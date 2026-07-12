#!/usr/bin/env python3
"""Validate the dig skill's structural and routing invariants."""

from __future__ import annotations

import re
import sys
import json
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
    evals_path = root / "evals" / "evals.json"
    skills_root = root.parent
    graph_skill_path = skills_root / "graph-explore" / "SKILL.md"
    graph_evals_path = skills_root / "graph-explore" / "evals" / "evals.json"
    improve_skill_path = skills_root / "dig-improve" / "SKILL.md"
    improve_evals_path = skills_root / "dig-improve" / "evals" / "evals.json"

    if not skill_path.is_file() or not template_path.is_file() or not evals_path.is_file():
        fail(f"expected SKILL.md, task-template.md, and evals/evals.json under {root}")

    skill = skill_path.read_text(encoding="utf-8")
    template = template_path.read_text(encoding="utf-8")
    try:
        evals = json.loads(evals_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid evals/evals.json: {error}")
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
    require(body, "[evals/evals.json](evals/evals.json)", "SKILL.md")
    require(body, "CLAUDE_CODE_SUBAGENT_MODEL", "SKILL.md")
    require(body, "Claude Code v2.1.197", "SKILL.md")
    require(body, 'graph-explore "$ARGUMENTS"', "SKILL.md")
    require(body, 'dig-improve "$DIG_STATE_DIR"', "SKILL.md")
    require(body, "## 11. 自己改善ループ", "SKILL.md")

    for field in (
        "### Contract trace",
        "### Model routing",
        "### Execution form",
        "### Graph context",
        "### Observe",
        "### Hypothesis",
        "### Verify",
        "### Review policy",
        "### Completion evidence",
        "## Dependency map",
        "### Post-task improvement signal",
    ):
        require(template, field, "task-template.md")

    if evals.get("skill_name") != "dig":
        fail("evals skill_name must be dig")
    cases = evals.get("evals")
    if not isinstance(cases, list) or len(cases) < 8:
        fail("evals/evals.json must contain at least eight behavioral cases")
    ids: set[int] = set()
    for case in cases:
        if not isinstance(case, dict):
            fail("every eval case must be an object")
        case_id = case.get("id")
        if not isinstance(case_id, int) or case_id in ids:
            fail("eval IDs must be unique integers")
        ids.add(case_id)
        prompt = case.get("prompt")
        expectations = case.get("expectations")
        if not isinstance(prompt, str) or not prompt.startswith("/dig"):
            fail(f"eval {case_id} prompt must explicitly invoke /dig")
        if not isinstance(expectations, list) or len(expectations) < 3:
            fail(f"eval {case_id} must define at least three expectations")

    for sibling_path, sibling_evals_path, expected_name in (
        (graph_skill_path, graph_evals_path, "graph-explore"),
        (improve_skill_path, improve_evals_path, "dig-improve"),
    ):
        if not sibling_path.is_file() or not sibling_evals_path.is_file():
            fail(f"missing sibling skill or evals for {expected_name}")
        sibling = sibling_path.read_text(encoding="utf-8")
        sibling_frontmatter, sibling_body = extract_frontmatter(sibling)
        if scalar(sibling_frontmatter, "name") != expected_name:
            fail(f"frontmatter name must be {expected_name}")
        if scalar(sibling_frontmatter, "context") != "fork":
            fail(f"{expected_name} must use an isolated forked context")
        if scalar(sibling_frontmatter, "user-invocable") != "false":
            fail(f"{expected_name} must remain internal-only")
        if len(sibling_body.splitlines()) >= 500:
            fail(f"{expected_name} SKILL.md body must remain below 500 lines")
        try:
            sibling_evals = json.loads(sibling_evals_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            fail(f"invalid {expected_name} evals: {error}")
        if sibling_evals.get("skill_name") != expected_name:
            fail(f"{expected_name} evals skill_name mismatch")
        sibling_cases = sibling_evals.get("evals")
        if not isinstance(sibling_cases, list) or len(sibling_cases) < 4:
            fail(f"{expected_name} must define at least four behavioral evals")

    graph_frontmatter, _ = extract_frontmatter(graph_skill_path.read_text(encoding="utf-8"))
    if scalar(graph_frontmatter, "agent") != "Explore" or scalar(graph_frontmatter, "model") != "haiku":
        fail("graph-explore must run with the forked Explore agent on haiku")
    improve_frontmatter, improve_body = extract_frontmatter(
        improve_skill_path.read_text(encoding="utf-8")
    )
    if scalar(improve_frontmatter, "agent") != "Plan":
        fail("dig-improve must use the forked Plan agent")
    if scalar(improve_frontmatter, "model") != "claude-sonnet-5":
        fail("dig-improve must request claude-sonnet-5")
    require(improve_body, '"apply": false', "dig-improve SKILL.md")
    require(improve_body, "2 independent runs", "dig-improve SKILL.md")

    print(
        "PASS: dig skill validated "
        f"({len(body.splitlines())} body lines, {len(description)} description characters)"
    )


if __name__ == "__main__":
    main()
