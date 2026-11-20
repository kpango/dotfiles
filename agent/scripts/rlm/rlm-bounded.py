#!/usr/bin/env python3
"""Depth<=1 bounded RLM analyzer: chunked parallel Map-Reduce with an audit ledger.

Fail-closed: depth > 1, chunk overflow, bad input, or a missing model backend
all exit non-zero. This script never talks to an LLM API itself; the model layer
is the `BACKENDS` registry selected by env RLM_BACKEND:

  stub  offline and deterministic: counts the lines that contain the query ("count" kind).
  exec  runs a command you choose, once per chunk ("answer" kind). The command is a JSON
        argv array in env RLM_BACKEND_CMD (no shell; "{model}" is replaced by --model); the
        prompt arrives on stdin, so neither the query nor the chunk can reach argv. Examples:
          RLM_BACKEND=exec RLM_BACKEND_CMD='["claude","-p","--model","{model}"]'
        The child gets only PATH/HOME/LANG/LC_ALL/TMPDIR plus the names listed in
        RLM_BACKEND_PASS_ENV (comma separated) - nothing else of this environment, so a
        credential reaches the backend only when you name it. --sandbox runs the command
        through `pa-sandbox --` and fails closed when it is not installed.

Tests/other harnesses may register further backends via `BACKENDS` (give them a `kind`).

The ledger records that a run was attempted and passed its checks; it does not
guarantee that the result was delivered on stdout.
"""

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from typing import NoReturn
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from datetime import datetime, timezone
from pathlib import Path

MAX_DEPTH = 1
DEFAULT_MODEL = "deepseek-v4.1-flash"
MAX_CHUNK_BYTES = 64 * 1024 * 1024
MAX_CHUNKS_LIMIT = 4096
MAX_CONTEXT_BYTES = 256 * 1024 * 1024  # absolute read cap; data+chunks+texts ~4x in memory


def stub_backend(_model: str, query: str, chunk: str) -> dict:
    """Deterministic offline map step: count lines containing the query."""
    q = query.lower()
    hits = [ln for ln in chunk.splitlines() if q in ln.lower()]
    return {"hits": len(hits), "first": hits[0] if hits else None}


stub_backend.kind = "count"  # type: ignore[attr-defined]

MAX_ANSWER_BYTES = 4096
MAX_BACKEND_OUTPUT = 64 * 1024
MAX_ANSWERS_REPORTED = 16
CHARS_PER_TOKEN = 4  # rough heuristic used only for the --require-min-tokens gate
PASS_ENV_BASE = ("PATH", "HOME", "LANG", "LC_ALL", "TMPDIR")
# Set by _main() before any backend runs (module state, because backends are plain callables).
EXEC_SANDBOX = False
EXEC_TIMEOUT = 60


def exec_command(model: str) -> list:
    raw = os.environ.get("RLM_BACKEND_CMD", "")
    try:
        argv = json.loads(raw)
    except ValueError:
        raise BackendFailure("RLM_BACKEND_CMD must be a JSON array of non-empty strings") from None
    if not (isinstance(argv, list) and argv and all(isinstance(a, str) and a for a in argv)):
        raise BackendFailure("RLM_BACKEND_CMD must be a JSON array of non-empty strings")
    if model.startswith("-"):
        raise BackendFailure("--model must not start with '-' (it is substituted into the backend argv)")
    argv = [a.replace("{model}", model) for a in argv]
    if EXEC_SANDBOX:
        sandbox = shutil.which("pa-sandbox")
        if not sandbox:
            raise BackendFailure("--sandbox was requested but pa-sandbox is not in PATH (refusing to run unsandboxed)")
        argv = [sandbox, "--", *argv]
    return argv


def exec_backend(model: str, query: str, chunk: str) -> dict:
    """Run the configured command on one chunk. The answer is whatever it prints (UTF-8, bounded)."""
    argv = exec_command(model)
    names = list(PASS_ENV_BASE) + [n for n in os.environ.get("RLM_BACKEND_PASS_ENV", "").split(",") if n]
    env = {k: os.environ[k] for k in names if k in os.environ}
    prompt = (
        "You analyse ONE chunk of a larger log. Answer the query using only this chunk: reply with at most "
        "10 short lines that quote the evidence, or with exactly NONE when the chunk is irrelevant.\n"
        f"Query: {query}\n\n--- chunk ---\n{chunk}"
    )
    try:
        r = subprocess.run(
            argv,
            input=prompt.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=EXEC_TIMEOUT,
            shell=False,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise BackendFailure(f"backend command timed out after {EXEC_TIMEOUT}s") from None
    except OSError as e:
        raise BackendFailure(f"cannot run the backend command: {e}") from None
    if r.returncode != 0:
        tail = r.stderr[-200:].decode("utf-8", errors="replace").strip()
        raise BackendFailure(f"backend command exited {r.returncode}: {tail}")
    if len(r.stdout) > MAX_BACKEND_OUTPUT:
        raise BackendFailure(f"backend output is larger than {MAX_BACKEND_OUTPUT} bytes")
    try:
        return {"answer": r.stdout.decode("utf-8").strip()}
    except UnicodeDecodeError:
        raise BackendFailure("backend output is not valid UTF-8") from None


exec_backend.kind = "answer"  # type: ignore[attr-defined]

BACKENDS = {"stub": stub_backend, "exec": exec_backend}


MAX_FIRST_BYTES = 512
TRUNC_MARK = "...[truncated]"


class BackendFailure(Exception):
    pass


def fatal(msg: str, code: int = 2) -> NoReturn:
    """Report and hard-exit: running backend threads must not delay or block exit."""
    print(f"rlm-bounded: error: {msg}" if code == 2 else f"rlm-bounded: {msg}", file=sys.stderr)
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except (OSError, ValueError):
            pass  # stream already broken; nothing more we can report
    os._exit(code)


def call_backend(backend, model: str, query: str, text: str) -> dict:
    """Run one chunk; any BaseException (incl. SystemExit) from the backend is a failure."""
    try:
        return backend(model, query, text)
    except KeyboardInterrupt:
        raise  # reported as 'interrupted' (exit 130) by main()
    except BaseException as e:  # noqa: BLE001 - deliberate: SystemExit must not look like success
        raise BackendFailure(f"backend raised {type(e).__name__}: {e}") from None


def clip_text(text: str, limit: int) -> str:
    raw = text.encode("utf-8")
    if len(raw) <= limit:
        return text
    keep = limit - len(TRUNC_MARK)
    return raw[:keep].decode("utf-8", errors="ignore") + TRUNC_MARK


def clip_first(first: str) -> str:
    return clip_text(first, MAX_FIRST_BYTES)


def chunk_timeout() -> int:
    raw = os.environ.get("RLM_CHUNK_TIMEOUT", "60")
    if not raw.isascii() or not raw.isdigit() or int(raw) < 1:
        die(f"RLM_CHUNK_TIMEOUT must be a positive integer (seconds), got {raw!r}")
    return int(raw)


def die(msg: str, code: int = 2) -> NoReturn:
    print(f"rlm-bounded: error: {msg}", file=sys.stderr)
    sys.exit(code)


def depth_arg(value: str) -> int:
    try:
        n = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"--max-depth must be an integer, got {value!r}")
    if n < 1 or n > MAX_DEPTH:
        raise argparse.ArgumentTypeError(
            f"--max-depth must be 1 (hard cap {MAX_DEPTH}), got {n}"
        )
    return n


def bounded_int(upper: int):
    def parse(value: str) -> int:
        try:
            n = int(value)
        except ValueError:
            raise argparse.ArgumentTypeError(f"expected an integer, got {value!r}")
        if not 1 <= n <= upper:
            raise argparse.ArgumentTypeError(f"must be in 1..{upper}, got {value}")
        return n

    return parse


def split_chunks(data: bytes, chunk_bytes: int) -> list[bytes]:
    """Split only at newline boundaries (never mid-line / mid-character); fail closed
    when a line is longer than a chunk, since a mid-line split could drop matches."""
    chunks, pos = [], 0
    while pos < len(data):
        end = min(pos + chunk_bytes, len(data))
        if end < len(data):
            nl = data.rfind(b"\n", pos, end)
            if nl < 0:
                die("line longer than --chunk-bytes; increase --chunk-bytes")
            end = nl + 1
        chunks.append(data[pos:end])
        pos = end
    return chunks


def open_ledger(ledger_dir: str) -> int:
    """Validate the ledger dir/file and return an append-only fd. Rules: no symlink
    anywhere in the path, existing dir/file must be ours and private (never chmod'ed),
    file must be a single-link regular file."""
    uid = os.getuid()
    try:
        raw = os.path.abspath(ledger_dir)
        if os.path.realpath(raw) != os.path.normpath(raw):
            die(f"ledger dir {raw} contains a symlink (use its real path); refusing")
        if not os.path.lexists(raw):
            try:
                os.mkdir(raw, 0o700)  # last component only; parent must exist
            except FileExistsError:
                pass  # lost a creation race: fall through to the ownership/mode checks
            except FileNotFoundError:
                die(f"ledger parent directory {os.path.dirname(raw)} does not exist")
        dfd = os.open(raw, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            dst = os.fstat(dfd)
            if dst.st_uid != uid or dst.st_mode & 0o077:
                die(f"ledger dir {raw} must be owned by the current user with mode 0700-or-stricter")
            fd = os.open(
                "rlm-trace.jsonl",
                os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK,
                0o600,
                dir_fd=dfd,
            )
        finally:
            os.close(dfd)
        fst = os.fstat(fd)
        if (
            not stat.S_ISREG(fst.st_mode)
            or fst.st_uid != uid
            or fst.st_nlink != 1
            or fst.st_mode & 0o077
        ):
            os.close(fd)
            die("ledger file must be a regular file with a single link, private (0600-or-stricter), owned by the current user")
        return fd
    except OSError as e:
        die(f"ledger open failed ({ledger_dir}): {e}")


def append_ledger(fd: int, entry: dict) -> None:
    data = (json.dumps(entry) + "\n").encode()
    try:
        n = os.write(fd, data)
    except OSError as e:
        die(f"ledger write failed: {e}")
    if n != len(data):
        die(f"ledger short write ({n} of {len(data)} bytes)")


def nonblank(value: str) -> str:
    if not value.strip():
        raise argparse.ArgumentTypeError("--ledger-dir must not be blank")
    return value


def emit(text: str) -> None:
    """Write the result; on a broken stdout fail cleanly and neutralise the exit-time flush."""
    try:
        sys.stdout.write(text)
        sys.stdout.flush()
    except OSError as e:  # incl. BrokenPipeError, ENOSPC (/dev/full)
        try:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        except (OSError, ValueError):
            pass  # best effort only: stdout is already unusable, the message below is what matters
        die(f"cannot write result to stdout: {e}")


def _main() -> int:
    global EXEC_SANDBOX, EXEC_TIMEOUT
    p = argparse.ArgumentParser(description=(__doc__ or '').splitlines()[0])
    p.add_argument("--query", required=True)
    p.add_argument("--context-file", required=True)
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--max-depth", type=depth_arg, default=1)
    p.add_argument("--chunk-bytes", type=bounded_int(MAX_CHUNK_BYTES), default=65536)
    p.add_argument("--max-chunks", type=bounded_int(MAX_CHUNKS_LIMIT), default=64)
    p.add_argument("--ledger-dir", type=nonblank, default="/tmp/rlm-ledger")
    p.add_argument("--max-workers", type=bounded_int(16), default=8,
                   help="parallel chunk analyses (1..16, default 8)")
    p.add_argument("--cell-timeout", type=bounded_int(3600), default=None,
                   help="seconds allowed per chunk analysis (1..3600); default env RLM_CHUNK_TIMEOUT or 60")
    p.add_argument("--require-min-tokens", type=int, default=0,
                   help="exit 3 without doing anything when the context is below ~N tokens (bytes/4); "
                        "the deep audit is only worth its cost on very large inputs (rlm-deep-audit uses 200000)")
    p.add_argument("--sandbox", action="store_true",
                   help="run the exec backend command through `pa-sandbox --` (fails closed when pa-sandbox is missing)")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--json", action="store_true")
    args = p.parse_args()  # argparse exits 2 on invalid --max-depth
    if args.require_min_tokens < 0:
        die("--require-min-tokens must be >= 0")

    if not args.query:
        die("--query must not be empty")
    if args.query.splitlines() != [args.query]:
        die("query must be a single line (no line separators)")
    try:
        query_hash = hashlib.sha256(args.query.encode()).hexdigest()
    except UnicodeEncodeError:
        die("--query is not valid UTF-8")
    try:
        args.model.encode()
    except UnicodeEncodeError:
        die("--model is not valid UTF-8")

    # Bound the read by chunk-bytes * max-chunks (and a hard cap): oversize input is
    # rejected, not read. Only regular files; O_NONBLOCK so a FIFO can't hang open().
    limit = min(args.chunk_bytes * args.max_chunks, MAX_CONTEXT_BYTES)
    try:
        fd = os.open(args.context_file, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    except OSError as e:
        die(f"cannot read --context-file: {e}")
    try:
        size = os.fstat(fd).st_size if stat.S_ISREG(os.fstat(fd).st_mode) else -1
        if size < 0:
            die("--context-file must be a regular file (no FIFO/device/socket/symlink)")
        if size > limit:
            die(
                f"context is {size} bytes > min(--max-chunks {args.max_chunks} x "
                f"--chunk-bytes {args.chunk_bytes}, {MAX_CONTEXT_BYTES}) = {limit}; raise the limits"
            )
        with os.fdopen(fd, "rb", closefd=False) as f:
            data = f.read(size + 1)  # size <= limit here; never allocate more than the file needs
    except OSError as e:
        die(f"cannot read --context-file: {e}")
    finally:
        os.close(fd)
    if len(data) > size:
        die("context file grew while reading")
    if not data:
        die("--context-file is empty")
    if b"\0" in data:
        die("--context-file looks binary (NUL byte)")
    est_tokens = len(data) // CHARS_PER_TOKEN
    if args.require_min_tokens and est_tokens < args.require_min_tokens:
        fatal(
            f"context is ~{est_tokens} tokens, below --require-min-tokens {args.require_min_tokens}; "
            "read it directly instead of fanning out",
            3,
        )

    chunks = split_chunks(data, args.chunk_bytes)
    # Fail-closed: never silently truncate analysis input.
    if len(chunks) > args.max_chunks:
        die(
            f"context needs {len(chunks)} chunks > --max-chunks {args.max_chunks}; "
            "raise --chunk-bytes/--max-chunks"
        )

    result = {
        "query_sha256": query_hash,
        "model": args.model,
        "depth": 1,
        "chunks": len(chunks),
        "context_bytes": len(data),
        "dry_run": args.dry_run,
        "truncated": False,
    }

    backend = None
    backend_name = ""
    kind = "count"
    timeout = args.cell_timeout if args.cell_timeout is not None else chunk_timeout()
    if not args.dry_run:
        backend_name = os.environ.get("RLM_BACKEND", "")
        backend = BACKENDS.get(backend_name)
        if backend is None:
            die(
                f"no model backend available (RLM_BACKEND={backend_name!r}; "
                f"known: {sorted(BACKENDS)}); use RLM_BACKEND=stub (offline) or RLM_BACKEND=exec with RLM_BACKEND_CMD"
            )
        kind = getattr(backend, "kind", "count")
        if args.sandbox and backend_name != "exec":
            die("--sandbox only applies to the exec backend")
    EXEC_SANDBOX = args.sandbox
    EXEC_TIMEOUT = timeout

    # Validate the ledger before any model work so a bad ledger fails without compute.
    ledger_fd = open_ledger(args.ledger_dir)
    try:
        if backend is not None:
            texts = [c.decode("utf-8", errors="replace") for c in chunks]
            ex = ThreadPoolExecutor(max_workers=min(args.max_workers, len(texts)))
            try:
                futs = [ex.submit(call_backend, backend, args.model, args.query, t) for t in texts]
                maps = [f.result(timeout=timeout) for f in futs]  # timeout applies per chunk wait
            except FutureTimeout:
                fatal(f"chunk analysis timed out after {timeout}s")
            except BackendFailure as e:
                fatal(str(e))
            finally:
                ex.shutdown(wait=False, cancel_futures=True)
            if kind == "answer":
                answers = []
                for m in maps:
                    ans = m.get("answer") if isinstance(m, dict) else None
                    if not isinstance(ans, str):
                        die("invalid result from backend (need {'answer': str})")
                    if ans and ans.strip().upper() != "NONE":
                        answers.append(clip_text(ans, MAX_ANSWER_BYTES))
                result["backend"] = backend_name
                result["answered_chunks"] = len(answers)
                result["answers"] = answers[:MAX_ANSWERS_REPORTED]
                if len(answers) > MAX_ANSWERS_REPORTED:
                    result["truncated"] = True
                    result["answers_omitted"] = len(answers) - MAX_ANSWERS_REPORTED
                maps = []  # nothing left for the count-kind validation below
            for m, text in zip(maps, texts):
                hits = m.get("hits") if isinstance(m, dict) else None
                first = m.get("first") if isinstance(m, dict) else None
                ok = (
                    isinstance(hits, int)
                    and not isinstance(hits, bool)
                    and 0 <= hits <= len(text.splitlines())
                    and (hits == 0) == (first is None)
                    and (first is None or isinstance(first, str))
                )
                if ok and first is not None:
                    try:
                        first.encode("utf-8")
                    except UnicodeEncodeError:
                        ok = False
                    else:
                        # must be a real line of this chunk that actually matches the query
                        ok = first in text.splitlines() and args.query.lower() in first.lower()
                if not ok:
                    die("invalid result from backend (need {'hits': 0..lines, 'first': str|None}, first set iff hits > 0)")
            if kind != "answer":
                result["total_hits"] = sum(m["hits"] for m in maps)
                result["first_hits"] = [clip_first(m["first"]) for m in maps if m["first"] is not None][:5]

        append_ledger(
            ledger_fd,
            {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "depth": 1,
                "chunks": len(chunks),
                "model": args.model,
                "query_sha256": result["query_sha256"],
                "context_bytes": len(data),
                "dry_run": args.dry_run,
                "backend": backend_name,
                "kind": kind,
                "max_workers": min(args.max_workers, len(chunks)),
                "cell_timeout": timeout,
                "sandbox": bool(args.sandbox),
            },
        )
    finally:
        os.close(ledger_fd)

    if args.json:
        emit(json.dumps(result) + "\n")
    else:
        emit("".join(f"{k}: {v}\n" for k, v in result.items()))
    return 0


def main() -> int:
    """Single choke point: every failure becomes a clear message + exit 2, no traceback."""
    try:
        return _main()
    except KeyboardInterrupt:
        fatal("interrupted", 130)
    except MemoryError:
        die("out of memory while processing the context; lower the input size/limits")
    except Exception as e:  # incl. OSError, UnicodeError, backend failures (SystemExit passes through)
        die(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    sys.exit(main())
