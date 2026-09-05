"""claude/hooks・agy/hooks・pi/extensions で3回独立に再実装されていた判定アルゴリズムの
単一正典実装。ルール**データ**は既に agent/security-rules.json・agent/vald-law-rules.json・
agent/graphify-hint-config.json へ集約済み(claude/agy/pi 共通)だったが、判定ロジック自体
(all_of/any_of/not_any_of の評価・force_push/git_reset_hard/vald_law2 の cd/-C ターゲット解決・
sensitive_write_path の複数候補照合)は bash(claude)・bash+埋め込みPython(agy)・
TypeScript(pi)で3回書かれていた。本モジュールはそれを1箇所へ統合する(2026-09-03)。

各ツールの薄いシム(claude/hooks/*.sh・agy/hooks/*.sh は decide.py をsubprocess呼び出し、
pi/extensions/*.ts は child_process 経由で decide.py を呼ぶ)が、stdin/stdout の
プロトコル変換・3値/2値の値域変換・UI確認ダイアログ(piのみ)を担当し、本モジュールは
「このコマンド/パスは判定データに対してどう評価されるか」という意味のみを持つ。

意図的にツールごとに異なる挙動(cd/-Cターゲット解決の有無・vald判定の基準)は、呼び出し側が
明示的に選ぶパラメータとして残す(黙って1つに揃えない)。
"""
from __future__ import annotations

import os
import re
import subprocess


# ---------------------------------------------------------------------------
# 汎用条件評価(all_of / any_of / not_any_of)
# 既存3実装(claude: grep -P、agy: Python re、pi: Node RegExp)で意味論が完全一致することを
# 確認済み(pi-ext-research系の調査+既存test-security-rules.shの全ケースで検証)。
# ---------------------------------------------------------------------------

def matches_all_of(rule: dict, text: str) -> bool:
    for pat in rule.get("all_of", []) or []:
        if not re.search(pat, text):
            return False
    return True


def matches_any_of(rule: dict, text: str, field: str = "any_of") -> bool:
    patterns = rule.get(field) or []
    if not patterns:
        return True
    return any(re.search(p, text) for p in patterns)


def matches_not_any_of(rule: dict, text: str) -> bool:
    for pat in rule.get("not_any_of", []) or []:
        if re.search(pat, text):
            return False
    return True


# ---------------------------------------------------------------------------
# force_push_protected_branch: {branches} テンプレート展開 + all_of/target_pattern/
# any_of_with_branches のいずれか一致。
# ---------------------------------------------------------------------------

def eval_force_push(rule: dict, command: str) -> bool:
    if not matches_all_of(rule, command):
        return False
    branches = "|".join(rule.get("protected_branches", []))
    target_pattern = (rule.get("target_branch_pattern") or "").replace("{branches}", branches)
    # pi実装のみ持っていた空文字ガードを正典に採用する(target_patternが空だと
    # re.search("", cmd)は常に真になり判定が壊れるため、他2実装は現行ルールデータに
    # 値が必ず入っているため実害が無かっただけの潜在的な穴だった)。
    if not target_pattern or not re.search(target_pattern, command):
        return False
    for pat in rule.get("any_of_with_branches", []) or []:
        if re.search(pat.replace("{branches}", branches), command):
            return True
    return False


# ---------------------------------------------------------------------------
# cd/-C ターゲットディレクトリ解決。claudeのVald Law2は意図的にこれを使わない
# (project-scoped配線で足りる上、cwdベース判定を足すとcdバイパスの温床になった経緯がある
# — agent/vald-law-rules.jsonの$comment参照)。pi/agyのVald Law2・3実装共通のgit_reset_hard
# はこれを使う。
#
# クォート除去は前後1文字のみ(agy/piと同じ、claude旧bash実装の「文字列中の全"'"除去」は
# 意図的な設計ではなく単なる実装差だったため、より保守的な前後除去へ統一する)。
# ---------------------------------------------------------------------------

def resolve_command_target_dir(
    command: str,
    cwd: str,
    cd_pattern: str | None,
    dash_c_pattern: str | None,
    absolutize: bool = True,
) -> str:
    """コマンド文字列から cd/-C の対象ディレクトリを抽出する。cd優先、次に-C、
    どちらも無ければ"."(hookプロセス/セッションのcwd相当)を返す。
    absolutize=True: 相対パスを os.path.join(cwd, target) で絶対化する(pi/agy方式)。
    absolutize=False: 抽出した文字列をそのまま返す(claude方式、hookプロセスのcwd基準で
    `git -C`自身に解決させる)。
    """
    target_dir = None
    if cd_pattern:
        m = re.search(cd_pattern, command)
        if m:
            target_dir = m.group(1).strip().strip("\"'")
    if target_dir is None and dash_c_pattern:
        m2 = re.search(dash_c_pattern, command)
        if m2:
            target_dir = m2.group(1).strip("\"'")
    if target_dir is None:
        target_dir = "."
    if absolutize and not os.path.isabs(target_dir):
        target_dir = os.path.normpath(os.path.join(cwd, target_dir))
    return target_dir


def _git_branch(target_dir: str) -> str:
    try:
        proc = subprocess.run(
            ["git", "-C", target_dir, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        return proc.stdout.strip()
    except Exception:
        return ""


def eval_git_reset_hard(rule: dict, command: str, cwd: str, absolutize: bool = True) -> bool:
    if not matches_all_of(rule, command):
        return False
    if not matches_not_any_of(rule, command):
        return False
    target_dir = resolve_command_target_dir(
        command, cwd, rule.get("cd_target_pattern"), rule.get("dash_c_target_pattern"), absolutize=absolutize
    )
    branch = _git_branch(target_dir)
    return branch in (rule.get("protected_branches") or [])


# ---------------------------------------------------------------------------
# shell_command_rules 全体の評価。呼び出し側(claude shim)がblock全件→ask全件の2パス評価
# 順序を再現できるよう、tierでフィルタしたリストを渡す形にする。
# ---------------------------------------------------------------------------

def evaluate_rule(rule: dict, command: str, cwd: str, resolve_command_target: bool = True) -> bool:
    rid = rule.get("id")
    if rid == "force_push_protected_branch":
        return eval_force_push(rule, command)
    if rid == "git_reset_hard_protected_branch":
        return eval_git_reset_hard(rule, command, cwd, absolutize=resolve_command_target)
    return (
        matches_all_of(rule, command)
        and matches_any_of(rule, command, "any_of")
        and matches_not_any_of(rule, command)
    )


def eval_shell_command_rules(rules: list[dict], command: str, cwd: str, resolve_command_target: bool = True):
    """一致したルールを [(id, tier, description), ...] で全件返す(宣言順)。
    呼び出し側がtierごとの優先順位付けを行う。"""
    matched = []
    for rule in rules:
        if evaluate_rule(rule, command, cwd, resolve_command_target=resolve_command_target):
            matched.append((rule.get("id"), rule.get("tier"), rule.get("description")))
    return matched


# ---------------------------------------------------------------------------
# sensitive_write_path_rules: 複数パス候補(raw/expanded/resolved/normalized/canonical)の
# いずれかがcase-insensitiveでマッチしたら該当。候補生成自体はツールごとに1〜5個と揺れて
# いたため、最も広い(pi方式の5候補)を正典として全ツールに適用する(安全側統合、
# agent/security-rules.jsonの$comment「最も保護範囲が広い版を正典とする」方針を踏襲)。
# ---------------------------------------------------------------------------

def resolve_write_path_candidates(raw_path: str, cwd: str, home: str) -> list[str]:
    expanded = os.path.join(home, raw_path[1:].lstrip("/")) if raw_path.startswith("~") else raw_path
    resolved = expanded if os.path.isabs(expanded) else os.path.normpath(os.path.join(cwd, expanded))
    normalized = os.path.normpath(resolved)
    try:
        canonical = os.path.realpath(normalized)
    except Exception:
        canonical = normalized
    return [raw_path, expanded, resolved, normalized, canonical]


def eval_sensitive_write_path(rules: list[dict], candidates: list[str]):
    """最初に一致したルールを (id, label) で返す。無ければ None。"""
    for rule in rules:
        pat = rule.get("pattern", "")
        if not pat:
            continue
        for candidate in candidates:
            if re.search(pat, candidate, re.IGNORECASE):
                return (rule.get("id"), rule.get("label", rule.get("id", "")))
    return None


# ---------------------------------------------------------------------------
# Vald Law
# ---------------------------------------------------------------------------

def eval_vald_law1(vald_rules: dict, file_path: str):
    """一致すれば law1_message を返す、しなければ None。"""
    pattern = vald_rules.get("law1_generated_file_pattern")
    if pattern and re.search(pattern, file_path):
        return vald_rules.get("law1_message", "Vald Law 1 violation")
    return None


def vald_command_targets(command: str, cwd: str, vald_rules: dict, scope_mode: str) -> bool:
    """Vald Law2のスコープ判定。scope_modeで既存3実装の意図的な差異を保持する:
    - "none": スコープ判定をしない(常にTrue) — claude、project-scoped配線に依存するため
    - "cwd_and_resolved_path": ctx.cwd または cd/-C解決後の絶対パスが一致 — pi方式
    - "workspace_and_cwd_and_command_string": workspace一覧・os.getcwd()・コマンド文字列
      そのもの・cd/-C解決後の絶対パスの4項OR — agy方式
    """
    pattern = vald_rules.get("vald_repo_pattern", "")
    if scope_mode == "none":
        return True
    if scope_mode in ("cwd_and_resolved_path", "workspace_and_cwd_and_command_string"):
        if re.search(pattern, cwd, re.IGNORECASE):
            return True
        # workspace一覧はこの関数の呼び出し側(shim)が先にチェックすることを想定し、ここでは
        # cwd・コマンド文字列自体・cd/-C解決後の絶対パスを見る(workspace分はshim側でOR)。
        # security-audit指摘(2026-09-03): 元々このscope_modeはディレクトリ解決を行わず、
        # `cd ../vald && go build` のような相対パスcdでcommand文字列自体にvald_repo_patternが
        # literal に出現しないケースを検出できなかった(cwd_and_resolved_pathとの非対称な
        # 弱点)。既存の一致経路を狭めない検出範囲の拡張のみのため、他scope_modeの挙動には
        # 影響しない。
        if scope_mode == "workspace_and_cwd_and_command_string" and re.search(pattern, command, re.IGNORECASE):
            return True
        target_dir = resolve_command_target_dir(
            command, cwd, vald_rules.get("cd_target_pattern"), vald_rules.get("dash_c_target_pattern"),
            absolutize=True,
        )
        if target_dir == ".":
            return False
        return bool(re.search(pattern, target_dir, re.IGNORECASE))
    raise ValueError(f"unknown scope_mode: {scope_mode}")


def eval_vald_law2(vald_rules: dict, command: str, cwd: str, scope_mode: str, workspaces: list[str] | None = None):
    """一致すれば (id, remediation) を返す、しなければ None。"""
    in_scope = False
    if scope_mode == "workspace_and_cwd_and_command_string" and workspaces:
        pattern = vald_rules.get("vald_repo_pattern", "")
        in_scope = any(re.search(pattern, ws, re.IGNORECASE) for ws in workspaces)
    if not in_scope:
        in_scope = vald_command_targets(command, cwd, vald_rules, scope_mode)
    if not in_scope:
        return None
    for rule in vald_rules.get("law2_prohibited_commands", []) or []:
        if re.search(rule.get("pattern", ""), command):
            return (rule.get("id"), rule.get("remediation", ""))
    return None


def _strip_go_comment(line: str) -> str:
    # "//"以降を切り捨てる(3実装とも同じ意味論: bashの${line%%//*}・Pythonのre.sub(r"//.*$","",line)・
    # TSのsplit("//")[0] はいずれも「最初の// より前」を残す点で等価)。
    idx = line.find("//")
    return (line if idx < 0 else line[:idx]).strip()


def eval_vald_law345(vald_rules: dict, file_path: str, content: str, is_vald_scope: bool):
    """違反メッセージのリストを返す(空リスト = 違反なし)。呼び出し側で件数上限・整形を行う。"""
    if not is_vald_scope:
        return []
    if not file_path.endswith(".go"):
        return []
    if vald_rules.get("law345_exclude_test_files", True) and file_path.endswith("_test.go"):
        return []
    if not content:
        return []
    violations = []
    for raw_line in content.split("\n"):
        clean = _strip_go_comment(raw_line)
        if not clean:
            continue
        for rule in vald_rules.get("law345_go_content_rules", []) or []:
            if re.search(rule.get("pattern", ""), clean):
                violations.append(rule.get("message", rule.get("id", "")))
                break
    return violations


# ---------------------------------------------------------------------------
# graphify-hint
# ---------------------------------------------------------------------------

def eval_graphify_hint(config: dict, command: str, search_bases: list[str]) -> str | None:
    """一致すればhint_messageを返す、しなければNone。search_basesは呼び出し側が
    claude=[cwd]・agy=workspacePaths(無ければ[os.getcwd()])・pi=[ctx.cwd] のように用意する。"""
    pattern = config.get("command_pattern", "")
    if not pattern or not re.search(pattern, command):
        return None
    relative_paths = config.get("graph_relative_paths", []) or []
    for base in search_bases:
        for rel in relative_paths:
            if os.path.exists(os.path.join(base, rel)):
                return config.get("hint_message")
    return None
