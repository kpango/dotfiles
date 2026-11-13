#!/usr/bin/env bash
# Antigravity PreToolUse Vald Law Enforcer (Laws 1-5)
#
# ルールデータは agent/vald-law-rules.json (claude/agy/pi 共通) を読む。判定アルゴリズムは
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み(2026-09-03)。本ファイルは
# I/Oプロトコル変換のみを持つ薄いシム。
#
# この統合で解消した既存バグ: Law1の `f"Vald Law 1 violation: {law1_msg}"` は law1_msg 自体が
# 既に同じ接頭辞で始まっており出力が二重になっていた(claude/piは元々 law1_message をそのまま
# 使っており二重化していなかった)。共有エンジンが返す reason をそのまま使うことで自然に解消される。
# また Law3/4/5 の出力メッセージは agy独自の「行番号+該当行の引用+先頭5件までの切り詰め」形式
# から claude と同じ「ルール単位のメッセージ一覧」形式へ統一される(振る舞い変更として意図的に
# 受け入れる、decision自体(deny)は変わらない)。
set -euo pipefail

PAYLOAD=$(cat)

if ! command -v python3 &>/dev/null; then
    echo '{"decision":"allow"}'
    exit 0
fi

# ~/.agy/hooks・~/.gemini/hooks は agy/hooks/ と agent/hooks/agy/ の2ソースを合成したmerged
# directory(per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/vald-law-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

if [[ ! -f "$RULES_FILE" ]] || [[ ! -f "$DECIDE" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

RULES_FILE="$RULES_FILE" DECIDE="$DECIDE" python3 -c '
import json, os, subprocess, sys

try:
    data = json.loads(sys.stdin.read() or "{}")
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

tool_call = data.get("toolCall", {})
tool_name = tool_call.get("name") or data.get("tool_name", "")
args = tool_call.get("args") or data.get("tool_input", {})
workspaces = data.get("workspacePaths", [])

def allow():
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

def deny(reason):
    print(json.dumps({"decision": "deny", "reason": reason}))
    sys.exit(0)

def call_decide(request):
    try:
        proc = subprocess.run(
            [sys.executable, os.environ["DECIDE"]],
            input=json.dumps(request),
            capture_output=True, text=True, timeout=10,
        )
        return json.loads(proc.stdout)
    except Exception:
        # decide.py 自体が起動できない/クラッシュした場合も fail-open(致命的にしない、他hookと同じ方針)
        return {"decision": "allow"}

RULES_FILE = os.environ["RULES_FILE"]

# ---------------------------------------------------------
# Vald Law 1: Protobuf Generation Law (PreToolUse Write/Edit)
# ---------------------------------------------------------
if tool_name in ("write_to_file", "replace_file_content", "edit_file"):
    target = args.get("TargetFile") or args.get("file_path", "")
    result = call_decide({"family": "vald_law1", "file_path": target, "vald_rules_file": RULES_FILE})
    if result.get("decision") == "block":
        deny(result.get("reason", "Vald Law 1 violation"))

# ---------------------------------------------------------
# Vald Law 2: Make Target Authority Law (PreToolUse run_command)
# ---------------------------------------------------------
if tool_name in ("run_command", "bash", "run_shell_command"):
    cmd = (args.get("CommandLine") or args.get("command", "")).strip()
    result = call_decide({
        "family": "vald_law2",
        "command": cmd,
        "cwd": os.getcwd(),
        "vald_rules_file": RULES_FILE,
        "scope_mode": "workspace_and_cwd_and_command_string",
        "workspaces": workspaces,
    })
    if result.get("decision") == "block":
        deny(result.get("reason", "Vald Law 2 violation"))

# ---------------------------------------------------------
# Vald Laws 3, 4, 5: Content Verification on Go File Edits
# ---------------------------------------------------------
# security-audit指摘(2026-09-03): is_vald を workspacePaths のみで判定すると、Write/Editの
# 実ターゲットパスがvald配下でもworkspacePathsにvald一致entryが無ければ丸ごとすり抜けた
# (pi実装は元々ctx.cwdとresolvedPathの両方をORしており、agyだけこの判定漏れがあった)。
# scope_mode="workspace_and_cwd_and_command_string" は共有エンジン側で
# [cwd, file_path] + workspaces の全候補をOR判定するため、この判定漏れは構造的に再発しない。
if tool_name in ("write_to_file", "replace_file_content", "edit_file"):
    target = args.get("TargetFile") or args.get("file_path", "")
    content = args.get("CodeContent") or args.get("ReplacementContent") or ""
    if content:
        result = call_decide({
            "family": "vald_law345",
            "file_path": target,
            "content": content,
            "vald_rules_file": RULES_FILE,
            "scope_mode": "workspace_and_cwd_and_command_string",
            "cwd": os.getcwd(),
            "workspaces": workspaces,
        })
        if result.get("decision") == "ask":
            violations = result.get("violations") or []
            if violations:
                # 旧実装どおり先頭5件までに切り詰める(claudeは無制限、agy/piは元々5件上限
                # だった書式上の差異を保持する — decisionそのものへの影響は無い)。
                deny("Vald Law violation(s) detected in Go source:\n" + "\n".join(f"- {v}" for v in violations[:5]))

allow()
' <<< "$PAYLOAD"
