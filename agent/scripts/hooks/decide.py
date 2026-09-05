#!/usr/bin/env python3
"""rule_engine.py を各ツールのシム(claude/hooks/*.sh・agy/hooks/*.sh・pi/extensions/*.ts)から
呼び出すためのCLIエントリポイント。

stdinで正規化済みJSONを受け取り、stdoutへ正規化済みの決定JSONを1行で返す。exit codeは常に0
(判定結果はstdoutのJSONで表現し、シム側がツール固有のexit code/JSON形式へ変換する)。

入力(stdinのJSON、"family"で分岐):
  security_shell:  {family, command, cwd, rules_file, resolve_command_target}
  security_write:  {family, file_path, cwd, home, rules_file}
  vald_law1:        {family, file_path, vald_rules_file}
  vald_law2:        {family, command, cwd, vald_rules_file, scope_mode, workspaces?}
  vald_law345:      {family, file_path, content, vald_rules_file, scope_mode, cwd?, workspaces?}
  graphify_hint:    {family, command, config_file, search_bases}
  memory_context:   {family, memory_dirs, local_files, cwd, index_head?, topic_head?,
                      local_head?, multi_dir_labels?, local_all_matches?}

出力(stdoutのJSON、1行):
  {"decision": "allow"|"ask"|"block", "reason": "...", "matches": [...]}
  security_shell はtier別に "block_matches"/"ask_matches" のIDリストも含める(シム側が
  claudeの「block全件→ask全件」評価順序を再現できるようにするため)。
  memory_contextは decision/reason を持たず {"context": "...", "file_count": N, "byte_count": N,
  "matched_local": bool} を返す(判定ではなくデータ合成のため、他familyと出力shapeが異なる)。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rule_engine as re_  # noqa: E402
import memory_context as mc_  # noqa: E402


def _load_json(path: str):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _out(decision: str, reason: str = "", **extra):
    payload = {"decision": decision, "reason": reason}
    payload.update(extra)
    print(json.dumps(payload))
    sys.exit(0)


def handle_security_shell(req: dict):
    rules_data = _load_json(req["rules_file"])
    if not rules_data:
        _out("allow", "rules file missing/invalid (fail-open)")
    command = req.get("command", "")
    cwd = req.get("cwd", ".")
    resolve_target = req.get("resolve_command_target", True)
    all_rules = rules_data.get("shell_command_rules", [])

    # all_matches: JSON宣言順のまま全一致ルールを返す(pi実装が「宣言順に1パスで走査し、
    # hasUI時はマッチ毎にconfirmを出し承認後も走査継続する」挙動を再現するために必要
    # — claude/agyはこのフィールドを使わずtop-levelのdecision/reasonのみ参照する)。
    # tier/descriptionをここで直接埋め込む(呼び出し側にモジュールロード時キャッシュ等の
    # 別経路でルール定義を再取得させない設計 — security-audit指摘2026-09-03: 呼び出し側が
    # idだけを受け取り自前の陳腐化しうるキャッシュから逆引きすると、decide.pyがフレッシュに
    # 読んだルールファイルとキャッシュがズレた場合にマッチが未確認のまま握り潰される穴になる。
    # decide.py自身が"今読んだばかりの"rules_dataから直接tier/descriptionを渡すことで、
    # 呼び出し側がローカルキャッシュを持つ必要そのものを無くす)。
    all_matches = [
        {"id": r.get("id"), "tier": r.get("tier"), "description": r.get("description")}
        for r in all_rules
        if re_.evaluate_rule(r, command, cwd, resolve_command_target=resolve_target)
    ]

    # top-level decision: block全件→ask全件の2パス評価(claude/agyの historical な優先順位、
    # ask()がexit 0で即終了するため先に評価すると複合コマンドで後続のblock条件に到達できない
    # 罠への対策)。
    block_rules = [r for r in all_rules if r.get("tier") == "block"]
    ask_rules = [r for r in all_rules if r.get("tier") == "ask"]
    for rule in block_rules:
        if re_.evaluate_rule(rule, command, cwd, resolve_command_target=resolve_target):
            _out("block", rule.get("description", ""), matched_rule_id=rule.get("id"), all_matches=all_matches)
    for rule in ask_rules:
        if re_.evaluate_rule(rule, command, cwd, resolve_command_target=resolve_target):
            _out("ask", rule.get("description", ""), matched_rule_id=rule.get("id"), all_matches=all_matches)
    _out("allow", all_matches=all_matches)


def handle_security_write(req: dict):
    rules_data = _load_json(req["rules_file"])
    if not rules_data:
        _out("allow", "rules file missing/invalid (fail-open)")
    candidates = re_.resolve_write_path_candidates(
        req.get("file_path", ""), req.get("cwd", "."), req.get("home", "")
    )
    hit = re_.eval_sensitive_write_path(rules_data.get("sensitive_write_path_rules", []), candidates)
    if hit:
        rule_id, label = hit
        _out("block", label, matched_rule_id=rule_id, resolved_path=candidates[2])
    _out("allow")


def handle_vald_law1(req: dict):
    vald_rules = _load_json(req["vald_rules_file"])
    if not vald_rules:
        _out("allow", "vald rules file missing/invalid (fail-open)")
    msg = re_.eval_vald_law1(vald_rules, req.get("file_path", ""))
    if msg:
        _out("block", msg, matched_rule_id="law1")
    _out("allow")


def handle_vald_law2(req: dict):
    vald_rules = _load_json(req["vald_rules_file"])
    if not vald_rules:
        _out("allow", "vald rules file missing/invalid (fail-open)")
    hit = re_.eval_vald_law2(
        vald_rules,
        req.get("command", ""),
        req.get("cwd", "."),
        req.get("scope_mode", "none"),
        workspaces=req.get("workspaces"),
    )
    if hit:
        rule_id, remediation = hit
        _out("block", f"Vald Law 2 violation: {remediation}", matched_rule_id=rule_id)
    _out("allow")


def handle_vald_law345(req: dict):
    vald_rules = _load_json(req["vald_rules_file"])
    if not vald_rules:
        _out("allow", "vald rules file missing/invalid (fail-open)")
    scope_mode = req.get("scope_mode", "none")
    if scope_mode == "none":
        is_vald_scope = True
    else:
        pattern = vald_rules.get("vald_repo_pattern", "")
        import re as _re
        candidates = [req.get("cwd", ""), req.get("file_path", "")] + list(req.get("workspaces") or [])
        is_vald_scope = any(_re.search(pattern, c, _re.IGNORECASE) for c in candidates if c)
    violations = re_.eval_vald_law345(
        vald_rules, req.get("file_path", ""), req.get("content", ""), is_vald_scope
    )
    if violations:
        _out("ask", "", violations=violations)
    _out("allow")


def handle_memory_context(req: dict):
    result = mc_.compose_memory_context(
        req.get("memory_dirs", []),
        req.get("local_files", []),
        req.get("cwd", "."),
        index_head=req.get("index_head", 200),
        topic_head=req.get("topic_head", 150),
        local_head=req.get("local_head"),
        multi_dir_labels=req.get("multi_dir_labels", False),
        local_all_matches=req.get("local_all_matches", False),
    )
    print(json.dumps(result))
    sys.exit(0)


def handle_graphify_hint(req: dict):
    config = _load_json(req["config_file"])
    if not config:
        _out("allow", "config file missing/invalid (fail-open)")
    hint = re_.eval_graphify_hint(config, req.get("command", ""), req.get("search_bases", []))
    if hint:
        _out("allow", hint, hint=hint)
    _out("allow")


HANDLERS = {
    "security_shell": handle_security_shell,
    "security_write": handle_security_write,
    "vald_law1": handle_vald_law1,
    "vald_law2": handle_vald_law2,
    "vald_law345": handle_vald_law345,
    "graphify_hint": handle_graphify_hint,
    "memory_context": handle_memory_context,
}


def main():
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except Exception:
        _out("allow", "invalid input JSON (fail-open)")
    family = req.get("family")
    handler = HANDLERS.get(family)
    if not handler:
        _out("allow", f"unknown family: {family} (fail-open)")
    handler(req)


if __name__ == "__main__":
    main()
