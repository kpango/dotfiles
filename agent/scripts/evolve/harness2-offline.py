#!/usr/bin/env python3
"""Harness² (arXiv:2610.14224) offline self-evolution pipeline.

Stages (each candidate is rejected at the first stage whose guard fails):
  1. Trace collector: cluster failure traces by root-cause signature; clusters with fewer than
     --min-occurrences (default 3) records are noise and are dropped.
  2. C1-C8 classification and INV (task-invariant, seen in >=2 distinct tasks) vs DOM (single task).
  3. Net Token Budget: always-loaded components (C1, C2, C4, C6) need delta_tokens <= 0, charged by
     file size. That is a LOCAL conservative law, stricter than upstream (which caps only the always-on
     text and never charges a skill body); C6 also reports advertised_delta_tokens, the name+description
     projection actually injected every turn, for visibility only. C6 additionally needs <= 500 lines
     and description <= 160 chars.
  3.5 Harness tree (upstream harness2/core/tree.py): the candidate is applied to the whole surface tree and
     validated (frontmatter, name/dir match, always-on cap, script refs, *.py compile). Only errors the
     candidate INTRODUCES are counted, so a pre-existing baseline defect cannot block every edit.
  4. Contrastive probes split deterministically into Training / Held-Out (no Held-Out regression),
     then the Security Monotonicity Gate (subprocesses; any non-zero exit rejects).
  5. Experience reflector: append SHA-256-deduplicated entries to EXPERIENCE.md (append only), write
     accepted candidates as unified diffs, and merge every accepted diff into one composed.diff that is
     re-validated as a whole (conflicting or collectively broken batches fall back). Proposal targets are
     NEVER written; applying a diff needs human approval. `--check-tree` validates the surface alone.

Upstream mapping (google-research/harness2 @ 68688175):
  harness2/core/tree.py SurfaceSpec/read_tree/validate/diff_summary/diversity -> SurfaceSpec, read_tree,
    validate_tree, diff_summary, diversity (the dotfiles OMP surface: flat walk, always-on cap opt-in
    via --always-on-cap, no hooks schema).
  harness2/core/tree.py is_allowed -> on_surface() (prefix surfaces); absolute paths, `..` and `\\` are rejected
  before it reaches any surface check.
  recursion.py invalid-proposal retry then inherit -> Compose fallback (same-path candidates keep the
    current harness) and whole-batch re-validation.
  library.py EXPERIENCE.md chaining -> stage 5 append + SHA-256 dedup (no session ids, no locks).
  NOT PORTED (model-dependent or external runners): recursion.py rollout/improve stages, selection.py
    anonymised pairwise selection, judge.py, spec.py channels, runmark.py, the substrate runners.
    compose() replaces the human "apply one diff" step deterministically; a human still applies it.

Input formats
  --traces      JSONL, one object per line (blank lines ignored):
                {"signature": str, "task": str, "target": repo-relative path, "message"?: str}
  --candidates  JSON array of:
                {"id": [A-Za-z0-9._-]{1,64} (unique), "signature": str (must match a kept cluster),
                 "target": repo-relative path, "new_text": str (full replacement text),
                 "category"?: "A" (Domain Learning, .trail/) | "B" (Skill Refinement, skills/) |
                              "C" (Harness/Routing/Context Config: harnesses/ models/ hooks/ extensions/);
                              when given it must match the category derived from target (else rejected
                              with category_mismatch); results always carry the derived "category",
                 "probes": [{"name": str (unique), "before": bool, "after": bool}, ...]}
                A probe records whether a held-out/training scenario passed before/after the change.

Token estimate: tokens = ceil(UTF-8 bytes / 4) (deterministic; byte based so CJK cannot hide growth).
Held-Out policy: any Held-Out regression rejects; Training regressions are reported
(training_regressions / training_fixes) and reject when they outnumber Training fixes. The split seed
defaults to the SHA-256 of the traces input (reproducible) and can be set with --seed.
Security gate: the baseline tree (--repo-root) must pass once, otherwise every candidate is rejected
(security_gate_baseline). Then, per candidate, agent/ is copied to a temp dir, the candidate is applied
there, and the gate runs against the copy (cwd, HARNESS2_REPO_ROOT and `{root}` in the command point
at it; the copy is always removed). The gate executes the candidate's code (e.g. *.py / *.ts), so it
ALWAYS runs inside a bwrap sandbox (no network, own namespaces, read-only system, size-limited tmpfs
/tmp and HOME, only HARNESS2_REPO_ROOT/PATH/HOME/TMPDIR/locale variables, RLIMIT_FSIZE/NPROC/AS/CORE, the
candidate copy writable but capped in total size, the baseline tree read-only) BEFORE any human approval.
The host /proc is never exposed: a fresh procfs is used; if the environment refuses one (containers) the run
fails closed unless --gate-empty-proc selects an empty /proc (tools needing /proc/self, e.g. bun, then fail).
When no sandbox can be created the run fails closed (exit 2); --allow-unsandboxed-gate opts out with a
warning on stderr and in the JSON report. Gate commands are replaceable (tests) via repeated
--security-cmd or the HARNESS2_SECURITY_CMDS env var (newline separated, must not be blank); the
override is honoured in production too and reported as security_gate.overridden / commands and as a
stderr warning. (pa-sandbox is not used: it is built around a writable workspace and git metadata
protection for agent harnesses, not around a throw-away read-only gate run.)
Write order: all validation and diffs are built in memory first, diffs are then written via temp file +
os.replace (symlinks are replaced, never followed), and EXPERIENCE.md is appended last under flock
(opened with O_NOFOLLOW, regular files only) so a failure never leaves a partial state.
Strings used in output/classification (signature, task, target, id, probe names, message) and new_text
reject control/C1 characters, U+2028/U+2029, invisible and bidi characters and lone surrogates (exit 2);
new_text may contain LF and TAB only. Lines are split on LF everywhere (never str.splitlines).

Fail-Closed: invalid input / unreadable file / schema violation -> message on stderr, exit 2.
Exit 0 otherwise (candidate rejections are results, not errors).
"""

from __future__ import annotations

import argparse
import collections
import datetime
import difflib
import errno
import fcntl
import hashlib
import json
import os
import re
import resource
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata
from pathlib import Path, PurePosixPath
from typing import NamedTuple

try:  # optional: when present, SKILL.md frontmatter is cross-checked against a real YAML parser
    import yaml
except ImportError:
    yaml = None
if os.environ.get("HARNESS2_NO_YAML"):
    yaml = None  # force the conservative PyYAML-free mode (also used by the tests)

MAX_INPUT_BYTES = 1 << 20
MAX_TRACES = 10_000
MAX_CANDIDATES = 200
MAX_PROBES = 200
MAX_NEW_TEXT_CHARS = 256 * 1024
SKILL_MAX_LINES = 500
DESC_MAX_CHARS = 160
ALWAYS_LOADED = frozenset({"C1", "C2", "C4", "C6"})
GATE_TIMEOUT_SEC = 300
DEFAULT_OUT_DIR = Path.home() / ".claude/session-data/swarm/evolve-proposals"
ID_RE = re.compile(r"[A-Za-z0-9._-]{1,64}")  # used with fullmatch ($ would accept a trailing LF)
_UNSAFE_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))
# invisible characters that Unicode classifies as letters/marks/symbols: hangul/khmer fillers, braille blank, CGJ, musical null notehead
_EXTRA_INVISIBLE = frozenset((0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x2800, 0x3164, 0xFFA0, 0x1D159))
_ASCII_BAD = {"strict": re.compile("[\x00-\x1f\x7f]"), "text": re.compile("[\x00-\x08\x0b-\x1f\x7f]"), "msg": None}


def unsafe_char(ch: str) -> bool:
    """Control, format, surrogate, private-use, unassigned, line/paragraph separators, non-ASCII spaces,
    variation selectors and the explicit invisible letters above (by Unicode category, not by ranges)."""
    o = ord(ch)
    cat = unicodedata.category(ch)
    if cat in _UNSAFE_CATEGORIES:
        return True
    if cat == "Zs":
        return ch != " "
    if cat == "Mn" and (0xFE00 <= o <= 0xFE0F or 0xE0100 <= o <= 0xE01EF or 0x180B <= o <= 0x180D):
        return True
    return o in _EXTRA_INVISIBLE


def has_unsafe(s: str, mode: str = "strict") -> bool:
    """mode strict: everything unsafe_char rejects; text (new_text): LF and TAB are allowed;
    msg (trace message): controls and line separators are allowed here and sanitized when rendered."""
    if s.isascii():
        r = _ASCII_BAD[mode]
        return bool(r and r.search(s))
    for ch in s:
        if ord(ch) < 128:
            if mode == "strict" and (ch < " " or ch == "\x7f"):
                return True
            if mode == "text" and ((ch < " " and ch not in "\n\t") or ch == "\x7f"):
                return True
            continue
        if unsafe_char(ch) and not (mode == "msg" and unicodedata.category(ch) in ("Cc", "Zl", "Zp")):
            return True
    return False


def sanitize(s: str) -> str:
    return "".join(" " if unsafe_char(c) else c for c in s)
COPY_IGNORE = shutil.ignore_patterns("__pycache__", "node_modules", ".git")
ENTRY_HEAD_RE = re.compile(r"^### ([0-9a-f]{16})$")
ENTRY_FIELD_RE = re.compile(r"^- (\w+): (.*)$")


class Fail(Exception):
    """Fail-Closed input error (exit code 2)."""


# ------------------------------------------------------------------ input helpers
def read_text(path: Path, label: str) -> str:
    try:
        if not path.is_file():
            raise Fail(f"cannot read {label} {path}: not a regular file")
        with path.open("rb") as f:
            data = f.read(MAX_INPUT_BYTES + 1)
    except OSError as e:
        raise Fail(f"cannot read {label} {path}: {e.strerror or e}") from e
    if len(data) > MAX_INPUT_BYTES:
        raise Fail(f"{label} {path} exceeds {MAX_INPUT_BYTES} bytes")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as e:
        raise Fail(f"cannot read {label} {path}: not valid UTF-8") from e


def no_ctrl(v: str, where: str, key: str) -> None:
    if has_unsafe(v):
        raise Fail(f"{where}: '{key}' contains control, invisible or surrogate characters")


def req_str(obj: dict, key: str, where: str, max_len: int) -> str:
    v = obj.get(key)
    if isinstance(v, str):
        no_ctrl(v, where, key)
    if not isinstance(v, str) or not v.strip():
        raise Fail(f"{where}: '{key}' must be a non-empty string")
    if len(v) > max_len:
        raise Fail(f"{where}: '{key}' exceeds {max_len} chars")
    return v


TARGET_RE = re.compile(r"[A-Za-z0-9._/@+-]+")  # allowlist: patch(1) and shells must read the path as one name


def check_target(t: str, where: str) -> str:
    p = PurePosixPath(t)
    if p.is_absolute() or ".." in p.parts or "\\" in t or "\x00" in t or p.as_posix() in ("", "."):
        raise Fail(f"{where}: invalid target {t!r} (must be a repo-relative path without '..')")
    if not TARGET_RE.fullmatch(t):  # GUARD:target-allowlist
        raise Fail(f"{where}: invalid target {t!r} (allowed characters: A-Z a-z 0-9 . _ / @ + -)")
    return p.as_posix()


def norm_sig(s: str) -> str:
    return " ".join(s.lower().split())


def one_line(s: str, limit: int) -> str:
    return " ".join(sanitize(s).split())[:limit]


def load_traces(path: Path) -> tuple[list[dict], str]:
    """Return (records, sha256 hex of the input); the digest seeds the Training/Held-Out split."""
    text = read_text(path, "traces")
    digest = hashlib.sha256(text.encode("utf-8", "surrogatepass")).hexdigest()
    rows: list[dict] = []
    for n, line in enumerate(text.split("\n"), 1):  # JSONL separator is LF only (not U+2028/U+0085)
        if not line.strip():
            continue
        if len(rows) >= MAX_TRACES:
            raise Fail(f"traces {path} has more than {MAX_TRACES} records")
        where = f"traces {path} line {n}"
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            raise Fail(f"traces {path}: invalid JSON at line {n}: {e.msg}") from e
        except RecursionError as e:
            raise Fail(f"traces {path}: line {n}: JSON nesting too deep") from e
        if not isinstance(obj, dict):
            raise Fail(f"{where}: record must be a JSON object")
        msg = obj.get("message", "")
        if not isinstance(msg, str):
            raise Fail(f"{where}: 'message' must be a string")
        if has_unsafe(msg, "msg"):
            raise Fail(f"{where}: 'message' contains control, invisible or surrogate characters")
        rows.append(
            {
                "signature": norm_sig(req_str(obj, "signature", where, 200)),
                "task": req_str(obj, "task", where, 200),
                "target": check_target(req_str(obj, "target", where, 300), where),
                "message": msg,
            }
        )
    if not rows:
        raise Fail(f"traces {path} is empty (no records)")
    return rows, digest


def load_candidates(path: Path, root: Path) -> list[dict]:
    text = read_text(path, "candidates")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        raise Fail(f"candidates {path}: invalid JSON: {e.msg} (line {e.lineno})") from e
    except RecursionError as e:
        raise Fail(f"candidates {path}: JSON nesting too deep") from e
    if not isinstance(data, list):
        raise Fail(f"candidates {path} must be a JSON array")
    if len(data) > MAX_CANDIDATES:
        raise Fail(f"candidates {path} has more than {MAX_CANDIDATES} entries")
    out, seen = [], set()
    root_res = root.resolve()
    for i, obj in enumerate(data):
        where = f"candidates {path} [{i}]"
        if not isinstance(obj, dict):
            raise Fail(f"{where}: entry must be a JSON object")
        cid = obj.get("id")
        if not isinstance(cid, str) or not ID_RE.fullmatch(cid):
            raise Fail(f"{where}: invalid candidate id {cid!r} (allowed: [A-Za-z0-9._-]{{1,64}})")
        if cid in seen:
            raise Fail(f"{where}: duplicate candidate id {cid!r}")
        seen.add(cid)
        new_text = obj.get("new_text")
        if not isinstance(new_text, str) or len(new_text) > MAX_NEW_TEXT_CHARS:
            raise Fail(f"{where}: 'new_text' must be a string of at most {MAX_NEW_TEXT_CHARS} chars")
        if has_unsafe(new_text, "text"):  # GUARD:newtext-unsafe
            raise Fail(f"{where}: 'new_text' contains control, invisible or surrogate characters")
        target = check_target(req_str(obj, "target", where, 300), where)
        resolved = (root_res / target).resolve()
        if root_res not in resolved.parents:
            raise Fail(f"{where}: target {target!r} resolves outside the repo root")
        category = obj.get("category")
        if category is not None and category not in ("A", "B", "C"):
            raise Fail(f"{where}: 'category' must be one of A, B, C (got {category!r})")
        probes = obj.get("probes")
        if not isinstance(probes, list) or len(probes) > MAX_PROBES:
            raise Fail(f"{where}: 'probes' must be a list of at most {MAX_PROBES} entries")
        names = set()
        for p in probes:
            if isinstance(p, dict) and isinstance(p.get("name"), str):
                no_ctrl(p["name"], where, "probes[].name")
            if (
                not isinstance(p, dict)
                or not isinstance(p.get("name"), str)
                or not p["name"]
                or not isinstance(p.get("before"), bool)
                or not isinstance(p.get("after"), bool)
                or p["name"] in names
            ):
                raise Fail(f"{where}: 'probes' entries need a unique string name and bool before/after")
            names.add(p["name"])
        out.append(
            {
                "id": cid,
                "signature": norm_sig(req_str(obj, "signature", where, 200)),
                "target": target,
                "new_text": new_text,
                "category": category,
                "probes": probes,
            }
        )
    return out


# ------------------------------------------------------------------ stage 1 / 2
def classify(target: str) -> str | None:
    """Map a repo-relative path to a Harness² component (C1-C8), or None."""
    p = PurePosixPath(target)
    name, parts = p.name, p.parts
    if name == "SYSTEM.md":
        return "C1"
    if name == "EXPERIENCE.md":
        return "C3"
    if name in ("AGENTS.md", "CLAUDE.md"):
        return "C4"
    if name == "SKILL.md" and len(parts) >= 3 and parts[-3] == "skills":
        return "C6"
    if p.suffix == ".md" and "rules" in parts[:-1]:
        return "C2"
    if p.suffix == ".md" and len(parts) >= 2 and parts[-2] == "agents":
        return "C5"
    if p.suffix == ".py" and "scripts" in parts[:-1]:
        return "C7"
    # hooks/omp/*.ts are deployed into ~/.omp/agent/extensions (merged directory)
    if p.suffix == ".ts" and ("extensions" in parts[:-1] or parts[-3:-1] == ("hooks", "omp")):
        return "C8"
    return None


def hypothesis_category(target: str) -> str | None:
    """swarm-evolve hypothesis category from the target path, or None when the path fits none.

    A: Domain Learning (.trail/)  B: Skill Refinement (skills/)  C: Harness / Routing / Context Config
    (harnesses/, models/, hooks/, extensions/). The three are kept strictly apart: one candidate, one category.
    """
    parts = PurePosixPath(target).parts
    if ".trail" in parts:
        return "A"
    if "skills" in parts[:-1]:
        return "B"
    if any(x in parts[:-1] for x in ("harnesses", "models", "hooks", "extensions")):
        return "C"
    return None


def cluster_traces(traces: list[dict], min_occ: int) -> list[dict]:
    groups: dict[str, list[dict]] = collections.defaultdict(list)
    for t in traces:
        groups[t["signature"]].append(t)
    clusters = []
    for sig in sorted(groups):
        items = groups[sig]
        tasks = sorted({t["task"] for t in items})
        counts = collections.Counter(t["target"] for t in items)
        target = sorted(counts, key=lambda k: (-counts[k], k))[0]
        c = {
            "signature": sig,
            "count": len(items),
            "tasks": len(tasks),
            "scope": "INV" if len(tasks) >= 2 else "DOM",
            "target": target,
            "component": classify(target),
            "sample": next((t["message"] for t in items if t["message"]), sig),
            "status": "accepted",
            "reason": None,
        }
        if len(items) < min_occ:  # GUARD:min-occurrences
            c["status"], c["reason"] = "rejected", "below_min_occurrences"
        elif c["component"] is None:  # GUARD:cluster-unclassified
            c["status"], c["reason"] = "rejected", "unclassified_target"
        clusters.append(c)
    return clusters


# ------------------------------------------------------------------ harness tree (upstream harness2/core/tree.py)
# Deterministic half of google-research/harness2 (harness2/core/tree.py, commit 68688175): the harness is ONE
# editable surface of known files, and every candidate edit is validated inside that whole tree before
# it is proposed. The stochastic half (LLM proposer, anonymised pairwise selection, alpha-beta judge)
# has no offline equivalent; compose() below replaces the human "apply one diff" step deterministically.


class SurfaceSpec(NamedTuple):
    """The files a candidate may rewrite — the agent/ tree deployed into ~/.omp/agent."""

    name: str
    always_on: tuple[str, ...]
    memory: str
    skill_dir: str
    agent_dir: str
    plugin_dir: str
    rules_dir: str
    script_dirs: tuple[str, ...]
    always_on_cap_reason: str


DOTFILES_SURFACE = SurfaceSpec(
    name="omp",
    always_on=("agent/harnesses/omp/SYSTEM.md", "agent/harnesses/omp/AGENTS.md"),  # C1 + C4: injected every turn
    memory="agent/context/library/EXPERIENCE.md",  # C3: read on demand
    skill_dir="agent/skills",
    agent_dir="agent/agents",
    plugin_dir="agent/harnesses/omp/extensions",
    rules_dir="agent/rules",
    script_dirs=("agent/scripts",),
    always_on_cap_reason="every character here is paid on every turn and competes with the agent's output budget",
)

# upstream reads exactly these bytes of a frontmatter head
FM_HEAD_CHARS = 600
# `scripts/x.sh` resolves inside this repo: agent/scripts/ or ANY skill's scripts/ (skills cross-reference
# each other: swarm-loop calls swarm-release-gate/scripts/verify.sh as `scripts/verify.sh`).
REF_SCRIPT = re.compile(r"(?<![\w/])scripts/([A-Za-z0-9_.-]+\.(?:sh|py))")
REF_CLAUDE_SKILL = re.compile(r"~/\.claude/skills/([a-z0-9_-]+)/(?:scripts/([A-Za-z0-9_.-]+\.(?:sh|py))|(load\.sh))")


def fm_field(head: str, key: str) -> str | None:
    m = re.search(rf"^{key}:[ \t]*(\S+)[ \t]*$", head[:FM_HEAD_CHARS], re.M)
    return m.group(1) if m else None


TEXT_SUFFIXES = frozenset({".md", ".sh", ".py", ".ts", ".js", ".json", ".txt", ".yml", ".yaml", ".toml", ".conf"})


def surface_files(surface: SurfaceSpec, root: Path) -> list[str]:
    """Every text file of the surface (upstream read_tree), sorted: candidates may only touch these.
    Binary assets (png/svg/xsd/...) and harness-managed `.system/` skills are not editable harness text."""
    out: set[str] = set()
    for rel in (*surface.always_on, surface.memory):
        if (root / rel).is_file():
            out.add(rel)
    for d in surface.script_dirs:
        base = root / d
        if base.is_dir():
            out |= {p.relative_to(root).as_posix() for p in base.iterdir() if p.is_file() and p.suffix in (".sh", ".py")}
    sd = root / surface.skill_dir
    if sd.is_dir():
        for skill in sd.iterdir():
            if skill.is_dir() and not skill.name.startswith("."):
                out |= {p.relative_to(root).as_posix() for p in skill.rglob("*") if p.is_file() and p.suffix in TEXT_SUFFIXES}
    for d, pat in ((surface.agent_dir, "*.md"), (surface.plugin_dir, "*.ts"), (surface.rules_dir, "*.md")):
        base = root / d
        if base.is_dir():
            out |= {p.relative_to(root).as_posix() for p in base.glob(pat) if p.is_file()}
    return sorted(out)


def read_tree(surface: SurfaceSpec, root: Path) -> dict[str, str]:
    return {rel: read_text(root / rel, "harness file") for rel in surface_files(surface, root)}


def on_surface(surface: SurfaceSpec, rel: str) -> bool:
    """Prefix check is enough: candidate targets already passed check_target() and classify()."""
    return rel in surface.always_on or rel == surface.memory or any(
        rel.startswith(d + "/")
        for d in (*surface.script_dirs, surface.skill_dir, surface.agent_dir, surface.plugin_dir, surface.rules_dir)
    )


def _skill_names(surface: SurfaceSpec, tree: dict[str, str]) -> list[str]:
    pre = surface.skill_dir + "/"
    depth = len(PurePosixPath(surface.skill_dir).parts) + 2  # <skill_dir>/<name>/SKILL.md
    return sorted(
        PurePosixPath(rel).parts[-2]
        for rel in tree
        if rel.startswith(pre) and rel.endswith("/SKILL.md") and len(PurePosixPath(rel).parts) == depth
    )


def _agent_names(surface: SurfaceSpec, tree: dict[str, str]) -> list[str]:
    pre = surface.agent_dir + "/"
    return sorted(rel[len(pre) : -3] for rel in tree if rel.startswith(pre) and rel.endswith(".md") and "/" not in rel[len(pre) :])


def validate_tree(
    surface: SurfaceSpec, tree: dict[str, str], *, always_on_max: int = 0, require_skill_triggers: bool = False
) -> dict:
    """Upstream tree.validate. Every message names the file, the rule, and why the agent silently loses the
    capability. `always_on_max=0` disables the cap (upstream passes a per-surface budget at call time; this
    repo's injected budget is model dependent, so the cap is opt-in via --always-on-cap)."""
    errs: list[str] = []
    warns: list[str] = []
    body = "\n".join(tree.get(rel, "") for rel in surface.always_on)
    if always_on_max and len(body) > always_on_max:
        errs.append(f"always-on content is {len(body)} chars, over the {always_on_max} cap; {surface.always_on_cap_reason}")

    skills = _skill_names(surface, tree)
    for name in skills:
        rel = f"{surface.skill_dir}/{name}/SKILL.md"
        head = tree.get(rel, "")
        if not re.search(r"^description:[ \t]*\S", head[:FM_HEAD_CHARS], re.M):
            errs.append(f"{rel} needs a `description:` in its frontmatter, or the skill is dropped SILENTLY at load")
        if fm_field(head, "name") != name:
            errs.append(f"{rel} needs frontmatter `name: {name}` matching its directory (a mismatch is dropped SILENTLY at load)")
        if name not in body:
            msg = f"skill '{name}' is never named in the always-on text, so the agent is not told to invoke it"
            (errs if require_skill_triggers else warns).append(msg)

    agents = _agent_names(surface, tree)
    for name in agents:
        rel = f"{surface.agent_dir}/{name}.md"
        head = tree.get(rel, "")
        if fm_field(head, "name") != name:
            errs.append(f"{rel} needs frontmatter `name: {name}`")
        if not re.search(r"^description:[ \t]*\S", head[:FM_HEAD_CHARS], re.M):
            errs.append(f"{rel} needs a `description:`")

    for rel in sorted(tree):
        if rel.endswith(".py") and (PurePosixPath(rel).parent.as_posix() in surface.script_dirs or "/scripts/" in rel):
            try:
                compile(tree[rel], rel, "exec")
            except (SyntaxError, ValueError) as e:  # ValueError: NUL byte in source
                errs.append(f"{rel} does not compile: {type(e).__name__}: {one_line(str(e), 160)}")

    have = {PurePosixPath(rel).name for rel in tree if rel.endswith((".sh", ".py"))}
    for rel in sorted(tree):
        if not (rel in surface.always_on or (rel.endswith("/SKILL.md") and on_surface(surface, rel))):
            continue
        src = tree[rel]
        for ref in sorted(set(REF_SCRIPT.findall(src))):
            if ref not in have:
                errs.append(f"{rel} invokes `scripts/{ref}` but that file is not in the harness")
        for skill, f, load in sorted(set(REF_CLAUDE_SKILL.findall(src))):
            want = f"scripts/{f}" if f else "load.sh"
            if f"{surface.skill_dir}/{skill}/{want}" not in tree:
                errs.append(f"{rel} invokes `~/.claude/skills/{skill}/{want}` but that file is not in the harness")

    def under(d: str) -> int:
        return sum(1 for rel in tree if PurePosixPath(rel).parent.as_posix() == d)

    return {
        "ok": not errs,
        "errors": errs,
        "warnings": warns,
        "message": " | ".join(errs),
        "always_on_chars": len(body),
        "always_on_cap": always_on_max or None,
        "census": {
            "n_files": len(tree),
            "skills": len(skills),
            "sub_agents": len(agents),
            "scripts": sum(under(d) for d in surface.script_dirs),
            "plugins": under(surface.plugin_dir),
            "rules": under(surface.rules_dir),
        },
    }


def tree_lines(tree: dict[str, str]) -> list[str]:
    return [f"{rel}\n{ln}" for rel in sorted(tree) for ln in split_lines(tree[rel])]


def tree_diversity(trees: dict[str, dict[str, str]]) -> dict:
    """Upstream tree.diversity: pairwise line Jaccard over the candidate trees (path names included)."""
    sets = {cid: set(tree_lines(t)) for cid, t in trees.items()}
    ids = sorted(sets)
    out = {"n": len(ids), "n_distinct": len({frozenset(s) for s in sets.values()}), "mean_line_jaccard": 1.0}
    if len(ids) < 2:
        return out
    vals = []
    for i, a in enumerate(ids):
        for b in ids[i + 1 :]:
            union = sets[a] | sets[b]
            vals.append(len(sets[a] & sets[b]) / len(union) if union else 1.0)
    out["mean_line_jaccard"] = round(sum(vals) / len(vals), 6)
    return out


def write_atomic(dest: Path, body: str, label: str = "proposal") -> str:
    """O_EXCL temp file + os.replace: a pre-planted symlink at the destination is replaced, never followed."""
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=".harness2-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(body)
            os.replace(tmp, dest)
        except BaseException:
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass
            raise
    except OSError as e:
        raise Fail(f"cannot write {label} {dest}: {e.strerror or e}") from e
    return str(dest)


def compose(
    surface: SurfaceSpec,
    base_tree: dict[str, str],
    accepted: list[dict],
    root: Path,
    out_path: Path,
    *,
    always_on_max: int,
    require_skill_triggers: bool,
    dry_run: bool,
) -> dict:
    """Merge every accepted candidate into ONE tree and validate it as a whole (upstream applies one diff
    by hand, so a batch that is individually fine but collectively broken can never be produced)."""
    groups: dict[str, list[dict]] = collections.defaultdict(list)
    for c in accepted:
        groups[c["target"]].append(c)
    conflicts = [
        {"target": t, "ids": [c["id"] for c in cs]} for t, cs in sorted(groups.items()) if len({c["new_text"] for c in cs}) > 1
    ]
    merged = [cs[0] for _, cs in sorted(groups.items()) if len({c["new_text"] for c in cs}) == 1]
    res = {"status": "empty", "path": None, "applied": [c["id"] for c in merged], "conflicts": conflicts, "reasons": []}
    if not accepted:
        return res
    if conflicts:
        return {**res, "status": "fallback", "reasons": [f"conflicting edits for {c['target']}: {', '.join(c['ids'])}" for c in conflicts]}
    if dry_run:
        return {**res, "status": "dry-run"}
    tree = dict(base_tree)
    for c in merged:
        tree[c["target"]] = c["new_text"]
    v = validate_tree(surface, tree, always_on_max=always_on_max, require_skill_triggers=require_skill_triggers)
    if not v["ok"]:
        return {**res, "status": "fallback", "reasons": v["errors"]}
    body = "".join(build_diff(c, root) for c in merged)
    return {**res, "status": "written", "path": write_atomic(out_path, body, "composed diff")}


# ------------------------------------------------------------------ stage 3
def est_tokens(text: str) -> int:
    """Deterministic estimate: ceil(UTF-8 bytes / 4); byte based so CJK cannot hide growth."""
    return (len(text.encode("utf-8")) + 3) // 4


KEY_RE = re.compile(r"^([A-Za-z0-9_-]+)[ \t]*:(.*)$")


def odd_chars(x: str) -> bool:
    """Any whitespace other than ASCII space/TAB, or any control/format character."""
    return any((ch not in " \t" and ch.isspace()) or unicodedata.category(ch)[0] == "C" for ch in x)


def skill_description(text: str) -> str | None:
    """Length-faithful reader of the single top-level `description` (YAML semantics: literal `|` keeps
    newlines and extra indentation, folded `>` and plain continuations join with a space). Returns None
    (-> skill_frontmatter) when the structure is missing, duplicated, non-standard or ambiguous:
    quoted keys, anchors/tags/flow values, nested mapping/sequence values, tab or jittering block
    indentation, explicit indent indicators, blank lines inside the value."""
    lines = text.split("\n")
    if lines[0].rstrip(" \t") != "---":
        return None
    end = next((i for i in range(1, len(lines)) if lines[i].rstrip(" \t") == "---"), None)
    if end is None:
        return None
    keys: list[tuple[str, str, list[str]]] = []
    for line in lines[1:end]:
        if line.startswith("#"):
            continue
        if not line.strip(" \t") or line[:1] in (" ", "\t") or line.startswith("- "):
            if not keys:
                if line.strip(" \t"):
                    return None
                continue
            keys[-1][2].append(line)
            continue
        m = KEY_RE.match(line)
        if not m:
            return None
        keys.append((m.group(1), m.group(2).strip(" \t"), []))
    found = [k for k in keys if k[0] == "description"]
    if len(found) != 1:
        return None
    _, val, cont = found[0]
    while cont and cont[-1] == "":
        cont.pop()  # only truly empty trailing lines are dropped; whitespace-only lines count as content (rejected below)
    if any(not c.strip(" \t") or c[:1] != " " or re.match(r"^ *\t", c) for c in cont):
        return None
    if any(odd_chars(x) for x in (val, *cont)):  # GUARD:desc-odd-chars (non-ASCII spaces, controls: YAML and str.strip disagree on them)
        return None
    if yaml is None:  # GUARD:noyaml-subset (conservative subset only: single-line plain scalar or simple block scalar)
        if val[:1] in (">", "|"):
            if not re.fullmatch(r"[>|]-?", val):
                return None
        elif cont or not val or val[0] in "\"'":
            return None
    if "\\" in val or any("\\" in c for c in cont):  # GUARD:desc-backslash (YAML escapes would decode to other characters)
        return None
    if val[:1] and val[0] in ">|":
        if not re.fullmatch(r"[>|]-?[ \t]*(#.*)?", val) or not cont:  # GUARD:desc-keep-chomp ('+' keeps trailing blank lines: rejected)
            return None
        indent = len(cont[0]) - len(cont[0].lstrip(" "))
        body = []
        for c in cont:
            lead = len(c) - len(c.lstrip(" "))
            if lead < indent or (val[0] == ">" and lead != indent):
                return None
            body.append(c[indent:])
        joined = ("\n" if val[0] == "|" else " ").join(body)
        if val[1:2] != "-":  # clip chomping keeps one final newline
            joined += "\n"
    else:
        if val[:1] and val[0] in "&*!%@`{[":
            return None
        parts = [c.strip(" \t") for c in cont]
        if any(x.startswith("- ") or x == "-" or ": " in x or x.endswith(":") for x in parts):
            return None
        joined = " ".join(x for x in [val, *parts] if x)
        if len(joined) >= 2 and joined[0] == joined[-1] and joined[0] in "\"'":
            joined = joined[1:-1]
    return joined or None


def yaml_undermeasured(text: str, ours_len: int) -> bool:
    """True when PyYAML reads a longer (or non-string) description than the strict reader measured."""
    if yaml is None:
        return False
    lines = text.split("\n")
    end = next(i for i in range(1, len(lines)) if lines[i].rstrip(" \t") == "---")
    try:
        doc = yaml.safe_load("\n".join(lines[1:end]) + "\n")
    except yaml.YAMLError:
        return True
    d = doc.get("description") if isinstance(doc, dict) else None
    return not isinstance(d, str) or len(d) > ours_len


# ------------------------------------------------------------------ stage 4
def split_probes(probes: list[dict], seed: str) -> tuple[list[dict], list[dict]]:
    """Deterministic Training / Held-Out split (about one third held out, at least one)."""
    keyed = sorted(probes, key=lambda p: (hashlib.sha256(f"{seed}:{p['name']}".encode()).hexdigest(), p["name"]))
    n_held = max(1, len(keyed) // 3)
    return keyed[n_held:], keyed[:n_held]


def security_commands(args: argparse.Namespace) -> tuple[list[str], bool]:
    """Return (gate commands, overridden). `{root}` inside a command is replaced by the tree under test."""
    overridden = True
    if args.security_cmd:
        cmds = list(args.security_cmd)
    elif os.environ.get("HARNESS2_SECURITY_CMDS"):
        cmds = [c for c in os.environ["HARNESS2_SECURITY_CMDS"].splitlines() if c.strip()]
    else:
        overridden = False
        cmds = [f"bash {{root}}/agent/scripts/{s}" for s in ("test-security-rules.sh", "test-write-scope-parity.sh")]
    if not cmds:  # GUARD:gate-empty
        raise Fail("no security gate commands configured (HARNESS2_SECURITY_CMDS is blank)")
    for c in cmds:
        try:
            if not shlex.split(c):
                raise ValueError("empty command")
        except ValueError as e:
            raise Fail(f"invalid security command {c!r}: {e}") from e
    return cmds, overridden


SANDBOX_PATH = "/usr/local/bin:/usr/bin:/bin"
GATE_ENV_ALLOW = ("PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER", "LOGNAME", "SHELL", "TERM", "TZ")
GATE_INNER_ENV = ("PYTHONDONTWRITEBYTECODE", "HARNESS2_REPO_ROOT", "LANG", "LC_ALL", "LC_CTYPE", "TZ")  # nothing else enters the sandbox
GATE_FSIZE = 128 << 20  # RLIMIT_FSIZE: largest single file
GATE_AS = 4 << 30  # RLIMIT_AS
GATE_NPROC = 512  # RLIMIT_NPROC inside the sandbox's own user namespace (counted per namespace, so the host's load is irrelevant)
GATE_TMPFS_BYTES = 256 << 20  # size of the sandbox /tmp tmpfs
GATE_COPY_QUOTA = 256 << 20  # total bytes the candidate may leave in its (host backed) copy
_SANDBOX_CACHE: dict[bool, tuple[list[str], str]] = {}


def sandbox_prefix(empty_proc: bool) -> tuple[list[str], str]:
    """bwrap argv prefix for the gate (no network, own pid/ipc/uts/user namespaces, read-only system, size-limited
    tmpfs /tmp and HOME) and its label, probed once. The host's /proc is NEVER exposed: a fresh procfs is used, or
    (only with --gate-empty-proc, when the environment refuses a fresh procfs) an empty /proc. Raises Fail (rc 2)
    when isolation cannot be created."""
    if empty_proc in _SANDBOX_CACHE:
        return _SANDBOX_CACHE[empty_proc]
    hint = "pass --allow-unsandboxed-gate to run the gate WITHOUT isolation (candidate code then runs with your privileges)"
    bwrap = shutil.which("bwrap")
    if bwrap is None:  # GUARD:sandbox-required
        raise Fail(f"cannot create a gate sandbox: bwrap not found in PATH; {hint}")
    base = ["--unshare-all", "--die-with-parent", "--new-session", "--clearenv", "--ro-bind", "/usr", "/usr",
            "--ro-bind", "/etc", "/etc", "--dev", "/dev", "--size", str(GATE_TMPFS_BYTES), "--tmpfs", "/tmp"]
    for d in ("/bin", "/sbin", "/lib", "/lib64"):
        if os.path.islink(d):
            base += ["--symlink", os.readlink(d), d]
        elif os.path.isdir(d):
            base += ["--ro-bind", d, d]

    def probe(proc_args: list[str]) -> list[str] | None:
        prefix = [bwrap, *base, *proc_args]
        try:
            r = subprocess.run([*prefix, "/usr/bin/true"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=30, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return None
        return prefix if r.returncode == 0 else None

    fresh = probe(["--proc", "/proc"])
    if fresh is not None:
        _SANDBOX_CACHE[empty_proc] = (fresh, "bwrap")
        return _SANDBOX_CACHE[empty_proc]
    empty = probe(["--tmpfs", "/proc"])
    if empty is None:
        raise Fail(f"cannot create a gate sandbox: bwrap cannot create namespaces here; {hint}")
    if not empty_proc:  # GUARD:no-host-proc (never fall back to binding the host /proc)
        raise Fail("cannot create a gate sandbox: this environment refuses a fresh procfs (bwrap --proc) and the host /proc is never "
                   "exposed to candidate code. An empty /proc breaks tools that need /proc/self (e.g. bun, which the default gates use). "
                   f"Pass --gate-empty-proc for gates that do not need /proc, or {hint}")
    _SANDBOX_CACHE[empty_proc] = (empty, "bwrap (empty /proc)")
    return _SANDBOX_CACHE[empty_proc]


def kill_group(proc: subprocess.Popen) -> None:
    """SIGKILL the gate's whole process group (also sweeps grandchildren) and reap the leader."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()


def dir_size(root: Path, limit: int) -> int:
    """Total file bytes below root (symlinks not followed), stopping as soon as limit is exceeded."""
    total = 0
    for dp, _dn, fn in os.walk(root):
        for f in fn:
            try:
                total += os.lstat(os.path.join(dp, f)).st_size
            except OSError:
                pass
            if total > limit:
                return total
    return total


def run_gate(cmds: list[str], root: Path, sandbox: list[str] | None, writable: bool) -> tuple[bool, str]:
    """Run every gate command with cwd=root and HARNESS2_REPO_ROOT=root; any failure rejects.
    sandbox=None runs unisolated (--allow-unsandboxed-gate only); otherwise inside bwrap with root bound
    read-write (candidate copy, total size capped) or read-only (baseline), RLIMIT_FSIZE/NPROC/AS/CORE set, and
    only GATE_INNER_ENV forwarded. Output is discarded (only the exit code matters), the environment is an
    allowlist, and the process group is always killed afterwards (also on timeout, SIGTERM and SIGINT)."""
    env = {k: v for k, v in os.environ.items() if k in GATE_ENV_ALLOW or k.startswith("HARNESS2_")}  # GUARD:gate-env
    env.update(HARNESS2_REPO_ROOT=str(root), PYTHONDONTWRITEBYTECODE="1")  # no __pycache__ in the repo
    for c in cmds:
        argv = [a.replace("{root}", str(root)) for a in shlex.split(c)]
        limits = None
        if sandbox is not None:  # GUARD:sandbox-used
            inner = {"PATH": SANDBOX_PATH, "HOME": "/tmp/home", "TMPDIR": "/tmp", **{k: env[k] for k in GATE_INNER_ENV if k in env}}
            setenv = [x for k, v in sorted(inner.items()) for x in ("--setenv", k, v)]
            argv = [*sandbox, "--dir", "/tmp/home", *setenv, "--bind" if writable else "--ro-bind", str(root), str(root),
                    "--chdir", str(root), "--", "/usr/bin/bash", "-c", 'ulimit -u "$0" && exec "$@"', str(GATE_NPROC),  # GUARD:nproc
                    "/usr/bin/env", *argv]

            def limits() -> None:  # runs in the child before exec; lowers limits only (NPROC is set inside the user namespace, see above)
                resource.setrlimit(resource.RLIMIT_FSIZE, (GATE_FSIZE, GATE_FSIZE))  # GUARD:rlimits
                resource.setrlimit(resource.RLIMIT_AS, (GATE_AS, GATE_AS))
                resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        try:
            proc = subprocess.Popen(  # noqa: S603 - argv list, no shell
                argv, cwd=root, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, start_new_session=True, preexec_fn=limits,
            )
        except OSError as e:
            return False, f"{c}: {e}"
        try:
            deadline = time.monotonic() + GATE_TIMEOUT_SEC
            while True:
                try:
                    rc = proc.wait(timeout=0.25)
                    break
                except subprocess.TimeoutExpired:
                    if sandbox is not None and writable and dir_size(root, GATE_COPY_QUOTA) > GATE_COPY_QUOTA:  # GUARD:copy-quota
                        kill_group(proc)
                        return False, f"{c}: copy quota exceeded"
                    if time.monotonic() > deadline:
                        kill_group(proc)
                        return False, f"{c}: timeout"
        finally:
            kill_group(proc)  # GUARD:gate-group-kill (BaseException such as SystemExit from SIGTERM passes through)
        if rc != 0:
            return False, f"{c}: exit {rc}"
    return True, ""


def gate_on_candidate(cand: dict, cmds: list[str], root: Path, sandbox: list[str] | None) -> tuple[bool, str]:
    """Copy agent/ to a temp tree, apply the candidate there, run the gate against the copy."""
    with tempfile.TemporaryDirectory(prefix="harness2-gate-") as tmp:
        copy_root = Path(tmp)
        try:
            if (root / "agent").is_dir():
                shutil.copytree(root / "agent", copy_root / "agent", symlinks=True, ignore=COPY_IGNORE)
            dest = copy_root / cand["target"]
            parent_real = os.path.realpath(dest.parent)
            root_real = os.path.realpath(copy_root)
            if parent_real != root_real and not parent_real.startswith(root_real + os.sep):
                return False, "target escapes the gate tree"
            dest.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp_name = tempfile.mkstemp(dir=dest.parent, prefix=".h2tmp-")
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(cand["new_text"])
            os.replace(tmp_name, dest)  # replaces (never follows) an existing file/symlink
        except (OSError, shutil.Error) as e:
            return False, f"cannot prepare gate tree: {e}"
        return run_gate(cmds, copy_root, sandbox, True)


# ------------------------------------------------------------------ evaluation
def evaluate(cand: dict, kept: dict[str, dict], root: Path, seed: str, gate, tree_ctx: dict | None = None) -> dict:
    res = {
        "id": cand["id"],
        "component": None,
        "category": hypothesis_category(cand["target"]),
        "scope": None,
        "status": "rejected",
        "reasons": [],
        "delta_tokens": None,
        "split": None,
        "training_regressions": None,
        "training_fixes": None,
        "proposal": None,
    }
    cluster = kept.get(cand["signature"])
    if cluster is None:
        res["reasons"].append("noise_signature")
        return res
    declared = cand.get("category")
    if declared is not None and declared != res["category"]:  # GUARD:category-mismatch
        res["reasons"].append("category_mismatch")
        return res
    comp = classify(cand["target"])
    if comp is None:
        res["reasons"].append("unclassified_target")
        return res
    res["component"], res["scope"] = comp, cluster["scope"]

    bpath = root / cand["target"]
    baseline = read_text(bpath, "baseline") if bpath.exists() else ""
    new = cand["new_text"]
    res["delta_tokens"] = est_tokens(new) - est_tokens(baseline)
    if new == baseline:
        res["reasons"].append("no_change")
        return res
    # The always-on projection (name+description) is what is injected every turn; it is reported for
    # visibility. The budget guard below keeps charging C6 by file size: that is a LOCAL conservation law
    # (stricter than upstream, which only caps always-on text and never charges a skill body).
    if comp == "C6":
        base_desc, new_desc = skill_description(baseline), skill_description(new)
        if base_desc is not None and new_desc is not None:
            adv = f"name: {fm_field(new, 'name') or ''}\ndescription: {new_desc}"
            adv0 = f"name: {fm_field(baseline, 'name') or ''}\ndescription: {base_desc}"
            res["advertised_delta_tokens"] = est_tokens(adv) - est_tokens(adv0)
    if comp in ALWAYS_LOADED and res["delta_tokens"] > 0:  # GUARD:net-token-budget
        res["reasons"].append("net_token_budget")
    if comp == "C6":
        if new.count("\n") + (0 if new.endswith("\n") or not new else 1) > SKILL_MAX_LINES:  # GUARD:skill-lines
            res["reasons"].append("skill_lines")
        desc = skill_description(new)
        if desc is None:
            res["reasons"].append("skill_frontmatter")
        elif yaml_undermeasured(new, len(desc)):  # GUARD:yaml-crosscheck
            res["reasons"].append("skill_frontmatter")
        elif len(desc) > DESC_MAX_CHARS:  # GUARD:skill-description
            res["reasons"].append("skill_description")
    if res["reasons"]:
        return res
    if tree_ctx is not None and on_surface(tree_ctx["surface"], cand["target"]):
        tree = dict(tree_ctx["base"])
        tree[cand["target"]] = new
        v = validate_tree(
            tree_ctx["surface"],
            tree,
            always_on_max=tree_ctx["cap"],
            require_skill_triggers=tree_ctx["require_triggers"],
        )
        # only errors this candidate INTRODUCES: a pre-existing baseline defect must not block every edit
        new_errs = [e for e in v["errors"] if e not in tree_ctx["base_errors"]]
        if new_errs:  # GUARD:tree-invalid (upstream validates the whole candidate tree)
            res["tree_errors"] = new_errs
            res["reasons"].append("tree_invalid")
    if res["reasons"]:
        return res

    if not cand["probes"]:
        res["reasons"].append("no_probes")
        return res
    train, held = split_probes(cand["probes"], seed)
    res["split"] = {"train": sorted(p["name"] for p in train), "held_out": sorted(p["name"] for p in held)}
    if any(p["before"] and not p["after"] for p in held):  # GUARD:heldout-regression
        res["reasons"].append("heldout_regression")
        return res
    res["training_regressions"] = sum(1 for p in train if p["before"] and not p["after"])
    res["training_fixes"] = sum(1 for p in train if not p["before"] and p["after"])
    if res["training_regressions"] > res["training_fixes"]:  # GUARD:training-regression
        res["reasons"].append("training_regression")
        return res
    why = gate(cand)  # GUARD:security-gate
    if why:
        res["reasons"].append(why)
        return res
    res["status"] = "accepted"
    return res


# ------------------------------------------------------------------ stage 5
def entry_id(pattern: str, target: str, scope: str) -> str:
    """Experience entry id: first 16 hex of SHA-256("pattern\\ntarget\\nscope")."""
    return hashlib.sha256("\n".join((pattern, target, scope)).encode("utf-8")).hexdigest()[:16]


def parse_experience(text: str) -> list[dict]:
    entries: list[dict] = []
    for line in text.split("\n"):
        m = ENTRY_HEAD_RE.match(line)
        if m:
            entries.append({"id": m.group(1)})
            continue
        f = ENTRY_FIELD_RE.match(line)
        if f and entries:
            entries[-1].setdefault(f.group(1), f.group(2))
    return entries


def render_entry(eid: str, c: dict, today: str) -> str:
    ev = f"{c['count']} occurrences across {c['tasks']} task(s); sample: {one_line(c['sample'], 300)}"
    for v in (c["signature"], ev, c["target"], c["scope"]):
        if has_unsafe(v):  # defence in depth: a field must never span lines
            raise Fail("refusing to render an experience entry with control characters")
    return (
        f"### {eid}\n- pattern: {c['signature']}\n- evidence: {ev}\n"
        f"- target: {c['target']}\n- scope: {c['scope']}\n- created: {today}\n"
    )


def open_experience(path: Path, write: bool) -> int:
    """Open without following symlinks (O_NONBLOCK so a FIFO cannot hang); must be a regular file."""
    flags = (os.O_RDWR | os.O_APPEND) if write else os.O_RDONLY
    try:
        fd = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    except OSError as e:
        if e.errno == errno.ELOOP:
            raise Fail(f"experience {path} is a symbolic link (refusing to follow it)") from e
        raise Fail(f"cannot read experience {path}: {e.strerror or e}") from e
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise Fail(f"cannot read experience {path}: not a regular file")
    return fd


def read_experience_fd(fd: int, path: Path) -> str:
    data, off = [], 0
    while chunk := os.pread(fd, 1 << 16, off):
        data.append(chunk)
        off += len(chunk)
        if off > MAX_INPUT_BYTES:
            raise Fail(f"experience {path} exceeds {MAX_INPUT_BYTES} bytes")
    try:
        return b"".join(data).decode("utf-8")
    except UnicodeDecodeError as e:
        raise Fail(f"cannot read experience {path}: not valid UTF-8") from e


def preflight_experience(path: Path, write: bool) -> None:
    """Everything that could make the final append fail for input reasons, checked BEFORE any diff is written."""
    fd = open_experience(path, write)  # GUARD:preflight
    try:
        read_experience_fd(fd, path)
    finally:
        os.close(fd)


def distill(clusters: list[dict], exp_path: Path, dry_run: bool) -> dict:
    """Append new entries (flock held from read to append, one write). Runs LAST so that any earlier
    failure leaves EXPERIENCE.md untouched; a failed (partial) append is rolled back with ftruncate."""
    fd = open_experience(exp_path, write=not dry_run)
    try:
        if not dry_run:
            fcntl.flock(fd, fcntl.LOCK_EX)
        text = read_experience_fd(fd, exp_path)
        known = {e["id"] for e in parse_experience(text)}
        added, dups, blocks = [], [], []
        today = datetime.date.today().isoformat()
        for c in clusters:
            if c["status"] != "accepted":
                continue
            eid = entry_id(c["signature"], c["target"], c["scope"])
            if eid in known:  # GUARD:sha256-dedup
                dups.append(eid)
                continue
            known.add(eid)
            added.append(eid)
            blocks.append(render_entry(eid, c, today))
        if blocks and not dry_run:
            payload = (("" if text.endswith("\n") else "\n") + "\n" + "\n".join(blocks)).encode("utf-8")
            orig_len, done = os.fstat(fd).st_size, 0
            try:
                while done < len(payload):  # O_APPEND: append only
                    done += os.write(fd, payload[done:])
            except OSError as e:
                try:
                    os.ftruncate(fd, orig_len)  # GUARD:append-rollback
                except OSError as e2:
                    raise Fail(f"cannot append to experience {exp_path}: {e.strerror or e}; rollback failed: {e2.strerror or e2}") from e
                raise Fail(f"cannot append to experience {exp_path}: {e.strerror or e}") from e
        return {"added": added, "duplicates": dups}
    finally:
        os.close(fd)  # also releases the flock


def split_lines(t: str) -> list[str]:
    """Split on LF only (keepends); str.splitlines would also split on VT/FF/NEL/U+2028 and corrupt hunks."""
    parts = t.split("\n")
    return [p + "\n" for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])


def build_diff(cand: dict, root: Path) -> str:
    bpath = root / cand["target"]
    exists = bpath.exists()
    old = read_text(bpath, "baseline") if exists else ""
    diff = difflib.unified_diff(
        split_lines(old),
        split_lines(cand["new_text"]),
        fromfile=f"a/{cand['target']}" if exists else "/dev/null",
        tofile=f"b/{cand['target']}",
    )
    # a line without trailing newline needs the standard marker or patch(1) rejects the diff
    return "".join(ln if ln.endswith("\n") else ln + "\n\\ No newline at end of file\n" for ln in diff)


def write_proposal(cand_id: str, body: str, out_dir: Path) -> str:
    return write_atomic(out_dir / f"harness2-{cand_id}.diff", body, "proposal")


# ------------------------------------------------------------------ CLI
def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description="Harness² offline self-evolution pipeline (see module docstring for formats). "
        "Candidates are only emitted as diffs; nothing under the repo's agent/ tree is ever written."
    )
    ap.add_argument("--traces", type=Path, help="failure traces (JSONL); omit only with --check-tree")
    ap.add_argument(
        "--check-tree",
        action="store_true",
        help="validate the harness tree at --repo-root and exit (0 valid, 1 invalid, 2 input error); no traces needed",
    )
    ap.add_argument(
        "--always-on-cap",
        type=int,
        default=0,
        metavar="N",
        help="reject when the always-on text of the surface exceeds N chars (0 = no cap, the default)",
    )
    ap.add_argument(
        "--require-skill-triggers",
        action="store_true",
        help="treat a skill never named in the always-on text as an error (upstream behaviour); default is a warning "
        "because Claude Code / OMP advertise the skill catalog themselves",
    )
    ap.add_argument("--compose-out", type=Path, help="path of the merged diff (default <out-dir>/composed.diff)")
    ap.add_argument("--candidates", type=Path, help="candidate changes (JSON array)")
    ap.add_argument("--min-occurrences", type=int, default=3, help="minimum cluster size N (default 3)")
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, help=f"proposal diff directory (default {DEFAULT_OUT_DIR})")
    ap.add_argument("--experience", type=Path, help="EXPERIENCE.md to append to (default <repo-root>/agent/context/library/EXPERIENCE.md)")
    ap.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[3], help="repository root (baseline files)")
    ap.add_argument(
        "--security-cmd",
        action="append",
        help="security gate command (repeatable; `{root}` is replaced by the tree under test; also exported as "
        "HARNESS2_REPO_ROOT and used as cwd). Overrides the default test-security-rules.sh / "
        "test-write-scope-parity.sh and the HARNESS2_SECURITY_CMDS env var (newline separated); honoured in production "
        "too and reported as security_gate.overridden",
    )
    ap.add_argument("--seed", type=int, help="Training/Held-Out split seed (default: derived from the SHA-256 of the traces input)")
    ap.add_argument(
        "--allow-unsandboxed-gate",
        action="store_true",
        help="DANGEROUS: run the security gate (which executes the candidate's code from the copied tree) without bwrap "
        "isolation. Without this flag the pipeline fails closed (exit 2) when no sandbox can be created. A warning is "
        "printed to stderr and recorded in the JSON report",
    )
    ap.add_argument(
        "--gate-empty-proc",
        action="store_true",
        help="when the environment refuses a fresh procfs for the gate sandbox (common in containers), use an EMPTY /proc "
        "instead of failing closed. The host /proc is never exposed. Tools that need /proc/self (bun, so the default gates) "
        "do not work with it; use it with gates that do not need /proc",
    )
    ap.add_argument("--dry-run", action="store_true", help="evaluate only; write no EXPERIENCE.md entries or diffs")
    ap.add_argument("--json", action="store_true", help="print the report as JSON")
    return ap


def esc(s: str) -> str:
    """Escape control/invisible characters for terminal output."""
    return "".join((f"\\u{ord(c):04x}" if ord(c) <= 0xFFFF else f"\\U{ord(c):08x}") if unsafe_char(c) else c for c in s)


def run(args: argparse.Namespace) -> dict:
    if args.min_occurrences < 1:
        raise Fail("--min-occurrences must be >= 1")
    if args.always_on_cap < 0:
        raise Fail("--always-on-cap must be >= 0 (0 disables the cap)")
    if args.traces is None and not args.check_tree:
        raise Fail("--traces or --check-tree is required")
    root = args.repo_root.resolve()  # GUARD:root-resolve ({root}, cwd and HARNESS2_REPO_ROOT must agree)
    surface = DOTFILES_SURFACE
    tree_ctx: dict = {
        "surface": surface,
        "cap": args.always_on_cap,
        "require_triggers": args.require_skill_triggers,
    }
    tree_ctx["base"] = read_tree(surface, root)
    base_tree_check = validate_tree(
        surface, tree_ctx["base"], always_on_max=args.always_on_cap, require_skill_triggers=args.require_skill_triggers
    )
    tree_ctx["base_errors"] = frozenset(base_tree_check["errors"])
    if args.check_tree:
        return {"dry_run": True, "tree": base_tree_check, "warnings": base_tree_check["warnings"],
                "exit_code": 0 if base_tree_check["ok"] else 1}
    exp_path = args.experience or root / "agent/context/library/EXPERIENCE.md"
    if exp_path.name != "EXPERIENCE.md":
        raise Fail(f"--experience must point to a file named EXPERIENCE.md (got {exp_path.name})")
    root_res = root
    od = args.out_dir.resolve()  # symlinks and '..' are resolved before the check
    if od == root_res or root_res in od.parents:  # GUARD:protected-out-dir
        raise Fail(f"--out-dir {args.out_dir} is inside the repository tree {root_res} (proposals go outside the repo)")

    preflight_experience(exp_path, not args.dry_run)
    traces, digest = load_traces(args.traces)
    cands = load_candidates(args.candidates, root) if args.candidates else []
    cmds, overridden = security_commands(args)
    seed = str(args.seed) if args.seed is not None else digest
    clusters = cluster_traces(traces, args.min_occurrences)
    kept = {c["signature"]: c for c in clusters if c["status"] == "accepted"}

    warnings: list[str] = []
    if overridden:
        warnings.append(f"security gate overridden by --security-cmd/HARNESS2_SECURITY_CMDS; commands: {'; '.join(esc(c) for c in cmds)}")
    if args.allow_unsandboxed_gate:
        warnings.append("--allow-unsandboxed-gate: the gate and the candidate code in the copied tree run WITHOUT isolation")
    if yaml is None and any(classify(c["target"]) == "C6" for c in cands):
        warnings.append("PyYAML is not available: SKILL.md descriptions are checked with the conservative strict subset only "
                        "(single-line plain or simple block scalars; anything else is rejected)")
    for w in warnings:
        print(f"harness2-offline: WARNING: {w}", file=sys.stderr)

    gate_state: dict = {
        "ran": False, "ok": None, "overridden": overridden, "commands": cmds,
        "sandbox": "none (--allow-unsandboxed-gate)" if args.allow_unsandboxed_gate else None,
    }

    def get_sandbox() -> list[str] | None:
        if args.allow_unsandboxed_gate:
            return None
        sb, label = sandbox_prefix(args.gate_empty_proc)
        gate_state["sandbox"] = label
        return sb

    def gate(cand: dict) -> str | None:
        """None = pass, otherwise the rejection reason. The baseline gate runs once, candidates run on a copy."""
        sb = get_sandbox()
        if not gate_state["ran"]:
            gate_state.update(ran=True, ok=run_gate(cmds, root, sb, False)[0])
        if not gate_state["ok"]:
            return "security_gate_baseline"
        return None if gate_on_candidate(cand, cmds, root, sb)[0] else "security_gate"

    # (1) validate everything and build every diff in memory; (2) write diffs; (3) append EXPERIENCE.md last.
    results = [evaluate(c, kept, root, seed, gate, tree_ctx) for c in cands]
    diffs = [(c["id"], build_diff(c, root)) for c, r in zip(cands, results) if r["status"] == "accepted"]
    by_id = {r["id"]: r for r in results}
    if not args.dry_run:
        for cid, body in diffs:
            by_id[cid]["proposal"] = write_proposal(cid, body, args.out_dir)
    accepted = [c for c, r in zip(cands, results) if r["status"] == "accepted"]
    applied_trees = {}
    for c in accepted:
        t = dict(tree_ctx["base"])
        t[c["target"]] = c["new_text"]
        applied_trees[c["id"]] = t
    diversity = tree_diversity(applied_trees)
    composed = compose(
        surface,
        tree_ctx["base"],
        accepted,
        root,
        args.compose_out or args.out_dir / "composed.diff",
        always_on_max=args.always_on_cap,
        require_skill_triggers=args.require_skill_triggers,
        dry_run=args.dry_run,
    )
    experience = distill(clusters, exp_path, args.dry_run)
    return {
        "dry_run": args.dry_run,
        "clusters": [{k: v for k, v in c.items() if k != "sample"} for c in clusters],
        "candidates": results,
        "security_gate": gate_state,
        "tree": base_tree_check,
        "diversity": diversity,
        "composed": composed,
        "warnings": warnings,
        "experience": experience,
    }


def print_human(rep: dict) -> None:
    if "clusters" not in rep:  # --check-tree
        t = rep["tree"]
        print(f"tree: {'ok' if t['ok'] else 'INVALID'} always_on={t['always_on_chars']} chars "
              f"census={json.dumps(t['census'], sort_keys=True)}")
        for e in t["errors"]:
            print(f"error: {e}")
        for w in t["warnings"]:
            print(f"warning: {w}")
        return
    for w in rep["warnings"]:
        print(f"WARNING: {w}")
    t = rep["tree"]
    print(f"tree: {'ok' if t['ok'] else 'invalid'} always_on={t['always_on_chars']} chars census={json.dumps(t['census'], sort_keys=True)}")
    for c in rep["clusters"]:
        print(f"cluster {c['status']:8} n={c['count']} {c['scope']} {c['component']} {c['signature']!r} {c['reason'] or ''}")
    for r in rep["candidates"]:
        print(f"candidate {r['id']}: {r['status']} {','.join(r['reasons'])} {r['proposal'] or ''}".rstrip())
    co = rep["composed"]
    print(f"composed: {co['status']} applied={len(co['applied'])} conflicts={len(co['conflicts'])} {co['path'] or ''}".rstrip())
    e = rep["experience"]
    print(f"experience: +{len(e['added'])} new, {len(e['duplicates'])} duplicate{' (dry-run)' if rep['dry_run'] else ''}")


def _exit_on_signal(signo: int, _frame) -> None:
    raise SystemExit(128 + signo)  # unwinds through the gate's finally/with blocks (group kill, temp tree removal)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    sys.stdout.reconfigure(errors="backslashreplace")  # never fail on printing after EXPERIENCE.md was written
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _exit_on_signal)
    try:
        rep = run(args)
    except Fail as e:
        print(f"harness2-offline: error: {e}", file=sys.stderr)
        return 2
    except OSError as e:
        print(f"harness2-offline: error: I/O failure: {e}", file=sys.stderr)
        return 2
    except (RecursionError, ValueError, UnicodeError, MemoryError) as e:  # last-resort fail-closed (no traceback)
        print(f"harness2-offline: error: invalid input ({type(e).__name__}: {e})", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130
    rc = rep.pop("exit_code", 0)
    if args.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
    else:
        print_human(rep)
    return rc


if __name__ == "__main__":
    sys.exit(main())
