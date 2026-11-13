#!/usr/bin/env python3
"""claude/skills・pi/skills・agy/skills 配下に分散していた SKILL.stats.json を
agent/skills/<name>/SKILL.stats.json (単一正典) へマージする一回限りの移行スクリプト。

使い方: python3 scripts/merge-skill-stats.py [--check]
  --check: 書き込みは行わず、マージ後の内容が現行 agent/skills/<name>/SKILL.stats.json と
           一致するかだけを確認する(exit 1 = 差分あり)。

マージ後、呼び出し元(caller)が claude/skills・pi/skills・agy/skills 配下の SKILL.stats.json を
削除する(本スクリプト自体は削除しない — 誤って走らせて既存の統計を消してしまう事故を避けるため、
削除は明示的な別コマンドに任せる設計)。
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ECOSYSTEMS = ["claude", "pi", "agy"]


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def merge_metrics(docs):
    m = {
        "execution_count": 0,
        "success_count": 0,
        "failure_count": 0,
        "retry_count": 0,
        "total_duration_ms": 0,
        "total_tokens_in": 0,
        "total_tokens_out": 0,
        "cache_read_tokens": 0,
        "min_duration_ms": None,
        "max_duration_ms": 0,
    }
    for d in docs:
        dm = d.get("metrics", {})
        for k in ("execution_count", "success_count", "failure_count", "retry_count",
                   "total_duration_ms", "total_tokens_in", "total_tokens_out", "cache_read_tokens"):
            m[k] += dm.get(k, 0) or 0
        mind = dm.get("min_duration_ms")
        if mind:
            m["min_duration_ms"] = mind if m["min_duration_ms"] is None else min(m["min_duration_ms"], mind)
        m["max_duration_ms"] = max(m["max_duration_ms"], dm.get("max_duration_ms", 0) or 0)

    exec_count = m["execution_count"]
    m["success_rate"] = round(m["success_count"] / exec_count, 4) if exec_count > 0 else 1.0
    m["avg_duration_ms"] = round(m["total_duration_ms"] / exec_count, 2) if exec_count > 0 else 0.0
    m["avg_tokens_per_call"] = round((m["total_tokens_in"] + m["total_tokens_out"]) / exec_count, 2) if exec_count > 0 else 0.0
    m["cache_hit_rate"] = round(m["cache_read_tokens"] / m["total_tokens_in"], 4) if m["total_tokens_in"] > 0 else 0.0
    if m["min_duration_ms"] is None:
        m["min_duration_ms"] = 0
    # execution_countを最初に、残りはinit_default_statsのキー順に揃える(scripts/skill-stats.shと同じ形)
    return {
        "execution_count": m["execution_count"],
        "success_count": m["success_count"],
        "failure_count": m["failure_count"],
        "success_rate": m["success_rate"],
        "retry_count": m["retry_count"],
        "total_duration_ms": m["total_duration_ms"],
        "avg_duration_ms": m["avg_duration_ms"],
        "min_duration_ms": m["min_duration_ms"],
        "max_duration_ms": m["max_duration_ms"],
        "total_tokens_in": m["total_tokens_in"],
        "total_tokens_out": m["total_tokens_out"],
        "avg_tokens_per_call": m["avg_tokens_per_call"],
        "cache_read_tokens": m["cache_read_tokens"],
        "cache_hit_rate": m["cache_hit_rate"],
    }


def merge_lifecycle(docs):
    firsts = [d.get("lifecycle", {}).get("first_executed") for d in docs if d.get("lifecycle", {}).get("first_executed")]
    lasts = [(d.get("lifecycle", {}).get("last_executed"), d.get("lifecycle", {}).get("last_status")) for d in docs if d.get("lifecycle", {}).get("last_executed")]
    createds = [d.get("lifecycle", {}).get("created_at") for d in docs if d.get("lifecycle", {}).get("created_at")]
    last_status = "initial"
    last_executed = None
    if lasts:
        lasts.sort(key=lambda t: t[0])
        last_executed, last_status = lasts[-1]
    return {
        "created_at": min(createds) if createds else None,
        "first_executed": min(firsts) if firsts else None,
        "last_executed": last_executed,
        "last_status": last_status,
    }


def merge_failure_signatures(docs):
    by_cat = {}
    for d in docs:
        for sig in d.get("failure_signatures", []):
            cat = sig.get("category")
            if not cat:
                continue
            existing = by_cat.get(cat)
            if existing is None:
                by_cat[cat] = dict(sig)
            else:
                existing["occurrence_count"] = existing.get("occurrence_count", 0) + sig.get("occurrence_count", 0)
                if sig.get("first_seen") and (not existing.get("first_seen") or sig["first_seen"] < existing["first_seen"]):
                    existing["first_seen"] = sig["first_seen"]
                if sig.get("last_seen") and (not existing.get("last_seen") or sig["last_seen"] > existing["last_seen"]):
                    existing["last_seen"] = sig["last_seen"]
                    existing["sample_error"] = sig.get("sample_error", existing.get("sample_error", ""))
    out = list(by_cat.values())
    for i, sig in enumerate(sorted(out, key=lambda s: s.get("first_seen") or "")):
        sig["signature_id"] = f"SIG_{sig['category'].upper()}_{i + 1}"
    return out


def merge_prompt_revision_history(docs):
    seen = set()
    merged = []
    for d in docs:
        for rev in d.get("prompt_revision_history", []):
            key = (rev.get("timestamp"), rev.get("change_summary"))
            if key in seen:
                continue
            seen.add(key)
            merged.append(rev)
    merged.sort(key=lambda r: r.get("timestamp") or "")
    for i, rev in enumerate(merged):
        rev["revision"] = i + 1
    return merged


def merge_one(skill_name, docs):
    base = next((d for d in docs if d), {})
    return {
        "schema_version": base.get("schema_version", "1.0.0"),
        "skill_name": skill_name,
        "version": base.get("version", "1.0.0"),
        "description": f"Metrics and lifecycle statistics for {skill_name}",
        "category": base.get("category", "domain-specialist" if ("pattern" in skill_name or "testing" in skill_name) else "swarm-orchestrator"),
        "metrics": merge_metrics(docs),
        "lifecycle": merge_lifecycle(docs),
        "failure_signatures": merge_failure_signatures(docs),
        "prompt_revision_history": merge_prompt_revision_history(docs) or base.get("prompt_revision_history", []),
    }


def main():
    check_only = "--check" in sys.argv[1:]

    skill_names = set()
    for eco in ECOSYSTEMS:
        for p in glob.glob(os.path.join(ROOT, eco, "skills", "*", "SKILL.stats.json")):
            skill_names.add(os.path.basename(os.path.dirname(p)))

    fail = 0
    for skill_name in sorted(skill_names):
        docs = []
        for eco in ECOSYSTEMS:
            p = os.path.join(ROOT, eco, "skills", skill_name, "SKILL.stats.json")
            d = load(p)
            if d:
                docs.append(d)
        if not docs:
            continue
        merged = merge_one(skill_name, docs)
        dst = os.path.join(ROOT, "agent", "skills", skill_name, "SKILL.stats.json")

        if check_only:
            current = load(dst)
            if current != merged:
                print(f"STALE: agent/skills/{skill_name}/SKILL.stats.json")
                fail = 1
            else:
                print(f"OK: agent/skills/{skill_name}/SKILL.stats.json")
            continue

        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8") as f:
            json.dump(merged, f, indent=2)
            f.write("\n")
        print(f"merged {len(docs)} source(s) -> agent/skills/{skill_name}/SKILL.stats.json "
              f"(execution_count={merged['metrics']['execution_count']})")

    sys.exit(fail)


if __name__ == "__main__":
    main()
