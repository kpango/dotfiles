#!/usr/bin/env python3
"""jev_client — thin stdlib-only client for the Jev (TypeSafe) evaluation API.

Wire contract: POST <endpoint> {state, model: "jev-latest", questions: {id: Question}}
-> {model, answers: {id: Answer}, usage}. See:
  ~/.claude/session-data/swarm/missions/ai-env-deepresearch-overhaul/jev-api-reference.md

Design decisions this module implements (CONTEXT.md, "ai-env-deepresearch-overhaul"):
  - I-3 fail-to-deterministic: every failure mode (no key, disabled, timeout, HTTP error,
    malformed/invalid-schema response, disallowed endpoint, secret detected, oversized
    request/response) returns None instead of raising, so callers can always fall back to
    their deterministic behavior.
  - I-6 (redefined, CONTEXT.md Addendum 2 -- a regex-based scan was judged unable to
    guarantee exhaustive coverage, so the design now leans on transport instead):
    * By default, only a loopback endpoint (http:// on 127.0.0.1/localhost/[::1]) is
      ever sent to. A non-loopback endpoint -- including the official
      https://api.typesafe.ai -- requires `JEV_ALLOW_REMOTE` to be an explicit truthy
      value; if unset, `evaluate()` returns None without sending anything, no matter
      what `state`/`questions` contain.
    * Secret-shaped-substring/sensitive-key-name scanning (`_contains_secret_anywhere`,
      `_dict_has_secret_key`) only ever runs on the *remote* path -- a loopback target
      never leaves the machine, so scanning it can't prevent a leak and would only add
      false-positive risk to a same-host round-trip. This scan is deliberately
      best-effort on the remote path: it is not, and cannot be, a regex-complete
      guarantee against every way a secret could be shaped, so `JEV_ALLOW_REMOTE`
      (not this scan) is the primary control against secrets leaving the machine.
  - Loopback exception (added after the initial spec): an http:// endpoint on 127.0.0.1,
    localhost, or [::1] is allowed without an API key, so this same client also talks to a
    local self-hosted server implementing the same POST /v1/systemone wire protocol (e.g.
    Laya's laya-serve) when that server has no key configured. A non-loopback http:// or any
    endpoint override outside that exact allow-list is rejected outright (no request sent,
    key or not) rather than merely treated as "key optional", since the allow-list -- not
    reachability -- is what keeps the API key from leaking to an unintended host.
  - https:// is allowed ONLY when the host matches the default endpoint's host exactly
    (api.typesafe.ai); an https override to any other host is rejected the same way a
    disallowed http:// host is (fail closed, not "any TLS host is presumably safe").
  - Redirects are never followed (a 3xx could point anywhere and would otherwise replay
    the Authorization header to that new, unvalidated host) -- a dedicated opener with no
    redirect handler turns every 3xx into an immediate HTTPError.
  - Response reads use `read1()` (at most one underlying recv per call) against a
    `time.monotonic()` wall-clock deadline, shrinking the socket timeout each iteration,
    so a server that trickles bytes slowly enough to keep any single socket op under
    budget still can't keep the overall call alive past its timeout. Response size is
    separately capped.
  - The *entire* network operation (DNS resolution, connect, and reading the status
    line/headers -- not just the response body) runs inside a daemon worker thread;
    the calling thread only ever waits on that thread via a queue with the same
    overall deadline (see `_run_with_deadline`). This closes the gap `read1()` alone
    can't: `socket.getaddrinfo()` and the initial `http.client` status-line/header
    read have no way to have their timeout shrunk mid-flight the way body reads do,
    so without an outer thread-level deadline a server that trickles status/header
    bytes (or a slow DNS server) could keep the call alive well past its budget. The
    worker thread is never joined past the deadline -- it is daemonic, so it cannot
    outlive or block the calling (hook) process, and any result it eventually
    produces after the deadline is simply discarded.
  - The opener is built with an explicit empty `ProxyHandler({})`, overriding
    `build_opener()`'s default of auto-adding a `ProxyHandler(getproxies())`. Without
    this, `HTTP_PROXY`/`HTTPS_PROXY` in the environment would silently redirect an
    otherwise-validated request (including its Authorization header) to whatever
    host those variables name, bypassing the endpoint allow-list below entirely.
  - Endpoint validation checks the raw `netloc` against a strict character allow-list
    (alnum, `.`, `:`, `[`, `]`, `-`) before ever looking at scheme/hostname. `urlsplit`
    and the legacy parser urllib's own connection code uses internally can disagree
    on a netloc containing userinfo (`user@host`) or other unusual syntax; rejecting
    any netloc outside the allow-list up front means the allow/deny decision never
    depends on those two parsers agreeing.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

DEFAULT_ENDPOINT = "https://api.typesafe.ai/v1/systemone"
DEFAULT_TIMEOUT_MS = 800
DEFAULT_MODEL = "jev-latest"

# The only https:// host allowed (the official Jev API). Any other https host is
# rejected exactly like a disallowed http host -- TLS alone doesn't make a host trusted.
_DEFAULT_ENDPOINT_HOST = urlsplit(DEFAULT_ENDPOINT).hostname

# Loopback hosts eligible for the no-key exception; deliberately a literal allow-list
# (not "is this reachable / does it resolve to loopback") so a misconfigured endpoint
# such as 0.0.0.0 -- which some stacks also happen to route to the local machine --
# cannot silently qualify and carry the API key to the wrong listener.
_LOOPBACK_HOSTS = frozenset({"127.0.0.1", "localhost", "::1"})

# Request/response byte caps: bound both outbound size and the time spent regex-scanning
# for secrets (item 6), and bound how long/large a response we'll ever buffer (item 5).
_MAX_REQUEST_BYTES = 256 * 1024
_MAX_RESPONSE_BYTES = 1024 * 1024
_READ_CHUNK = 65536

# JEV_DISABLE must be an explicit truthy value; a bare non-empty string (e.g. "0", which
# is truthy in Python) must NOT be treated as "disabled".
_DISABLE_VALUES = frozenset({"1", "true", "yes"})

# JEV_ALLOW_REMOTE gates sending to any *non-loopback* endpoint (including the official
# https://api.typesafe.ai). Same truthy-value convention as JEV_DISABLE/_DISABLE_VALUES.
_ALLOW_REMOTE_VALUES = frozenset({"1", "true", "yes"})

# Strict character allow-list for a URL's `netloc` (host[:port], or userinfo@host[:port]
# in the raw component `urlsplit` gives us before any interpretation). Only alnum, '.',
# ':', '[', ']', and '-' are permitted -- notably '@' is not. `urlsplit(...).hostname`
# and the legacy parser urllib's own connection code uses internally can disagree on a
# netloc containing userinfo syntax (`user@host`); rejecting anything outside this
# allow-list up front means the allow/deny decision never depends on those two parsers
# agreeing with each other.
_NETLOC_ALLOWED = re.compile(r"^[A-Za-z0-9.:\[\]-]+$")

# ASCII-only boundary lookarounds, used everywhere below instead of `\b`. Python's `\b`
# treats any Unicode "word" character (ASCII letters/digits, '_', *and* non-ASCII
# letters like Japanese kana/kanji) as "adjacent to the token", so it fails to fire
# exactly where a secret is most likely to start/end in practice: immediately after an
# underscore (SECRET_KEY=..., a compound env-var-style name) or a non-ASCII character
# (full-width brackets/colons, surrounding prose in another script). These lookarounds
# only ever treat ASCII letters/digits as "word" characters, so both underscores and
# non-ASCII characters count as separators on either side.
_AB_START = r"(?<![A-Za-z0-9])"
_AB_END = r"(?![A-Za-z0-9])"

# Secret-shaped substrings scanned for on the remote path only (I-6, redefined -- see
# module docstring): best-effort, not a regex-complete guarantee. A false positive just
# means a deterministic fallback is used instead of a Jev call, which is the safe
# direction to err in, so these are deliberately over-inclusive.
_SECRET_PATTERNS = tuple(
    re.compile(p)
    for p in (
        r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----",
        _AB_START + r"AKIA[0-9A-Z]{16}" + _AB_END,
        _AB_START + r"(?:ghp|gho)_[A-Za-z0-9]{20,}",
        _AB_START + r"github_pat_[A-Za-z0-9_]{20,}",
        _AB_START + r"xox[abprs]-[0-9]+-[0-9]+-[A-Za-z0-9]+",
        # Body allows '_' and '-': real Anthropic/OpenAI keys mix both (sk-ant-api03-..._...).
        _AB_START + r"sk-ant-[A-Za-z0-9_-]{15,}",
        _AB_START + r"sk-proj-[A-Za-z0-9_-]{10,}",
        _AB_START + r"sk-[A-Za-z0-9]{20,}",  # no trailing boundary: body may run into "_..."
        _AB_START + r"eyJ[A-Za-z0-9_-]{5,}\.eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}",
        r"(?i)" + _AB_START + r"Authorization\s*:\s*Bearer\s+\S+",
        # Sensitive keyword, optionally continued by more identifier characters (so
        # SECRET_KEY=, AWS_SECRET_ACCESS_KEY=, MY_API_KEY= are all caught even though the
        # keyword itself isn't at the end of the identifier), optionally followed by a
        # closing quote (so a quoted-key assignment like `"password": "..."` is caught --
        # a literal `"` sits where plain `\s*` alone can't match), then the assignment
        # operator and an 8+-char non-space value.
        r"(?i)"
        + _AB_START
        + r"(?:api[-_ ]?key|password|passwd|secret|token|credential|authorization)"
        + r"[A-Za-z0-9_-]*['\"]?\s*[:=]\s*\S{8,}",
    )
)

# Dict key *name fragments* (normalized: lowercased, non-alnum stripped) treated as
# sensitive when their value is a string of any meaningful length. Needed because a
# JSON-serialized {"password": "..."} never puts the assignment operator directly after
# the keyword (the closing quote of the key sits in between), so the regexes above
# can't see it -- this walks the actual structure instead of the serialized text.
#
# Matched as a *substring* of the normalized key (not full-string equality): a key like
# "DB_PASSWORD" normalizes to "dbpassword", which never equals "password" outright but
# does contain it. Since a false positive here only means a deterministic fallback is
# used instead of a Jev call (the safe direction, per the module docstring's I-3), this
# is deliberately over-inclusive rather than requiring an exact key-name match.
_SENSITIVE_KEY_NAMES = frozenset(
    {
        "password",
        "passwd",
        "secret",
        "token",
        "apikey",
        "clientsecret",
        "credential",
        "authorization",
    }
)


def contains_secret(text: str) -> bool:
    """True if `text` contains a secret-shaped substring (key/token/password/PEM/etc.)."""
    if not isinstance(text, str):
        return False
    return any(p.search(text) for p in _SECRET_PATTERNS)


def _normalize_key(key: str) -> str:
    return re.sub(r"[^a-z0-9]", "", key.lower())


def _value_looks_secret_shaped(value) -> bool:
    """True if `value` is a string of meaningful length, or a list/tuple containing one
    (recursively) -- covers `{"password": [...]}` in addition to the plain
    `{"password": "..."}` case, since a sensitive key's value being a *collection* of
    credentials (e.g. a list of API keys) is just as much a leak as a single string."""
    if isinstance(value, str):
        return len(value) >= 8
    if isinstance(value, (list, tuple)):
        return any(_value_looks_secret_shaped(v) for v in value)
    return False


def _dict_has_secret_key(obj) -> bool:
    """Recursively check dict keys two independent ways, plus recurse into list/tuple
    containers and dict values:

    1. Key *name* signals what kind of value it holds (password, token, ...) even
       though the name itself isn't a secret -- `_SENSITIVE_KEY_NAMES` substring match
       against the normalized key, gated on the *value* looking secret-shaped (see
       `_value_looks_secret_shaped`) so an unrelated boolean flag like
       `"has_password": true` isn't flagged. Needed because a JSON-serialized
       `{"password": "..."}` never puts the assignment operator directly after the
       keyword (the closing quote of the key sits in between), so the flat
       `keyword[:=]value` pattern in `_SECRET_PATTERNS` can't see it.
    2. Key *content* -- the key's own literal text -- is itself scanned with
       `contains_secret()`, the same patterns used for ordinary string values,
       regardless of what the value is (e.g. a leaked AWS access key used as a dict
       key/label rather than a value).

    Non-str keys (Python allows int/float/bool/None as dict keys, and json.dumps
    silently stringifies them) are converted with `str()` before either check.
    """
    if isinstance(obj, dict):
        for key, value in obj.items():
            key_str = key if isinstance(key, str) else str(key)
            normalized = _normalize_key(key_str)
            if any(word in normalized for word in _SENSITIVE_KEY_NAMES) and _value_looks_secret_shaped(
                value
            ):
                return True
            if contains_secret(key_str):
                return True
            if _dict_has_secret_key(value):
                return True
        return False
    if isinstance(obj, (list, tuple)):
        return any(_dict_has_secret_key(item) for item in obj)
    return False


def _iter_strings(obj):
    """Yield every string found recursively within `obj` (dict values, list/tuple
    items, and `obj` itself if it is already a string).

    Deliberately walks the live Python structure instead of a JSON-serialized copy: the
    secret-shaped regexes above rely on ASCII-boundary lookarounds around punctuation
    like newlines, tabs, and non-ASCII characters, but `json.dumps` escapes exactly
    those (`\\n`, `\\t`, `\\uXXXX` by default), turning what was a boundary character in
    the real value into an ordinary ASCII letter/hex digit in the serialized text --
    which would silence the boundary check right where a secret starts. Scanning the
    raw strings themselves sidesteps that escaping entirely. Dict *keys* are
    intentionally not yielded here -- key content and key names are both checked
    separately by `_dict_has_secret_key`.
    """
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for value in obj.values():
            yield from _iter_strings(value)
    elif isinstance(obj, (list, tuple)):
        for item in obj:
            yield from _iter_strings(item)


def _contains_secret_anywhere(state, questions) -> bool:
    """Best-effort scan of the remote path only (I-6, redefined -- see module
    docstring): not a regex-complete guarantee against every way a secret could be
    shaped. `JEV_ALLOW_REMOTE` is the primary control; this is defense in depth."""
    if _dict_has_secret_key(state) or _dict_has_secret_key(questions):
        return True
    return any(contains_secret(s) for s in _iter_strings(state)) or any(
        contains_secret(s) for s in _iter_strings(questions)
    )


def _int_env(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _jev_disabled() -> bool:
    raw = os.environ.get("JEV_DISABLE")
    return raw is not None and raw.strip().lower() in _DISABLE_VALUES


def _remote_allowed() -> bool:
    """True only if JEV_ALLOW_REMOTE is an explicit truthy value. Gates every
    *non-loopback* endpoint (I-6, redefined -- see module docstring): unset means
    nothing is ever sent to a remote endpoint, regardless of what state/questions
    contain."""
    raw = os.environ.get("JEV_ALLOW_REMOTE")
    return raw is not None and raw.strip().lower() in _ALLOW_REMOTE_VALUES


def _endpoint_loopback_status(url: str):
    """Return (allowed, is_loopback) for `url`. https is allowed only for the default
    endpoint's own host; http is allowed only for the literal loopback allow-list;
    anything else (including any other https host) is rejected outright."""
    parsed = urlsplit(url)
    if not _NETLOC_ALLOWED.match(parsed.netloc or ""):
        return False, False
    if parsed.scheme == "https" and parsed.hostname == _DEFAULT_ENDPOINT_HOST:
        return True, False
    if parsed.scheme == "http" and parsed.hostname in _LOOPBACK_HOSTS:
        return True, True
    return False, False


def _valid_unit_value(val) -> bool:
    """True for a real (non-bool) number in [0, 1]; also rejects NaN (comparisons
    against NaN are always False in Python, so the range check fails on its own)."""
    return isinstance(val, (int, float)) and not isinstance(val, bool) and 0 <= val <= 1


def _validate_answer(question: dict, answer) -> bool:
    if not isinstance(answer, dict) or not isinstance(question, dict):
        return False
    qtype = question.get("type")
    if answer.get("type") != qtype:
        return False

    if qtype == "noul":
        return _valid_unit_value(answer.get("noul"))

    if qtype == "choice":
        criteria = question.get("criteria")
        if not isinstance(criteria, dict) or answer.get("choice") not in criteria:
            return False
        return _valid_unit_value(answer.get("confidence"))

    if qtype == "score":
        criteria = question.get("criteria")
        if not isinstance(criteria, list) or not criteria:
            return False
        val = answer.get("score")
        if not isinstance(val, (int, float)) or isinstance(val, bool):
            return False
        if not (0 <= val <= len(criteria) - 1):
            return False
        return _valid_unit_value(answer.get("confidence"))

    return False


def _all_answers_valid(questions: dict, answers: dict) -> bool:
    for qid, question in questions.items():
        if qid not in answers or not _validate_answer(question, answers[qid]):
            return False
    return True


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Returning None means "do not follow"; urllib then raises the 3xx as a plain
        # HTTPError instead. A redirect could point anywhere, and would otherwise replay
        # our Authorization header to that new, unvalidated host verbatim.
        return None


# Built once: a single opener with (a) the default HTTPRedirectHandler replaced by one
# that refuses to follow any redirect, and (b) an explicit empty ProxyHandler({}) that
# overrides build_opener()'s default of auto-adding ProxyHandler(getproxies()) --
# otherwise HTTP_PROXY/HTTPS_PROXY in the environment would silently redirect an
# already-validated request (Authorization header included) to whatever host those
# variables name, bypassing the endpoint allow-list entirely.
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirectHandler)


def _read_within_deadline(resp, deadline: float) -> bytes:
    """Read `resp` in chunks, bounded by both an overall wall-clock deadline and a max
    size. Uses read1() (at most one underlying recv per call) rather than read(), which
    on a BufferedIOBase loops internally until it fills the requested size or hits EOF --
    i.e. it would keep blocking past our deadline against a server that trickles bytes
    slowly enough to keep any single recv() under budget."""
    chunks = []
    total = 0
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("jev response deadline exceeded")
        sock = getattr(getattr(resp, "fp", None), "raw", None)
        sock = getattr(sock, "_sock", None)
        if sock is not None:
            try:
                sock.settimeout(remaining)
            except OSError:
                pass
        chunk = resp.read1(_READ_CHUNK)
        if not chunk:
            break
        total += len(chunk)
        if total > _MAX_RESPONSE_BYTES:
            raise ValueError("jev response exceeds max size")
        chunks.append(chunk)
    return b"".join(chunks)


def _network_call(request, timeout_s, deadline):
    """Open `request` and read its body, entirely inside whatever thread calls this
    (see `_run_with_deadline`). Raises on any failure (HTTPError, URLError, OSError,
    ValueError, or the TimeoutError/ValueError `_read_within_deadline` raises past the
    deadline/size cap) -- the caller treats every exception identically as "no result"."""
    try:
        resp = _OPENER.open(request, timeout=timeout_s)
    except urllib.error.HTTPError as exc:
        exc.close()  # avoid a ResourceWarning; body is discarded, we only need "fail"
        raise
    try:
        return _read_within_deadline(resp, deadline)
    finally:
        resp.close()


def _run_with_deadline(fn, deadline: float):
    """Run `fn()` in a daemon worker thread; wait for it only until `deadline` (a
    `time.monotonic()` timestamp). Returns (True, value) on success, (False, None) on
    any failure or if `deadline` passes first.

    This is what bounds DNS resolution and connect/header reads (not just the response
    body `_read_within_deadline` already bounds): neither `socket.getaddrinfo()` nor
    `http.client`'s initial status-line/header read can have their timeout shrunk
    mid-flight the way `_read_within_deadline` shrinks the body-read timeout each
    iteration, so a slow DNS server or a peer that trickles status/header bytes could
    otherwise keep a single-threaded call alive well past its budget.

    The worker thread is never joined past `deadline` -- it is a daemon thread, so it
    cannot outlive or block the calling (hook) process, and whatever it eventually
    produces after we stop waiting is simply discarded.
    """
    result_queue: "queue.Queue" = queue.Queue(maxsize=1)

    def worker():
        try:
            result_queue.put(("ok", fn()))
        except Exception as exc:  # noqa: BLE001 - every failure collapses to "no result"
            result_queue.put(("error", exc))

    threading.Thread(target=worker, daemon=True).start()

    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return False, None
    try:
        status, value = result_queue.get(timeout=remaining)
    except queue.Empty:
        return False, None
    if status != "ok":
        return False, None
    return True, value


def evaluate(state, questions, *, timeout=None, api_key=None, endpoint=None):
    """POST `state`/`questions` to the Jev endpoint; return {qid: Answer} or None.

    None covers every failure mode by design (I-3): disabled, no key, secret detected,
    disallowed endpoint, oversized request/response, redirect, timeout, HTTP error,
    malformed body, schema mismatch, or any other unexpected exception. Never raises.
    """
    try:
        if _jev_disabled():
            return None

        try:
            body = {"state": state, "model": DEFAULT_MODEL, "questions": questions}
            payload = json.dumps(body).encode("utf-8")
        except (TypeError, ValueError):
            return None

        if len(payload) > _MAX_REQUEST_BYTES:
            return None

        url = endpoint or os.environ.get("TYPESAFE_API_URL") or DEFAULT_ENDPOINT
        allowed, loopback = _endpoint_loopback_status(url)
        if not allowed:
            return None

        # I-6, redefined (CONTEXT.md Addendum 2): loopback never leaves the machine, so
        # it is sent unconditionally, without a secret scan (see module docstring / the
        # `_contains_secret_anywhere` and `_remote_allowed` docstrings for why). Any
        # non-loopback endpoint -- including the official https default -- requires an
        # explicit opt-in, checked before the (best-effort) secret scan runs at all.
        if not loopback:
            if not _remote_allowed():
                return None
            if _contains_secret_anywhere(state, questions):
                return None

        key = api_key if api_key is not None else os.environ.get("TYPESAFE_API_KEY")
        if not key and not loopback:
            return None

        timeout_ms = timeout if timeout is not None else _int_env("JEV_TIMEOUT_MS", DEFAULT_TIMEOUT_MS)
        timeout_s = max(timeout_ms, 0) / 1000.0

        headers = {"Content-Type": "application/json"}
        if key:
            headers["Authorization"] = "Bearer %s" % key

        request = urllib.request.Request(url, data=payload, headers=headers, method="POST")

        deadline = time.monotonic() + timeout_s
        ok, raw = _run_with_deadline(lambda: _network_call(request, timeout_s, deadline), deadline)
        if not ok:
            return None

        try:
            parsed = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None

        answers = parsed.get("answers") if isinstance(parsed, dict) else None
        if not isinstance(answers, dict) or not _all_answers_valid(questions, answers):
            return None

        return {qid: answers[qid] for qid in questions}
    except Exception:
        return None


def noul(state, instructions, **kwargs):
    """Convenience wrapper: ask a single yes/no question, return its probability or None."""
    result = evaluate(state, {"q": {"type": "noul", "instructions": instructions}}, **kwargs)
    return None if result is None else result["q"]["noul"]


def choice(state, instructions, options, **kwargs):
    """Convenience wrapper: pick one of `options`, return (choice, confidence) or None."""
    criteria = {opt: None for opt in options}
    result = evaluate(
        state,
        {"q": {"type": "choice", "instructions": instructions, "criteria": criteria}},
        **kwargs,
    )
    return None if result is None else (result["q"]["choice"], result["q"]["confidence"])


def score(state, instructions, levels, **kwargs):
    """Convenience wrapper: rate along `levels`, return (score, confidence) or None."""
    result = evaluate(
        state,
        {"q": {"type": "score", "instructions": instructions, "criteria": list(levels)}},
        **kwargs,
    )
    return None if result is None else (result["q"]["score"], result["q"]["confidence"])


# ---------------------------------------------------------------------------
# CLI: python3 jev_client.py noul|choice|score --instructions ... [--options a,b,c |
#      --levels a,b,c] < state
# ---------------------------------------------------------------------------


def _build_question(kind: str, instructions: str, options, levels) -> dict:
    if kind == "noul":
        return {"type": "noul", "instructions": instructions}
    if kind == "choice":
        opts = [o.strip() for o in (options or "").split(",") if o.strip()]
        return {"type": "choice", "instructions": instructions, "criteria": {o: None for o in opts}}
    # kind == "score" (argparse `choices` already rules out anything else)
    lvls = [l.strip() for l in (levels or "").split(",") if l.strip()]
    return {"type": "score", "instructions": instructions, "criteria": lvls}


def main(argv=None) -> int:
    # argparse.parse_args() calls sys.exit() (raising SystemExit) on bad/missing
    # arguments -- that's the standard CLI contract for a usage error and must pass
    # through untouched, so it is deliberately outside the try/except below (which is
    # only for turning an *unexpected* runtime failure, per I-3, into the same
    # {"available": false} exit-3 contract evaluate() failures already use).
    parser = argparse.ArgumentParser(prog="jev_client")
    parser.add_argument("kind", choices=("noul", "choice", "score"))
    parser.add_argument("--instructions", required=True)
    parser.add_argument("--options", default=None, help="comma-separated options (choice)")
    parser.add_argument("--levels", default=None, help="comma-separated levels (score)")
    args = parser.parse_args(argv)

    try:
        # Read raw bytes and decode leniently: sys.stdin.read() uses strict decoding
        # under the process's locale encoding and raises UnicodeDecodeError on
        # malformed input, which would otherwise crash the CLI (exit 1, traceback on
        # stderr) instead of following the same fail-to-deterministic contract as
        # every other failure mode here.
        state = sys.stdin.buffer.read().decode("utf-8", errors="replace")
        question = _build_question(args.kind, args.instructions, args.options, args.levels)
        result = evaluate(state, {"q": question})

        if result is None:
            print(json.dumps({"available": False}))
            return 3

        print(json.dumps(result["q"]))
        return 0
    except Exception:
        print(json.dumps({"available": False}))
        return 3


if __name__ == "__main__":
    sys.exit(main())
