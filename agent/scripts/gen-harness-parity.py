#!/usr/bin/env python3
"""Check or refresh harness settings in this checkout, not in HOME."""

import argparse
import json
import os
import stat
import sys
from pathlib import Path
from tempfile import NamedTemporaryFile


ROOT = Path(__file__).resolve().parents[2]
AGY = ROOT / "agent/harnesses/agy"
PI = ROOT / "agent/harnesses/pi"
CLAUDE_PROJECT = ROOT / "agent/project/claude"


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def check_output(path):
    if path.is_symlink() or path.parent.resolve() != path.parent:
        raise ValueError(f"refusing symlink at {path.relative_to(ROOT)}")
    if not path.parent.is_dir():
        raise ValueError(f"missing output directory: {path.parent.relative_to(ROOT)}")
    if path.exists() and not path.is_file():
        raise ValueError(f"not a regular file: {path.relative_to(ROOT)}")


def update_json(path, update):
    check_output(path)
    current = path.read_bytes()
    settings = json.loads(current)
    if not isinstance(settings, dict):
        raise ValueError(f"expected a JSON object in {path.relative_to(ROOT)}")
    updated = update(settings)
    return current if updated == json.loads(current) else json_bytes(updated)


def replace(path, data):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    with NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        tmp = Path(stream.name)
        try:
            stream.write(data)
            stream.close()
            tmp.chmod(mode)
            os.replace(tmp, path)
        finally:
            tmp.unlink(missing_ok=True)


def projections():
    root_mcp = ROOT / ".mcp.json"
    if root_mcp.exists() or root_mcp.is_symlink():
        raise ValueError("root .mcp.json conflicts with explicit Claude MCP opt-in")

    agy_servers = json.loads((AGY / "mcp_config.json").read_bytes())["mcpServers"]
    trail = agy_servers.pop("trail")
    if trail != {"command": "trail", "args": ["mcp"]}:
        raise ValueError("refusing to propagate an unreviewed Trail MCP command")

    def fill_trail(entry, expected, location):
        if (
            not isinstance(entry, dict)
            or any(key in entry and entry[key] != value for key, value in expected.items())
            or any(key in entry for key in ("url", "httpUrl"))
        ):
            raise ValueError(f"conflicting Trail MCP definition in {location}")
        entry.update(expected)

    def gemini(settings):
        entry = settings.setdefault("mcpServers", {}).setdefault("trail", {})
        fill_trail(entry, trail, ".gemini/settings.json")
        return settings

    def opencode(settings):
        settings.setdefault("$schema", "https://opencode.ai/config.json")
        entry = settings.setdefault("mcp", {}).setdefault("trail", {})
        fill_trail(
            entry, {"type": "local", "command": [trail["command"], *trail["args"]]}, "opencode.json"
        )
        if not isinstance(entry.setdefault("enabled", True), bool):
            raise ValueError("OpenCode Trail enabled must be a boolean")
        return settings

    def agy(settings):
        # Agy CLI reads mcp_config.json. Legacy settings mirror only non-Trail servers.
        settings["mcpServers"] = agy_servers
        return settings

    def pi_mcp(settings):
        entry = settings.setdefault("mcpServers", {}).setdefault("trail", {})
        fill_trail(entry, trail, "agent/harnesses/pi/mcp.json")
        return settings

    project = (CLAUDE_PROJECT / "settings.json").read_bytes()
    if not isinstance(json.loads(project), dict):
        raise ValueError("Claude project settings must be a JSON object")
    return {
        ROOT / ".claude/settings.json": project,
        # A local opt-in file, not root .mcp.json (some user policies auto-approve it).
        CLAUDE_PROJECT / "trail-mcp.json": json_bytes({"type": "stdio", **trail}),
        ROOT / ".gemini/settings.json": update_json(ROOT / ".gemini/settings.json", gemini),
        # Keep OpenCode's native entrypoint intact.
        ROOT / "opencode.json": update_json(ROOT / "opencode.json", opencode),
        AGY / "settings.json": update_json(AGY / "settings.json", agy),
        PI / "mcp.json": update_json(PI / "mcp.json", pi_mcp),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()

    try:
        outputs = projections()
        for path in outputs:
            check_output(path)
        stale = [path for path, data in outputs.items() if not path.is_file() or path.read_bytes() != data]
        for path in stale:
            if args.write:
                replace(path, outputs[path])
            print(f"{'updated' if args.write else 'stale'}: {path.relative_to(ROOT)}")
        if stale and args.check:
            print("Run: python3 agent/scripts/gen-harness-parity.py --write", file=sys.stderr)
            return 1
    except (OSError, AttributeError, KeyError, TypeError, ValueError) as exc:
        print(f"gen-harness-parity: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
