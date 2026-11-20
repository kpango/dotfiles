#!/usr/bin/env python3
"""Fetch the model lists that harness CLIs report, cache them for this run.

Usage: fetch-harness-models.py {omp,agy} [...]

Writes <cache>/<cli>.json as {"cli", "status", "fetched_at", "models", "reason"?}.
status is "ok" only when the CLI answered and its output parsed to a non-empty list.
Anything else rewrites the cache as "unavailable" with empty models, so a previous
run's list can never be reused as if it were fresh. Consumers fail closed on that.

Cache dir: $AGENT_MODEL_LIST_DIR, else $XDG_CACHE_HOME/agent-model-lists, else
~/.cache/agent-model-lists.

Model ids are provider-qualified: omp -> "provider/id" selectors (anthropic,
openai-codex, opencode-go, ollama), agy -> "antigravity-cli/<base id>".
Claude and Hermes have no verified list command, so they are not fetched here.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

TIMEOUT_S = 30
EFFORT_SUFFIX = re.compile(r"-(minimal|low|medium|high|xhigh|max)$")


def parse_omp(stdout: str) -> list[str]:
    data = json.loads(stdout)
    return sorted({m["selector"] for m in data.get("models", []) if m.get("kind") == "chat" and m.get("selector")})


def parse_agy(stdout: str) -> list[str]:
    out = set()
    for line in stdout.splitlines():
        # Table rows are "<id>\t<display name>"; anything else (e.g. "Fetching ...") is noise.
        if "\t" not in line:
            continue
        model_id = line.split("\t", 1)[0].strip()
        if not model_id or "orchestrator" in model_id:
            continue
        out.add(f"antigravity-cli/{EFFORT_SUFFIX.sub('', model_id)}")
    return sorted(out)


CLIS = {
    "omp": (["omp", "models", "--json", "--no-extensions"], parse_omp),
    "agy": (["agy", "models"], parse_agy),
}


def cache_dir(env=os.environ) -> Path:
    if env.get("AGENT_MODEL_LIST_DIR"):
        return Path(env["AGENT_MODEL_LIST_DIR"])
    base = env.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "agent-model-lists"


def _unavailable(reason: str) -> dict:
    return {"status": "unavailable", "models": [], "reason": reason}


def fetch_one(cli: str, runner=subprocess.run) -> dict:
    argv, parse = CLIS[cli]
    try:
        proc = runner(argv, capture_output=True, text=True, timeout=TIMEOUT_S, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return _unavailable(f"{type(exc).__name__}: {exc}")
    if proc.returncode != 0:
        return _unavailable(f"exit {proc.returncode}")
    try:
        models = parse(proc.stdout)
    except (ValueError, KeyError, TypeError) as exc:
        return _unavailable(f"unparseable output: {exc}")
    if not models:
        return _unavailable("empty model list")
    return {"status": "ok", "models": models}


def write_cache(directory: Path, cli: str, result: dict) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    record = {"cli": cli, "fetched_at": time.time(), **result}
    tmp = directory / f".{cli}.{os.getpid()}.tmp"
    tmp.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, directory / f"{cli}.json")  # atomic: concurrent subagent spawns share this file


def main(argv: list[str]) -> int:
    unknown = [c for c in argv if c not in CLIS]
    if not argv or unknown:
        sys.stderr.write(f"usage: fetch-harness-models.py {{{','.join(CLIS)}}} [...] (unknown: {unknown})\n")
        return 2
    directory = cache_dir()
    summary = {}
    for cli in argv:
        result = fetch_one(cli)
        write_cache(directory, cli, result)
        summary[cli] = {"status": result["status"], "count": len(result["models"])}
        if result["status"] != "ok":
            sys.stderr.write(f"fetch-harness-models: {cli} unavailable: {result['reason']}\n")
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
