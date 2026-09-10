#!/usr/bin/env python3
"""
resolve-model-tier.py — Abstract Model Tier Resolver for Multi-Harness Architecture

Maps abstract model tiers (Low, Medium, High, XHigh, Max, Inherit) to harness-specific
concrete models and reasoning effort levels using model-routing.json.

Usage:
  resolve-model-tier.py <harness> <tier> [--format model|effort|provider|json]
  resolve-model-tier.py --check [harness]
"""

import json
import os
import sys

TIER_NAMES = ["Low", "Medium", "High", "XHigh", "Max", "Inherit"]
TIER_MAP = {t.lower(): t for t in TIER_NAMES}

def find_repo_root():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(script_dir, "../.."))

def get_harness_config_path(harness: str, root: str = None) -> str:
    if root is None:
        root = find_repo_root()
    candidates = [
        os.path.join(root, "agent", "harnesses", harness, "model-routing.json"),
        os.path.join(root, "agent", "models", f"{harness}.json"),
        os.path.join(root, harness, "model-routing.json"),
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return candidates[0]

def load_harness_config(harness: str, root: str = None) -> dict:
    cfg_path = get_harness_config_path(harness, root)
    if not os.path.isfile(cfg_path):
        raise FileNotFoundError(f"Configuration not found for harness '{harness}': {cfg_path}")
    with open(cfg_path, "r", encoding="utf-8") as f:
        return json.load(f)

def resolve_tier(harness: str, tier_str: str, root: str = None, sub_route: str = None, fallback_index: int = None, trigger: str = None) -> dict:
    clean_tier = tier_str
    if not sub_route:
        for sep in ("-", ":", "_"):
            if sep in tier_str:
                parts = tier_str.split(sep, 1)
                if parts[0].lower() in TIER_MAP:
                    clean_tier = parts[0]
                    sub = parts[1].lower()
                    if sub in ("code", "code_research"):
                        sub_route = "code_research"
                    elif sub in ("web", "web_research"):
                        sub_route = "web_research"
                    break

    normalized_tier = TIER_MAP.get(clean_tier.lower(), clean_tier)
    if normalized_tier.lower() == "inherit":
        return {
            "harness": harness,
            "tier": "Inherit",
            "model": "inherit",
            "effort": None,
            "provider": None,
            "fallbacks": [],
        }

    cfg = load_harness_config(harness, root)
    tiers = cfg.get("tiers", {})

    tier_cfg = tiers.get(normalized_tier)
    if not tier_cfg:
        default_tier = cfg.get("default_tier", "High")
        tier_cfg = tiers.get(default_tier, {})
        normalized_tier = default_tier

    target_cfg = tier_cfg
    if sub_route and "sub_routes" in tier_cfg:
        sub_cfg = tier_cfg["sub_routes"].get(sub_route)
        if sub_cfg:
            target_cfg = sub_cfg

    fallbacks = target_cfg.get("fallbacks", tier_cfg.get("fallbacks", []))

    # Fallback selection if requested
    active_cfg = target_cfg
    resolved_fallback = None
    if fallback_index is not None and 0 <= fallback_index < len(fallbacks):
        active_cfg = fallbacks[fallback_index]
        resolved_fallback = active_cfg
    elif trigger:
        matching = [f for f in fallbacks if f.get("trigger") == trigger]
        if matching:
            active_cfg = matching[0]
            resolved_fallback = active_cfg

    return {
        "harness": harness,
        "tier": normalized_tier,
        "sub_route": sub_route,
        "model": active_cfg.get("model", ""),
        "effort": active_cfg.get("effort"),
        "provider": active_cfg.get("provider"),
        "description": active_cfg.get("description", ""),
        "is_fallback": resolved_fallback is not None,
        "fallback_trigger": resolved_fallback.get("trigger") if resolved_fallback else None,
        "fallbacks": fallbacks,
    }

def validate_config(harness: str, root: str = None) -> tuple[bool, list[str]]:
    errors = []
    cfg_path = get_harness_config_path(harness, root)
    if not os.path.isfile(cfg_path):
        return False, [f"File missing: {cfg_path}"]

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return False, [f"Invalid JSON in {cfg_path}: {e}"]

    if data.get("harness") != harness:
        errors.append(f"harness field mismatch: expected '{harness}', got '{data.get('harness')}'")

    default_tier = data.get("default_tier")
    if default_tier not in TIER_NAMES:
        errors.append(f"invalid default_tier: {default_tier}")

    tiers = data.get("tiers", {})
    required_tiers = ["Low", "Medium", "High", "XHigh", "Max"]
    for rt in required_tiers:
        if rt not in tiers:
            errors.append(f"missing required tier: {rt}")
        else:
            t = tiers[rt]
            if not t.get("model"):
                errors.append(f"tier '{rt}' missing 'model' field")
            effort = t.get("effort")
            if effort and effort not in ["low", "medium", "high", "xhigh", "max"]:
                errors.append(f"tier '{rt}' has invalid effort: {effort}")

    # Cross-check referenced models against the harness's models.json catalog
    # (pi/primeagent). A tier/fallback/sub_route that references a provider/id
    # whose provider is catalogued but whose id is undefined indicates config
    # drift (e.g. a typo'd model id) that would otherwise fall through to an
    # unconfigured provider at runtime and pass every existing check. Bare native
    # aliases (no "/") and models under providers not present in the catalog
    # (e.g. anthropic native) are not catalogued in models.json and are skipped.
    models_path = os.path.join(os.path.dirname(cfg_path), "models.json")
    if os.path.isfile(models_path):
        try:
            with open(models_path, "r", encoding="utf-8") as mf:
                mdata = json.load(mf)
        except Exception as e:
            errors.append(f"invalid models.json for '{harness}': {e}")
            mdata = None
        if mdata:
            provider_models = {
                prov: {m.get("id") for m in pdata.get("models", [])}
                for prov, pdata in mdata.get("providers", {}).items()
            }

            # Field invariants on the catalog itself. These guard the
            # copy-paste drift that a cross-reference check cannot see: a
            # duplicate id within a provider (id typo on a copied entry) or a
            # maxTokens that exceeds the model's contextWindow (impossible to
            # honor at runtime).
            for prov, pdata in mdata.get("providers", {}).items():
                seen = set()
                for m in pdata.get("models", []):
                    mid = m.get("id")
                    if mid in seen:
                        errors.append(f"models.json provider '{prov}' has duplicate model id '{mid}'")
                    seen.add(mid)
                    cw, mt = m.get("contextWindow"), m.get("maxTokens")
                    if isinstance(cw, int) and isinstance(mt, int) and mt > cw:
                        errors.append(
                            f"models.json '{prov}/{mid}': maxTokens {mt} exceeds contextWindow {cw}"
                        )

            def check_ref(ref, where):
                if not ref or "/" not in ref:
                    return
                prov, _, mid = ref.partition("/")
                if prov in provider_models and mid not in provider_models[prov]:
                    errors.append(
                        f"{where} references undefined model '{ref}' "
                        f"(provider '{prov}' has no id '{mid}' in models.json)"
                    )

            for tname, t in tiers.items():
                check_ref(t.get("model"), f"tier '{tname}'")
                for fb in t.get("fallbacks", []):
                    check_ref(fb.get("model"), f"tier '{tname}' fallback ({fb.get('trigger')})")
                for sr, srd in (t.get("sub_routes") or {}).items():
                    check_ref(srd.get("model"), f"tier '{tname}' sub_route '{sr}'")

    return len(errors) == 0, errors

def main():
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)

    if sys.argv[1] == "--check":
        root = find_repo_root()
        target = sys.argv[2] if len(sys.argv) > 2 else "all"
        harnesses = ["claude", "agy", "codex", "pi", "primeagent"] if target == "all" else [target]
        has_error = False
        for h in harnesses:
            ok, errs = validate_config(h, root)
            if ok:
                print(f"PASS: {h} model-routing.json is valid")
            else:
                has_error = True
                print(f"FAIL: {h} model-routing.json validation errors:", file=sys.stderr)
                for err in errs:
                    print(f"  - {err}", file=sys.stderr)
        sys.exit(1 if has_error else 0)

    harness = sys.argv[1]
    tier = sys.argv[2] if len(sys.argv) > 2 else "High"
    fmt = "json"
    sub_route = None
    fallback_index = None
    trigger = None
    if "--format" in sys.argv:
        idx = sys.argv.index("--format")
        if idx + 1 < len(sys.argv):
            fmt = sys.argv[idx + 1]
    if "--sub-route" in sys.argv:
        idx = sys.argv.index("--sub-route")
        if idx + 1 < len(sys.argv):
            sub_route = sys.argv[idx + 1]
    if "--fallback" in sys.argv:
        idx = sys.argv.index("--fallback")
        if idx + 1 < len(sys.argv):
            try:
                fallback_index = int(sys.argv[idx + 1])
            except ValueError:
                pass
    if "--trigger" in sys.argv:
        idx = sys.argv.index("--trigger")
        if idx + 1 < len(sys.argv):
            trigger = sys.argv[idx + 1]

    try:
        res = resolve_tier(harness, tier, sub_route=sub_route, fallback_index=fallback_index, trigger=trigger)
        if fmt == "model":
            print(res.get("model", ""))
        elif fmt == "effort":
            print(res.get("effort") or "")
        elif fmt == "provider":
            print(res.get("provider") or "")
        else:
            print(json.dumps(res, indent=2))
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
