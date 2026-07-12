#!/usr/bin/env python3
"""Validate the dig skill's structural and routing invariants."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def extract_frontmatter(text: str) -> tuple[str, str]:
    match = re.match(r"\A---\n(?P<frontmatter>.*?)\n---\n(?P<body>.*)\Z", text, re.DOTALL)
    if match is None:
        fail("SKILL.md must contain a leading YAML frontmatter block")
    return match.group("frontmatter"), match.group("body")


def scalar(frontmatter: str, key: str) -> str | None:
    match = re.search(rf"(?m)^{re.escape(key)}:\s*(.+?)\s*$", frontmatter)
    if match is None:
        return None
    return match.group(1).strip().strip('"\'')


def require(text: str, needle: str, source: str) -> None:
    if needle not in text:
        fail(f"{source} is missing required content: {needle}")


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parents[1])
    skill_path = root / "SKILL.md"
    template_path = root / "task-template.md"

    if not skill_path.is_file() or not template_path.is_file():
        fail(f"expected SKILL.md and task-template.md under {root}")

    skill = skill_path.read_text(encoding="utf-8")
    template = template_path.read_text(encoding="utf-8")
    frontmatter, body = extract_frontmatter(skill)

    if scalar(frontmatter, "name") != "dig":
        fail("frontmatter name must be dig")
    if scalar(frontmatter, "disable-model-invocation") != "true":
        fail("dig must remain explicitly user-invoked")
    if scalar(frontmatter, "trigger") is not None:
        fail("trigger is not a supported Claude Code skill frontmatter field")

    description = scalar(frontmatter, "description")
    if not description:
        fail("frontmatter description is required")
    if len(description) > 1536:
        fail("description exceeds Claude Code's 1,536-character listing budget")
    if len(body.splitlines()) >= 500:
        fail("SKILL.md body must remain below 500 lines")

    for heading in (
        "## 2. モデルルーター",
        "## 3. 永続状態と再開",
        "## 4. Completion Contract",
        "## 8. 実装反復",
        "## 9. 失敗処理と停滞検知",
        "## 10. 完了評価",
    ):
        require(body, heading, "SKILL.md")

    for model in ("`haiku`", "`claude-sonnet-5`", "`opus`"):
        require(body, f"| {model} |", "model routing table")

    router = body.split("## 2. モデルルーター", 1)[1].split("## 3. 永続状態と再開", 1)[0]
    if "| `opusplan` |" in router or re.search(r"(?m)^\s*model:\s*opusplan\s*$", body):
        fail("unsupported opusplan model is configured for routing")
    require(body, "`/goal`", "SKILL.md")
    require(body, "`/loop`", "SKILL.md")
    require(body, "observe -> hypothesize -> act -> verify -> record", "SKILL.md")
    require(body, "[task-template.md](task-template.md)", "SKILL.md")

    for field in (
        "### Contract trace",
        "### Model routing",
        "### Observe",
        "### Hypothesis",
        "### Verify",
        "### Review policy",
        "### Completion evidence",
        "## Dependency map",
    ):
        require(template, field, "task-template.md")

    print(
        "PASS: dig skill validated "
        f"({len(body.splitlines())} body lines, {len(description)} description characters)"
    )


if __name__ == "__main__":
    main()
