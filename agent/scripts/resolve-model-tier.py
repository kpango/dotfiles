#!/usr/bin/env python3
"""
resolve-model-tier.py — Abstract Model Tier Resolver for Multi-Harness Architecture

Maps abstract model tiers (Low, Medium, High, XHigh, Max, Inherit) to harness-specific
concrete models and reasoning effort levels using model-routing.json.

Usage:
  resolve-model-tier.py <harness> <tier> [--format model|effort|provider|json]
  resolve-model-tier.py --check [harness]
  resolve-model-tier.py --quota-guard [harness]   # advisory JSON: is OpenCode Go usage over the routingPolicy limits?

--quota-guard reads routingPolicy.openCodeGoQuotaGuard from <harness>/model-routing.json (default omp) and the measured
usage from env OPENCODE_GO_USAGE_5H_PCT / OPENCODE_GO_USAGE_WEEK_PCT, else from ~/.omp/agent/quota/opencode-go.json
({"fiveHourPct": n, "weeklyPct": n}). Nothing in this repo measures the usage; whatever does must write one of those.
"over" is true / false / null (null = enabled but no usable usage figure: unknown, never reported as fine).
It never switches a model; it only says where high-volume subagent fan-out should go (highVolumeSubagentDefault).
"""

import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    yaml = None

VALID_HARNESSES = ["claude", "agy", "omp", "hermes"]
TIER_NAMES = ["Low", "Medium", "High", "XHigh", "Max", "Inherit"]
REQUIRED_TIERS = ["Low", "Medium", "High", "XHigh", "Max"]
VALID_EFFORTS = {"low", "medium", "high", "xhigh", "max"}
VALID_TRIGGERS = {
    "rate_limit",
    "token_exhaustion",
    "context_overflow",
    "cost_saver",
    "unavailability",
}
OMP_EFFORT_SUFFIXES = {"low", "medium", "high", "xhigh", "max", "minimal", "off"}
TIER_MAP = {t.lower(): t for t in TIER_NAMES}
DEFAULT_ALIAS_TO_TIER = {
    "@smol": "Low",
    "@fast": "Low",
    "@good": "High",
    "@review": "XHigh",
    "@slow": "Max",
    "@plan": "Max",
    "smol": "Low",
    "fast": "Low",
    "good": "High",
    "review": "XHigh",
    "slow": "Max",
    "plan": "Max",
    "haiku": "Low",
    "sonnet": "High",
    "opus": "XHigh",
    "fable": "Max",
}

def load_alias_map(root: str = None) -> dict:
    aliases = dict(DEFAULT_ALIAS_TO_TIER)
    base = root if root else find_repo_root()
    cat_path = os.path.join(base, "agent", "models", "catalog.json")
    if os.path.isfile(cat_path):
        try:
            with open(cat_path, "r", encoding="utf-8") as cf:
                cat = json.load(cf)
            for src_key in ("role_aliases", "legacy_aliases"):
                for k, v in (cat.get(src_key) or {}).items():
                    if isinstance(k, str) and isinstance(v, str):
                        lk = k.strip().lower()
                        aliases[lk] = v
                        if lk.startswith("@"):
                            aliases[lk[1:]] = v
        except Exception:
            pass
    return aliases

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

PARENT_MODEL_ENV_VARS = ("OMP_PARENT_MODEL", "CLAUDE_PARENT_MODEL", "PARENT_MODEL")
_PARENT_MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/@\[\]-]{0,199}$")


def _check_parent_model(value: str, src: str) -> str:
    if not _PARENT_MODEL_RE.fullmatch(value):
        raise ValueError(f"invalid parent model from {src}: {value!r}")
    return value


def resolve_tier(harness: str, tier_str: str, root: str = None, sub_route: str = None, fallback_index: int = None, trigger: str = None) -> dict:
    aliases = load_alias_map(root)
    clean_tier = aliases.get(tier_str.strip().lower(), tier_str)
    if not sub_route:
        for sep in ("-", ":", "_"):
            if sep in clean_tier:
                parts = clean_tier.split(sep, 1)
                if parts[0].lower() in TIER_MAP:
                    clean_tier = parts[0]
                    sub = parts[1].lower()
                    if sub in ("code", "code_research"):
                        sub_route = "code_research"
                    elif sub in ("web", "web_research"):
                        sub_route = "web_research"
                    break

    normalized_tier = TIER_MAP.get(clean_tier.lower(), clean_tier)
    cfg = load_harness_config(harness, root)
    tiers = cfg.get("tiers", {})

    if normalized_tier.lower() == "inherit":
        # D12 resolution order: OMP_PARENT_MODEL -> CLAUDE_PARENT_MODEL -> PARENT_MODEL
        # -> tiers.Inherit.primary -> resolved default_tier.
        # Unset / empty / whitespace-only values are skipped; a set but malformed value
        # (control chars, whitespace inside, over-long, bad charset) is fail-closed (ValueError).
        inh_cfg = tiers.get("Inherit") if isinstance(tiers.get("Inherit"), dict) else {}
        flags = {
            "inheritFromParent": inh_cfg.get("inheritFromParent", True),
            "preservePromptCachePrefix": inh_cfg.get("preservePromptCachePrefix", True),
        }

        def _inherited(model, src):
            return {
                "harness": harness,
                "tier": "Inherit",
                "model": _check_parent_model(model, src),
                "effort": inh_cfg.get("effort"),
                "provider": inh_cfg.get("provider"),
                **flags,
                "fallbacks": [],
            }

        for var in PARENT_MODEL_ENV_VARS:
            val = os.environ.get(var)
            if val is not None and val.strip():
                return _inherited(val.strip(), var)
        primary = inh_cfg.get("primary") or inh_cfg.get("model")
        if primary:
            if primary.lower() in TIER_MAP and primary.lower() != "inherit":
                res = resolve_tier(harness, TIER_MAP[primary.lower()], root=root)
                res["tier"] = "Inherit"
                return res
            return _inherited(primary, "tiers.Inherit.primary")
        default_tier = cfg.get("default_tier", "High")
        if str(default_tier).lower() == "inherit":
            default_tier = "High"
        res = resolve_tier(harness, default_tier, root=root)
        res["tier"] = "Inherit"
        res.update(flags)
        return res

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

    result = {
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
    if "max_context_tokens" in active_cfg:
        result["max_context_tokens"] = active_cfg["max_context_tokens"]
    if "compaction_threshold" in active_cfg:
        result["compaction_threshold"] = active_cfg["compaction_threshold"]
    return result

def _validate_compaction_bounds(obj: dict, where: str, errors: list[str]) -> None:
    mc = obj.get("max_context_tokens")
    ct = obj.get("compaction_threshold")
    for field, val in (("max_context_tokens", mc), ("compaction_threshold", ct)):
        if val is not None and (isinstance(val, bool) or not isinstance(val, int) or val < 1):
            errors.append(f"{where} has invalid {field}: {val!r} (expected positive integer)")
    if (
        isinstance(mc, int)
        and not isinstance(mc, bool)
        and isinstance(ct, int)
        and not isinstance(ct, bool)
        and ct > mc
    ):
        errors.append(f"{where}: compaction_threshold ({ct}) exceeds max_context_tokens ({mc})")


def _strip_omp_effort(ref: str) -> str:
    if ":" not in ref:
        return ref
    base, _, suffix = ref.rpartition(":")
    if suffix.lower() in OMP_EFFORT_SUFFIXES:
        return base
    return ref


def _load_catalog(harness_dir: str, harness: str, errors: list[str]) -> tuple[str | None, dict | None]:
    models_yml = os.path.join(harness_dir, "models.yml")
    models_json = os.path.join(harness_dir, "models.json")
    if os.path.isfile(models_yml):
        if yaml is None:
            errors.append(f"PyYAML is required to validate {models_yml}")
            return "models.yml", None
        try:
            with open(models_yml, "r", encoding="utf-8") as mf:
                mdata = yaml.safe_load(mf)
            if not isinstance(mdata, dict):
                errors.append(f"invalid models.yml for '{harness}': top-level must be a mapping")
                return "models.yml", None
            return "models.yml", mdata
        except Exception as e:
            errors.append(f"invalid models.yml for '{harness}': {e}")
            return "models.yml", None
    if os.path.isfile(models_json):
        try:
            with open(models_json, "r", encoding="utf-8") as mf:
                mdata = json.load(mf)
            return "models.json", mdata
        except Exception as e:
            errors.append(f"invalid models.json for '{harness}': {e}")
            return "models.json", None
    return None, None


QUOTA_GUARD_KEYS = {"enabled", "fiveHourMaxPct", "weeklyMaxPct", "highVolumeSubagentDefault"}


def _is_pct(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and 0 < v <= 100


def validate_routing_policy(policy) -> list[str]:
    """schema.json RoutingPolicy, checked by hand like the rest of validate_config."""
    if not isinstance(policy, dict):
        return ["routingPolicy must be an object"]
    errors = []
    extra = set(policy) - {"openCodeGoQuotaGuard"}
    if extra:
        errors.append(f"routingPolicy has unexpected properties: {sorted(extra)}")
    guard = policy.get("openCodeGoQuotaGuard")
    if guard is None:
        return errors
    if not isinstance(guard, dict):
        return errors + ["routingPolicy.openCodeGoQuotaGuard must be an object"]
    missing = QUOTA_GUARD_KEYS - set(guard)
    if missing:
        errors.append(f"openCodeGoQuotaGuard is missing: {sorted(missing)}")
    extra = set(guard) - QUOTA_GUARD_KEYS
    if extra:
        errors.append(f"openCodeGoQuotaGuard has unexpected properties: {sorted(extra)}")
    if "enabled" in guard and not isinstance(guard["enabled"], bool):
        errors.append("openCodeGoQuotaGuard.enabled must be a boolean")
    for k in ("fiveHourMaxPct", "weeklyMaxPct"):
        if k in guard and not _is_pct(guard[k]):
            errors.append(f"openCodeGoQuotaGuard.{k} must be a number in (0, 100]")
    ref = guard.get("highVolumeSubagentDefault")
    if "highVolumeSubagentDefault" in guard and not (isinstance(ref, str) and re.fullmatch(r"[^/\s]+/[^\s]+", ref)):
        errors.append("openCodeGoQuotaGuard.highVolumeSubagentDefault must be a 'provider/model' id")
    return errors


def _pct_from(raw):
    """A usage figure from env text or JSON: a number in [0, 100], else None (unusable, never guessed)."""
    try:
        v = float(raw)
    except (TypeError, ValueError):
        return None
    return v if 0 <= v <= 100 and v == v else None


def load_quota_usage(environ=None, home=None) -> dict:
    environ = os.environ if environ is None else environ
    five = _pct_from(environ.get("OPENCODE_GO_USAGE_5H_PCT"))
    week = _pct_from(environ.get("OPENCODE_GO_USAGE_WEEK_PCT"))
    if five is None and week is None:
        path = os.path.join(home or os.path.expanduser("~"), ".omp", "agent", "quota", "opencode-go.json")
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                five = _pct_from(data.get("fiveHourPct"))
                week = _pct_from(data.get("weeklyPct"))
        except (OSError, ValueError):
            pass
    return {"fiveHourPct": five, "weeklyPct": week}


def evaluate_quota_guard(policy, usage: dict) -> dict:
    """over: True when a known figure reached its limit; None when enabled but nothing usable is known; else False."""
    guard = (policy or {}).get("openCodeGoQuotaGuard") if isinstance(policy, dict) else None
    if not isinstance(guard, dict) or not guard.get("enabled"):
        return {"enabled": False, "over": False, "reasons": []}
    five, week = usage.get("fiveHourPct"), usage.get("weeklyPct")
    reasons = []
    if five is not None and five >= guard["fiveHourMaxPct"]:
        reasons.append(f"5h usage {five:g}% >= {guard['fiveHourMaxPct']:g}%")
    if week is not None and week >= guard["weeklyMaxPct"]:
        reasons.append(f"weekly usage {week:g}% >= {guard['weeklyMaxPct']:g}%")
    over = True if reasons else (None if five is None and week is None else False)
    return {
        "enabled": True,
        "over": over,
        "reasons": reasons,
        "fiveHourPct": five,
        "weeklyPct": week,
        "recommend": guard["highVolumeSubagentDefault"] if over else None,
    }


def validate_config(harness: str, root: str = None) -> tuple[bool, list[str]]:
    errors = []
    if harness not in VALID_HARNESSES:
        errors.append(f"unsupported harness '{harness}': expected one of {VALID_HARNESSES}")

    cfg_path = get_harness_config_path(harness, root)
    if not os.path.isfile(cfg_path):
        return False, [f"File missing: {cfg_path}"]

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return False, [f"Invalid JSON in {cfg_path}: {e}"]

    if not isinstance(data, dict):
        return False, [f"Invalid root object in {cfg_path}"]

    unknown_top = set(data.keys()) - {"$schema", "harness", "default_tier", "tiers", "routingPolicy"}
    if unknown_top:
        errors.append(f"unexpected top-level properties: {sorted(unknown_top)}")
    if "routingPolicy" in data:
        errors.extend(validate_routing_policy(data["routingPolicy"]))

    if data.get("harness") != harness:
        errors.append(f"harness field mismatch: expected '{harness}', got '{data.get('harness')}'")

    default_tier = data.get("default_tier")
    if default_tier not in TIER_NAMES:
        errors.append(f"invalid default_tier: {default_tier}")

    tiers = data.get("tiers")
    if not isinstance(tiers, dict):
        errors.append("missing or invalid 'tiers' object")
        tiers = {}

    unknown_tiers = set(tiers.keys()) - set(TIER_NAMES)
    if unknown_tiers:
        errors.append(f"unexpected tier keys: {sorted(unknown_tiers)}")

    allowed_inherit_keys = {
        "inheritFromParent", "preservePromptCachePrefix", "primary", "fallback", "description", "model", "provider", "effort",
    }
    if "Inherit" in tiers:
        inh = tiers["Inherit"]
        if not isinstance(inh, dict):
            errors.append("tier 'Inherit' must be an object")
        else:
            extra_inh = set(inh.keys()) - allowed_inherit_keys
            if extra_inh:
                errors.append(f"tier 'Inherit' has unexpected properties: {sorted(extra_inh)}")
            for bkey in ("inheritFromParent", "preservePromptCachePrefix"):
                if bkey in inh and not isinstance(inh[bkey], bool):
                    errors.append(f"tier 'Inherit' {bkey} must be a boolean")

    allowed_tier_keys = {
        "model", "provider", "effort", "max_context_tokens",
        "compaction_threshold", "description", "fallbacks", "candidates", "sub_routes",
    }
    allowed_fb_keys = {
        "model", "provider", "effort", "max_context_tokens",
        "compaction_threshold", "trigger", "description",
    }
    allowed_cand_keys = {
        "model", "provider", "effort", "max_context_tokens",
        "compaction_threshold", "priority", "strategy", "description",
    }
    allowed_sr_keys = {
        "model", "provider", "effort", "max_context_tokens",
        "compaction_threshold", "description",
    }

    for rt in REQUIRED_TIERS:
        if rt not in tiers:
            errors.append(f"missing required tier: {rt}")
            continue
        t = tiers[rt]
        if not isinstance(t, dict):
            errors.append(f"tier '{rt}' must be an object")
            continue
        extra_t = set(t.keys()) - allowed_tier_keys
        if extra_t:
            errors.append(f"tier '{rt}' has unexpected properties: {sorted(extra_t)}")
        if not t.get("model"):
            errors.append(f"tier '{rt}' missing 'model' field")
        effort = t.get("effort")
        if effort is not None and effort not in VALID_EFFORTS:
            errors.append(f"tier '{rt}' has invalid effort: {effort}")
        _validate_compaction_bounds(t, f"tier '{rt}'", errors)

        for idx, fb in enumerate(t.get("fallbacks") or []):
            if not isinstance(fb, dict):
                errors.append(f"tier '{rt}' fallback[{idx}] must be an object")
                continue
            extra_fb = set(fb.keys()) - allowed_fb_keys
            if extra_fb:
                errors.append(f"tier '{rt}' fallback[{idx}] has unexpected properties: {sorted(extra_fb)}")
            if not fb.get("model"):
                errors.append(f"tier '{rt}' fallback[{idx}] missing 'model' field")
            if fb.get("effort") is not None and fb.get("effort") not in VALID_EFFORTS:
                errors.append(f"tier '{rt}' fallback[{idx}] has invalid effort: {fb.get('effort')}")
            if fb.get("trigger") is not None and fb.get("trigger") not in VALID_TRIGGERS:
                errors.append(f"tier '{rt}' fallback[{idx}] has invalid trigger: {fb.get('trigger')}")
            _validate_compaction_bounds(fb, f"tier '{rt}' fallback[{idx}]", errors)

        for idx, cand in enumerate(t.get("candidates") or []):
            if not isinstance(cand, dict):
                errors.append(f"tier '{rt}' candidates[{idx}] must be an object")
                continue
            extra_c = set(cand.keys()) - allowed_cand_keys
            if extra_c:
                errors.append(f"tier '{rt}' candidates[{idx}] has unexpected properties: {sorted(extra_c)}")
            if not cand.get("model"):
                errors.append(f"tier '{rt}' candidates[{idx}] missing 'model' field")
            if cand.get("effort") is not None and cand.get("effort") not in VALID_EFFORTS:
                errors.append(f"tier '{rt}' candidates[{idx}] has invalid effort: {cand.get('effort')}")
            _validate_compaction_bounds(cand, f"tier '{rt}' candidates[{idx}]", errors)

        for sr, srd in (t.get("sub_routes") or {}).items():
            if not isinstance(srd, dict):
                errors.append(f"tier '{rt}' sub_route '{sr}' must be an object")
                continue
            extra_sr = set(srd.keys()) - allowed_sr_keys
            if extra_sr:
                errors.append(f"tier '{rt}' sub_route '{sr}' has unexpected properties: {sorted(extra_sr)}")
            if not srd.get("model"):
                errors.append(f"tier '{rt}' sub_route '{sr}' missing 'model' field")
            if srd.get("effort") is not None and srd.get("effort") not in VALID_EFFORTS:
                errors.append(f"tier '{rt}' sub_route '{sr}' has invalid effort: {srd.get('effort')}")
            _validate_compaction_bounds(srd, f"tier '{rt}' sub_route '{sr}'", errors)

    # Cross-check referenced models against the harness's models.yml (OMP) or
    # models.json catalog. Bare native aliases (no "/") and built-in providers not
    # listed in the custom catalog (e.g., anthropic, openai, antigravity-cli) are
    # skipped unless defined in the catalog.
    harness_dir = os.path.dirname(cfg_path)
    catalog_name, mdata = _load_catalog(harness_dir, harness, errors)
    provider_models = {}
    if mdata:
        providers_map = mdata.get("providers") or {}
        if not isinstance(providers_map, dict):
            errors.append(f"{catalog_name} 'providers' must be an object/mapping")
            providers_map = {}

        provider_models = {
            prov: {m.get("id") for m in (pdata.get("models") or []) if isinstance(m, dict)}
            for prov, pdata in providers_map.items()
            if isinstance(pdata, dict)
        }

        for prov, pdata in providers_map.items():
            if not isinstance(pdata, dict):
                continue
            seen = set()
            for m in pdata.get("models") or []:
                if not isinstance(m, dict):
                    continue
                mid = m.get("id")
                if mid in seen:
                    errors.append(f"{catalog_name} provider '{prov}' has duplicate model id '{mid}'")
                seen.add(mid)
                cw, mt = m.get("contextWindow"), m.get("maxTokens")
                if isinstance(cw, int) and isinstance(mt, int) and mt > cw:
                    errors.append(
                        f"{catalog_name} '{prov}/{mid}': maxTokens {mt} exceeds contextWindow {cw}"
                    )

        def check_ref(ref, where):
            if not ref or "/" not in ref:
                return
            prov, _, mid = ref.partition("/")
            if prov in provider_models and mid not in provider_models[prov]:
                errors.append(
                    f"{where} references undefined model '{ref}' "
                    f"(provider '{prov}' has no id '{mid}' in {catalog_name})"
                )

        for tname, t in tiers.items():
            if not isinstance(t, dict):
                continue
            check_ref(t.get("model"), f"tier '{tname}'")
            for fb in t.get("fallbacks") or []:
                if isinstance(fb, dict):
                    check_ref(fb.get("model"), f"tier '{tname}' fallback ({fb.get('trigger')})")
            for cand in t.get("candidates") or []:
                if isinstance(cand, dict):
                    check_ref(cand.get("model"), f"tier '{tname}' candidate")
            for sr, srd in (t.get("sub_routes") or {}).items():
                if isinstance(srd, dict):
                    check_ref(srd.get("model"), f"tier '{tname}' sub_route '{sr}'")

    # Cross-check OMP config.yml (modelRoles / retry.fallbackChains) if present
    config_yml = os.path.join(harness_dir, "config.yml")
    if os.path.isfile(config_yml):
        if yaml is None:
            errors.append(f"PyYAML is required to validate {config_yml}")
        else:
            try:
                with open(config_yml, "r", encoding="utf-8") as cf:
                    cdata = yaml.safe_load(cf)
                if not isinstance(cdata, dict):
                    errors.append(f"invalid config.yml for '{harness}': top-level must be a mapping")
                elif provider_models:
                    for role, ref in (cdata.get("modelRoles") or {}).items():
                        if isinstance(ref, str) and "/" in ref:
                            clean_ref = _strip_omp_effort(ref)
                            prov, _, mid = clean_ref.partition("/")
                            if prov in provider_models and mid not in provider_models[prov]:
                                errors.append(
                                    f"config.yml modelRoles.{role} references undefined model '{ref}' "
                                    f"(provider '{prov}' has no id '{mid}' in {catalog_name})"
                                )
                    chains = ((cdata.get("retry") or {}).get("fallbackChains") or {})
                    if isinstance(chains, dict):
                        for cname, entries in chains.items():
                            for ref in entries or []:
                                if isinstance(ref, str) and "/" in ref:
                                    clean_ref = _strip_omp_effort(ref)
                                    prov, _, mid = clean_ref.partition("/")
                                    if prov in provider_models and mid not in provider_models[prov]:
                                        errors.append(
                                            f"config.yml retry.fallbackChains.{cname} references undefined model '{ref}' "
                                            f"(provider '{prov}' has no id '{mid}' in {catalog_name})"
                                        )
            except Exception as e:
                errors.append(f"invalid config.yml for '{harness}': {e}")

    return len(errors) == 0, errors

def main():
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)

    if sys.argv[1] == "--check":
        root = find_repo_root()
        target = sys.argv[2] if len(sys.argv) > 2 else "all"
        harnesses = VALID_HARNESSES if target == "all" else [target]
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

    if sys.argv[1] == "--quota-guard":
        harness = sys.argv[2] if len(sys.argv) > 2 else "omp"
        if harness not in VALID_HARNESSES:
            print(f"unsupported harness '{harness}': expected one of {VALID_HARNESSES}", file=sys.stderr)
            sys.exit(2)
        try:
            with open(get_harness_config_path(harness, find_repo_root()), "r", encoding="utf-8") as f:
                routing = json.load(f)
        except (OSError, ValueError) as e:
            print(f"cannot read the {harness} model-routing.json: {e}", file=sys.stderr)
            sys.exit(2)
        print(json.dumps(evaluate_quota_guard(routing.get("routingPolicy"), load_quota_usage())))
        sys.exit(0)

    args = sys.argv[1:]
    harness = None
    tier = None
    fmt = "json"
    sub_route = None
    fallback_index = None
    trigger = None

    i = 0
    positional = []
    while i < len(args):
        a = args[i]
        if a == "--harness" and i + 1 < len(args):
            harness = args[i + 1]
            i += 2
        elif a == "--tier" and i + 1 < len(args):
            tier = args[i + 1]
            i += 2
        elif a == "--format" and i + 1 < len(args):
            fmt = args[i + 1]
            i += 2
        elif a == "--sub-route" and i + 1 < len(args):
            sub_route = args[i + 1]
            i += 2
        elif a == "--fallback" and i + 1 < len(args):
            try:
                fallback_index = int(args[i + 1])
            except ValueError:
                pass
            i += 2
        elif a == "--trigger" and i + 1 < len(args):
            trigger = args[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1

    if harness is None and positional:
        if positional[0] in VALID_HARNESSES:
            harness = positional.pop(0)
    if tier is None and positional:
        tier = positional.pop(0)
    harness = harness or "omp"
    tier = tier or "High"

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
