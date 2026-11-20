#!/usr/bin/env python3
"""
update-model-catalog.py — Daily SSoT Model Catalog Updater & Multi-Objective Pareto Optimizer.

Fetches model metadata (pricing, context windows, availability) from public catalogs
(LiteLLM, OpenRouter) and local endpoints (OpenCode Go, Ollama, antigravity-model-catalog.json),
computes tier-specific Pareto-optimal model rankings across (quality, cost_efficiency, speed,
context_window) with cross-family independence between High (Maker) and XHigh (Checker), and
deterministically syncs derived configs across all 4 harnesses (omp, claude, agy, hermes).

Usage:
  update-model-catalog.py --check
  update-model-catalog.py --sync-only [--dry-run]
  update-model-catalog.py [--fetch] [--optimize] [--dry-run] [--report]
"""

import argparse
import copy
import datetime as dt
import json
import math
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

DERIVED_HARNESSES = ("omp", "claude", "agy", "hermes")
REQUIRED_TIERS = ("Low", "Medium", "High", "XHigh", "Max")
BARE_MODEL_HARNESSES = {"claude", "agy"}


def find_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def canonical_catalog_path(root: Path) -> Path:
    return root / "agent" / "models" / "catalog.json"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _dump_json(data: dict) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def _expand_path(p: str) -> Path:
    return Path(os.path.expanduser(p))


def _fetch_json_source(url: str, fixture_env: str, cache_path: Path, timeout: float = 5.0):
    fixture = os.environ.get(fixture_env, "").strip()
    if fixture:
        fp = _expand_path(fixture)
        if fp.is_file():
            return _load_json(fp), f"fixture:{fp}"
        raise FileNotFoundError(f"{fixture_env} points to missing file: {fp}")

    if os.environ.get("MODEL_CATALOG_OFFLINE", "").strip() in ("1", "true", "yes"):
        return None, "offline-skipped"

    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "dotfiles-model-catalog-updater/1.0",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            data = json.loads(raw)
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_text(raw, encoding="utf-8")
            return data, f"live:{url}"
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        if cache_path.is_file():
            try:
                return _load_json(cache_path), f"cache:{cache_path} ({exc})"
            except Exception:
                pass
        return None, f"unavailable:{exc}"


def _infer_family(model_key: str) -> str:
    low = model_key.lower()
    if "claude" in low or low.startswith("anthropic/"):
        return "anthropic"
    if "gemini" in low or "google/" in low:
        return "google"
    if "gpt-" in low or low.startswith("openai/") or "/o3" in low or "/o4" in low:
        return "openai"
    if "deepseek" in low:
        return "deepseek"
    if "qwen" in low:
        return "qwen"
    if "kimi" in low or "moonshot" in low:
        return "moonshot"
    if low.startswith("ollama/") or low.startswith("local/"):
        return "local"
    return model_key.split("/", 1)[0] if "/" in model_key else "unknown"


def _heuristic_scores_from_metadata(model_id: str, ctx: int, inp_1m: float, out_1m: float, reasoning: bool) -> dict:
    low = model_id.lower()
    if any(k in low for k in ("fable", "opus", "astra", "pro", "o3", "o1")):
        base_coding, base_reason, base_speed = 93.0, 95.0, 58.0
    elif any(k in low for k in ("sonnet", "sol", "argon", "max", "coder")):
        base_coding, base_reason, base_speed = 91.0, 89.0, 75.0
    elif any(k in low for k in ("flash", "haiku", "hydrogen", "mini", "nano", "lite")):
        base_coding, base_reason, base_speed = 82.0, 80.0, 93.0
    else:
        base_coding, base_reason, base_speed = 78.0, 76.0, 75.0

    if reasoning:
        base_reason = min(99.0, base_reason + 2.0)
    if out_1m > 20.0:
        base_speed = max(35.0, base_speed - 10.0)
    if ctx >= 1000000:
        base_coding = min(98.0, base_coding + 1.0)
    return {
        "coding": round(base_coding, 2),
        "reasoning": round(base_reason, 2),
        "speed": round(base_speed, 2),
    }


def _match_litellm_entry(model_key: str, meta: dict, litellm_data: dict):
    mid = meta.get("model_id", "")
    prov = meta.get("provider", "")
    candidates = [model_key, mid, f"{prov}/{mid}"]
    if prov == "antigravity-cli":
        candidates.append(f"gemini/{mid}")
    for key in candidates:
        if key in litellm_data and isinstance(litellm_data[key], dict):
            return litellm_data[key]
    return None


def _ensure_omp_provider_model(catalog: dict, provider: str, model_id: str, name: str, ctx: int, max_out: int, reasoning: bool):
    omp_providers = catalog.setdefault("omp_providers", {})
    if provider not in omp_providers:
        return
    models = omp_providers[provider].setdefault("models", [])
    existing = next((m for m in models if m.get("id") == model_id), None)
    safe_ctx = max(int(ctx or 65536), 4096)
    safe_out = min(int(max_out or 8192), safe_ctx)
    if existing is None:
        entry = {
            "id": model_id,
            "name": name,
            "contextWindow": safe_ctx,
            "maxTokens": safe_out,
        }
        if reasoning:
            entry["reasoning"] = True
        models.append(entry)
    else:
        existing["contextWindow"] = max(int(existing.get("contextWindow", 0)), safe_ctx)
        existing["maxTokens"] = min(max(int(existing.get("maxTokens", 0)), safe_out), existing["contextWindow"])


def fetch_and_merge(catalog: dict, timeout: float = 5.0) -> list[str]:
    notes = []
    sources = catalog.get("update_sources") or {}
    cache_dir = _expand_path(sources.get("cache_dir", "~/.cache/omp/model-catalog"))
    models = catalog.setdefault("models", {})

    # 1. LiteLLM model prices and context windows
    litellm_data, litellm_src = _fetch_json_source(
        sources.get("litellm_url", ""),
        "MODEL_CATALOG_LITELLM_FIXTURE",
        cache_dir / "litellm_prices.json",
        timeout=timeout,
    )
    notes.append(f"litellm: {litellm_src}")
    if isinstance(litellm_data, dict):
        for full_id, meta in models.items():
            entry = _match_litellm_entry(full_id, meta, litellm_data)
            if not entry:
                continue
            inp_tok = entry.get("input_cost_per_token")
            out_tok = entry.get("output_cost_per_token")
            if isinstance(inp_tok, (int, float)) and isinstance(out_tok, (int, float)):
                meta.setdefault("pricing", {})
                meta["pricing"]["input_per_1m"] = round(inp_tok * 1_000_000, 4)
                meta["pricing"]["output_per_1m"] = round(out_tok * 1_000_000, 4)
                cr = entry.get("cache_read_input_token_cost")
                cw = entry.get("cache_creation_input_token_cost")
                if isinstance(cr, (int, float)):
                    meta["pricing"]["cache_read_per_1m"] = round(cr * 1_000_000, 4)
                if isinstance(cw, (int, float)):
                    meta["pricing"]["cache_write_per_1m"] = round(cw * 1_000_000, 4)
            max_in = entry.get("max_input_tokens") or entry.get("max_tokens")
            if isinstance(max_in, int) and max_in > 0:
                meta["context_window"] = max(meta.get("context_window", 0), max_in)

        # Ingest explicit catalog candidate additions from LiteLLM (direct Anthropic/OpenAI candidates)
        for key, entry in litellm_data.items():
            if not isinstance(entry, dict) or key in ("sample_spec",):
                continue
            prov = key.split("/", 1)[0] if "/" in key else ""
            if prov not in ("anthropic", "openai") or "/" not in key:
                continue
            if key in models:
                continue
            mid = key.split("/", 1)[1]
            inp_1m = round((entry.get("input_cost_per_token") or 0.0) * 1_000_000, 4)
            out_1m = round((entry.get("output_cost_per_token") or 0.0) * 1_000_000, 4)
            ctx = int(entry.get("max_input_tokens") or entry.get("max_tokens") or 200000)
            max_out = int(entry.get("max_output_tokens") or 32768)
            scores = entry.get("scores") if isinstance(entry.get("scores"), dict) else _heuristic_scores_from_metadata(mid, ctx, inp_1m, out_1m, bool(entry.get("supports_reasoning", True)))
            elig = entry.get("eligible_tiers") if isinstance(entry.get("eligible_tiers"), list) else (
                ["Low", "Medium"] if out_1m <= 5.5 else ["High", "XHigh"] if out_1m <= 20.0 else ["XHigh", "Max"]
            )
            models[key] = {
                "provider": prov,
                "model_id": mid,
                "family": _infer_family(key),
                "display_name": entry.get("display_name") or mid,
                "harness_support": entry.get("harness_support") or (["omp", "claude", "agy", "hermes"] if prov == "anthropic" else ["omp", "agy", "hermes"]),
                "eligible_tiers": elig,
                "reasoning": bool(entry.get("supports_reasoning", True)),
                "context_window": ctx,
                "max_output_tokens": min(max_out, ctx),
                "compaction_threshold": 250000 if prov == "openai" else (90000 if "haiku" in mid else None),
                "pricing": {
                    "input_per_1m": inp_1m,
                    "output_per_1m": out_1m,
                    "cache_read_per_1m": round((entry.get("cache_read_input_token_cost") or 0.0) * 1_000_000, 4),
                    "cache_write_per_1m": round((entry.get("cache_creation_input_token_cost") or 0.0) * 1_000_000, 4),
                    "subscription_included": False,
                },
                "scores": scores,
                "status": "candidate",
                "source": "litellm",
            }
            notes.append(f"litellm: discovered candidate {key}")

    # 2. OpenRouter /api/v1/models
    or_data, or_src = _fetch_json_source(
        sources.get("openrouter_url", ""),
        "MODEL_CATALOG_OPENROUTER_FIXTURE",
        cache_dir / "openrouter_models.json",
        timeout=timeout,
    )
    notes.append(f"openrouter: {or_src}")
    if isinstance(or_data, dict) and isinstance(or_data.get("data"), list):
        by_tail = {k.split("/", 1)[-1]: v for k, v in models.items()}
        for item in or_data["data"]:
            if not isinstance(item, dict):
                continue
            oid = str(item.get("id", ""))
            tail = oid.split("/", 1)[-1]
            target = models.get(oid) or by_tail.get(tail)
            if not target:
                continue
            ctx = item.get("context_length")
            if isinstance(ctx, int) and ctx > 0:
                target["context_window"] = max(target.get("context_window", 0), ctx)
            pricing = item.get("pricing") or {}
            try:
                p_in = float(pricing.get("prompt", 0)) * 1_000_000
                p_out = float(pricing.get("completion", 0)) * 1_000_000
                if p_in > 0 or p_out > 0:
                    target.setdefault("pricing", {})
                    target["pricing"]["input_per_1m"] = round(p_in, 4)
                    target["pricing"]["output_per_1m"] = round(p_out, 4)
            except (TypeError, ValueError):
                pass
            if isinstance(item.get("scores"), dict):
                target["scores"] = {
                    "coding": float(item["scores"].get("coding", target["scores"]["coding"])),
                    "reasoning": float(item["scores"].get("reasoning", target["scores"]["reasoning"])),
                    "speed": float(item["scores"].get("speed", target["scores"]["speed"])),
                }

    # 3. OpenCode Go /v1/models (OpenAI-compatible endpoint)
    og_data, og_src = _fetch_json_source(
        sources.get("opencode_go_models_url", ""),
        "MODEL_CATALOG_OPENCODE_GO_FIXTURE",
        cache_dir / "opencode_go_models.json",
        timeout=timeout,
    )
    notes.append(f"opencode-go: {og_src}")
    if isinstance(og_data, dict) and isinstance(og_data.get("data"), list):
        for item in og_data["data"]:
            if not isinstance(item, dict) or not item.get("id"):
                continue
            mid = str(item["id"])
            full_id = mid if mid.startswith("opencode-go/") else f"opencode-go/{mid}"
            raw_mid = full_id.split("/", 1)[1]
            ctx = int(item.get("context_length") or item.get("contextWindow") or 131072)
            max_out = int(item.get("max_output_tokens") or item.get("maxTokens") or 16384)
            reasoning = bool(item.get("reasoning", True))
            if full_id not in models:
                scores = item.get("scores") if isinstance(item.get("scores"), dict) else _heuristic_scores_from_metadata(raw_mid, ctx, 0.0, 0.0, reasoning)
                elig = item.get("eligible_tiers") if isinstance(item.get("eligible_tiers"), list) else (
                    ["Low", "Medium"] if "flash" in raw_mid else ["Medium", "High", "XHigh"]
                )
                models[full_id] = {
                    "provider": "opencode-go",
                    "model_id": raw_mid,
                    "family": _infer_family(full_id),
                    "display_name": item.get("name") or f"{raw_mid} (OpenCode Go)",
                    "harness_support": ["omp", "hermes"],
                    "eligible_tiers": elig,
                    "reasoning": reasoning,
                    "context_window": ctx,
                    "max_output_tokens": min(max_out, ctx),
                    "compaction_threshold": None,
                    "pricing": {
                        "input_per_1m": float((item.get("pricing") or {}).get("input_per_1m", 0.0)),
                        "output_per_1m": float((item.get("pricing") or {}).get("output_per_1m", 0.0)),
                        "cache_read_per_1m": 0.0,
                        "cache_write_per_1m": 0.0,
                        "subscription_included": True,
                    },
                    "scores": scores,
                    "status": "candidate",
                    "source": "opencode-go",
                }
                notes.append(f"opencode-go: discovered candidate {full_id}")
            else:
                if isinstance(item.get("scores"), dict):
                    models[full_id]["scores"].update(item["scores"])
            _ensure_omp_provider_model(catalog, "opencode-go", raw_mid, models[full_id]["display_name"], ctx, max_out, reasoning)

    # 4. Local Ollama /api/tags
    ol_data, ol_src = _fetch_json_source(
        sources.get("ollama_tags_url", ""),
        "MODEL_CATALOG_OLLAMA_FIXTURE",
        cache_dir / "ollama_tags.json",
        timeout=min(timeout, 2.0),
    )
    notes.append(f"ollama: {ol_src}")
    if isinstance(ol_data, dict) and isinstance(ol_data.get("models"), list):
        for item in ol_data["models"]:
            if not isinstance(item, dict) or not item.get("name"):
                continue
            mid = str(item["name"])
            full_id = f"ollama/{mid}"
            ctx = int(item.get("contextWindow") or 65536)
            max_out = int(item.get("maxTokens") or 8192)
            if full_id not in models:
                models[full_id] = {
                    "provider": "ollama",
                    "model_id": mid,
                    "family": "local",
                    "display_name": f"{mid} (Local Ollama)",
                    "harness_support": ["omp", "hermes"],
                    "eligible_tiers": ["Low", "Medium"] if "coder" in mid else ["Low"],
                    "local_fallback_only": True,
                    "reasoning": False,
                    "context_window": ctx,
                    "max_output_tokens": min(max_out, ctx),
                    "compaction_threshold": None,
                    "pricing": {
                        "input_per_1m": 0.0,
                        "output_per_1m": 0.0,
                        "cache_read_per_1m": 0.0,
                        "cache_write_per_1m": 0.0,
                        "subscription_included": True,
                    },
                    "scores": _heuristic_scores_from_metadata(mid, ctx, 0.0, 0.0, False),
                    "status": "candidate",
                    "source": "ollama",
                }
                notes.append(f"ollama: discovered local {full_id}")
            _ensure_omp_provider_model(catalog, "ollama", mid, models[full_id]["display_name"], ctx, max_out, False)

    # 5. Local antigravity-model-catalog.json
    ag_fixture = os.environ.get("MODEL_CATALOG_ANTIGRAVITY_FIXTURE", "").strip()
    ag_candidates = [_expand_path(ag_fixture)] if ag_fixture else [
        _expand_path(p) for p in sources.get("local_catalog_paths", [])
    ]
    ag_loaded = None
    for agp in ag_candidates:
        if agp.is_file():
            try:
                ag_loaded = (_load_json(agp), agp)
                break
            except Exception as exc:
                notes.append(f"antigravity-local: error reading {agp}: {exc}")
    if ag_loaded:
        ag_data, agp = ag_loaded
        notes.append(f"antigravity-local: {agp}")
        for item in ag_data.get("models") or []:
            if not isinstance(item, dict) or not item.get("id"):
                continue
            mid = str(item["id"])
            full_id = f"antigravity-cli/{mid}"
            cost = item.get("cost") or {}
            ctx = int(item.get("contextWindow") or 1048576)
            max_out = int(item.get("maxTokens") or 65536)
            inp_1m = float(cost.get("input", 0.0))
            out_1m = float(cost.get("output", 0.0))
            if full_id in models:
                models[full_id]["context_window"] = max(models[full_id].get("context_window", 0), ctx)
                models[full_id]["max_output_tokens"] = max(models[full_id].get("max_output_tokens", 0), max_out)
                models[full_id].setdefault("pricing", {}).update({
                    "input_per_1m": inp_1m,
                    "output_per_1m": out_1m,
                    "cache_read_per_1m": float(cost.get("cacheRead", 0.0)),
                    "cache_write_per_1m": float(cost.get("cacheWrite", 0.0)),
                })
            elif isinstance(item.get("scores"), dict):
                models[full_id] = {
                    "provider": "antigravity-cli",
                    "model_id": mid,
                    "family": _infer_family(full_id),
                    "display_name": item.get("name") or mid,
                    "harness_support": ["omp", "agy", "hermes"],
                    "eligible_tiers": item.get("eligible_tiers") or (["Low", "Medium"] if out_1m <= 1.0 else ["High", "XHigh", "Max"]),
                    "reasoning": bool(item.get("reasoning", True)),
                    "context_window": ctx,
                    "max_output_tokens": min(max_out, ctx),
                    "compaction_threshold": None,
                    "pricing": {
                        "input_per_1m": inp_1m,
                        "output_per_1m": out_1m,
                        "cache_read_per_1m": float(cost.get("cacheRead", 0.0)),
                        "cache_write_per_1m": float(cost.get("cacheWrite", 0.0)),
                        "subscription_included": True,
                    },
                    "scores": item["scores"],
                    "status": "candidate",
                    "source": "antigravity-local",
                }
                notes.append(f"antigravity-local: discovered {full_id}")
    else:
        notes.append("antigravity-local: not found")

    return notes


def _compute_metrics(meta: dict) -> dict:
    scores = meta.get("scores") or {}
    coding = max(0.0, min(100.0, float(scores.get("coding", 50.0)))) / 100.0
    reasoning = max(0.0, min(100.0, float(scores.get("reasoning", 50.0)))) / 100.0
    speed = max(0.0, min(100.0, float(scores.get("speed", 50.0)))) / 100.0
    ctx = max(32768, int(meta.get("context_window") or 32768))
    ctx_norm = (math.log2(min(ctx, 1048576)) - math.log2(32768)) / (math.log2(1048576) - math.log2(32768))
    ctx_norm = max(0.0, min(1.0, ctx_norm))

    pricing = meta.get("pricing") or {}
    blended = (float(pricing.get("input_per_1m", 1.0)) + 3.0 * float(pricing.get("output_per_1m", 3.0))) / 4.0
    if meta.get("provider") == "opencode-go":
        eff_cost = 0.0
    else:
        eff_cost = blended
    cost_eff = 1.0 / (1.0 + eff_cost)

    return {
        "quality_coding": coding,
        "quality_reasoning": reasoning,
        "cost_efficiency": cost_eff,
        "speed": speed,
        "context_score": ctx_norm,
    }


def _pareto_nondominated(scored_items: list[dict]) -> set[str]:
    objs = ("quality_coding", "quality_reasoning", "cost_efficiency", "speed", "context_score")
    nondom = set()
    for a in scored_items:
        ma = a["metrics"]
        dominated = False
        for b in scored_items:
            if a["full_id"] == b["full_id"]:
                continue
            mb = b["metrics"]
            if all(mb[k] >= ma[k] for k in objs) and any(mb[k] > ma[k] for k in objs):
                dominated = True
                break
        if not dominated:
            nondom.add(a["full_id"])
    return nondom


def _resolve_model_meta_key(models: dict, ref: str, harness: str) -> str | None:
    if not ref:
        return None
    if ref in models:
        return ref
    for full_id, meta in models.items():
        if meta.get("model_id") == ref and harness in (meta.get("harness_support") or []):
            # Prefer direct provider match for bare claude/agy model refs
            if harness == "claude" and meta.get("provider") == "anthropic":
                return full_id
            if harness == "agy" and meta.get("provider") in ("antigravity-cli", "anthropic", "openai"):
                return full_id
    for full_id, meta in models.items():
        if meta.get("model_id") == ref:
            return full_id
    return None


def optimize_catalog(catalog: dict) -> list[dict]:
    profiles = catalog.get("tier_optimization_profiles") or {}
    models = catalog.get("models") or {}
    native_bonuses = catalog.get("harness_native_bonuses") or {}
    hysteresis = float((catalog.get("update_sources") or {}).get("hysteresis_margin", 0.02))
    report_rows = []

    for harness in DERIVED_HARNESSES:
        hcfg = catalog["harnesses"][harness]
        tiers = hcfg["tiers"]
        selected_families = {}
        h_bonuses = native_bonuses.get(harness) or {}

        for tier in REQUIRED_TIERS:
            tcfg = tiers[tier]
            prof = profiles.get(tier) or {}
            weights = prof.get("weights") or {}
            min_ctx = int(prof.get("min_context_tokens") or 0)
            cross_from = prof.get("cross_family_from_tier")
            blocked_family = selected_families.get(cross_from) if cross_from else None

            current_ref = tcfg.get("model", "")
            current_key = _resolve_model_meta_key(models, current_ref, harness)

            # Collect pre-cross-family eligible pool to verify multiple families exist
            pre_pool = []
            for full_id, meta in models.items():
                if meta.get("status") == "deprecated":
                    continue
                if meta.get("auxiliary_role_only") or meta.get("local_fallback_only"):
                    continue
                if harness not in (meta.get("harness_support") or []):
                    continue
                if tier not in (meta.get("eligible_tiers") or []):
                    continue
                if int(meta.get("context_window") or 0) < min_ctx:
                    continue
                # For harnesses with multiple mirrors of identical model_id (e.g., antigravity-cli/claude-sonnet-5-5),
                # prefer direct provider unless direct isn't listed.
                if harness == "omp" and meta.get("provider") == "antigravity-cli" and f"anthropic/{meta.get('model_id')}" in models:
                    continue
                pre_pool.append((full_id, meta))

            non_blocked_families = {m.get("family") for _, m in pre_pool if m.get("family") != blocked_family}
            enforce_cross = bool(blocked_family and non_blocked_families)

            # Build final eligible pool for this harness + tier
            eligible = []
            for full_id, meta in pre_pool:
                if enforce_cross and meta.get("family") == blocked_family:
                    continue
                metrics = _compute_metrics(meta)
                bonus = float(h_bonuses.get(meta.get("provider"), 0.0))
                score = sum(float(weights.get(k, 0.0)) * metrics[k] for k in metrics) + bonus
                eligible.append({
                    "full_id": full_id,
                    "meta": meta,
                    "metrics": metrics,
                    "score": round(score, 6),
                })

            if not eligible:
                if current_key and current_key in models:
                    selected_families[tier] = models[current_key].get("family")
                report_rows.append({
                    "harness": harness,
                    "tier": tier,
                    "current": current_ref,
                    "winner": current_ref,
                    "action": "keep-no-candidates",
                    "current_score": None,
                    "winner_score": None,
                    "pareto_frontier": [],
                })
                continue

            frontier_ids = _pareto_nondominated(eligible)
            for item in eligible:
                item["pareto"] = item["full_id"] in frontier_ids

            # Prefer Pareto frontier candidates, sorted descending by composite score
            ranked = sorted(
                eligible,
                key=lambda x: (1 if x["pareto"] else 0, x["score"]),
                reverse=True,
            )
            winner = ranked[0]

            current_entry = next((x for x in eligible if x["full_id"] == current_key), None)
            if current_entry is None and current_key in models and models[current_key].get("status") != "deprecated":
                # Baseline model outside normalized pool (e.g. opusplan hybrid): score it directly
                cur_meta = models[current_key]
                cur_m = _compute_metrics(cur_meta)
                cur_bonus = float(h_bonuses.get(cur_meta.get("provider"), 0.0))
                cur_score = round(sum(float(weights.get(k, 0.0)) * cur_m[k] for k in cur_m) + cur_bonus, 6)
            else:
                cur_score = current_entry["score"] if current_entry else 0.0

            current_is_hybrid_claude = (harness == "claude" and tier == "Medium" and current_ref == "opusplan")
            should_switch = (
                not current_is_hybrid_claude
                and winner["full_id"] != current_key
                and (current_entry is None or winner["score"] >= cur_score + hysteresis)
            )

            if should_switch:
                wmeta = winner["meta"]
                new_model_ref = wmeta["model_id"] if harness in BARE_MODEL_HARNESSES else winner["full_id"]
                old_model_ref = tcfg["model"]

                # Demote previous primary to top fallback if not already present and valid
                fbs = list(tcfg.get("fallbacks") or [])
                if old_model_ref and old_model_ref != new_model_ref and not any(fb.get("model") == old_model_ref for fb in fbs):
                    prev_fb = {
                        "model": old_model_ref,
                        "effort": tcfg.get("effort", prof.get("effort", "high")),
                        "trigger": "rate_limit",
                        "description": f"Previous baseline {old_model_ref} fallback after catalog upgrade to {new_model_ref}",
                    }
                    if harness not in BARE_MODEL_HARNESSES and "/" in old_model_ref:
                        prev_fb["provider"] = old_model_ref.split("/", 1)[0]
                    if current_key and models.get(current_key, {}).get("compaction_threshold"):
                        prev_fb["compaction_threshold"] = models[current_key]["compaction_threshold"]
                    fbs.insert(0, prev_fb)
                # Ensure winner is not duplicated in its own fallbacks
                tcfg["fallbacks"] = [fb for fb in fbs if fb.get("model") != new_model_ref]

                tcfg["model"] = new_model_ref
                if harness not in BARE_MODEL_HARNESSES:
                    tcfg["provider"] = wmeta["provider"]
                if wmeta.get("compaction_threshold"):
                    tcfg["compaction_threshold"] = wmeta["compaction_threshold"]
                else:
                    tcfg.pop("compaction_threshold", None)
                if wmeta.get("provider") == "opencode-go" and wmeta.get("context_window"):
                    tcfg["max_context_tokens"] = wmeta["context_window"]
                tcfg["description"] = f"{wmeta.get('display_name', new_model_ref)} ({tier}) — Pareto-selected (score={winner['score']:.3f})"
                if harness in ("omp", "hermes") and tier == "Low" and isinstance(tcfg.get("sub_routes"), dict):
                    cr = tcfg["sub_routes"].get("code_research")
                    if isinstance(cr, dict):
                        cr["provider"] = wmeta["provider"]
                        cr["model"] = new_model_ref
                        cr["max_context_tokens"] = wmeta.get("context_window", 131072)

                wmeta["status"] = "active"
                selected_families[tier] = wmeta.get("family")
                action = "switch"
                chosen_ref = new_model_ref
                chosen_score = winner["score"]
            else:
                if current_key and current_key in models:
                    selected_families[tier] = models[current_key].get("family")
                elif blocked_family and current_key and models.get(current_key, {}).get("family") == blocked_family:
                    selected_families[tier] = blocked_family
                action = "keep"
                chosen_ref = current_ref
                chosen_score = cur_score

            # Ensure provider models for omp are registered in omp_providers
            if harness == "omp":
                target_id = _resolve_model_meta_key(models, tcfg["model"], "omp")
                if target_id and target_id in models:
                    tm = models[target_id]
                    _ensure_omp_provider_model(
                        catalog,
                        tm["provider"],
                        tm["model_id"],
                        tm.get("display_name", tm["model_id"]),
                        int(tm.get("context_window", 131072)),
                        int(tm.get("max_output_tokens", 16384)),
                        bool(tm.get("reasoning", True)),
                    )

            report_rows.append({
                "harness": harness,
                "tier": tier,
                "current": current_ref,
                "winner": chosen_ref,
                "action": action,
                "current_score": cur_score,
                "winner_score": chosen_score,
                "pareto_frontier": [
                    {"model": x["full_id"], "score": x["score"], "family": x["meta"].get("family")}
                    for x in ranked if x["pareto"]
                ][:4],
            })

    # Sync OMP config roles & sol_pi from optimized omp tiers
    omp_tiers = catalog["harnesses"]["omp"]["tiers"]
    omp_cfg = catalog.setdefault("omp_config", {})
    roles = omp_cfg.setdefault("modelRoles", {})
    roles["fast"] = f"{omp_tiers['Low']['model']}:low"
    roles["smol"] = f"{omp_tiers['Low']['model']}:medium"
    roles["good"] = f"{omp_tiers['High']['model']}:{omp_tiers['High'].get('effort', 'high')}"
    roles["review"] = f"{omp_tiers['XHigh']['model']}:{omp_tiers['XHigh'].get('effort', 'xhigh')}"

    chains = omp_cfg.setdefault("retry_fallbackChains", {})
    if isinstance(chains.get("default"), list) and chains["default"]:
        chains["default"][0] = roles["good"]

    low_prov = omp_tiers["Low"].get("provider") or omp_tiers["Low"]["model"].split("/", 1)[0]
    low_mid = omp_tiers["Low"]["model"].split("/", 1)[-1]
    omp_cfg["sol_pi"] = {
        "evidencePreservingReducerProvider": low_prov,
        "evidencePreservingReducerModel": low_mid,
    }

    # Sync consensus_models cross-family picks from High / XHigh only if any picked ID changed
    omp_high = omp_tiers["High"]["model"]
    omp_xhigh = omp_tiers["XHigh"]["model"]
    agy_xhigh_mid = catalog["harnesses"]["agy"]["tiers"]["XHigh"]["model"]
    agy_xhigh = agy_xhigh_mid if "/" in agy_xhigh_mid else f"antigravity-cli/{agy_xhigh_mid}"
    desired_ids = [(omp_high, "High"), (agy_xhigh, "XHigh"), (omp_xhigh, "XHigh")]
    existing_consensus = catalog.get("consensus_models") or []
    existing_ids = [c.get("id") for c in existing_consensus if isinstance(c, dict)]
    target_ids = []
    seen_c = set()
    for mid, tier_tag in desired_ids:
        if mid not in seen_c:
            seen_c.add(mid)
            target_ids.append((mid, tier_tag))
    if existing_ids != [m for m, _ in target_ids]:
        existing_labels = {c.get("id"): c.get("label") for c in existing_consensus if isinstance(c, dict)}
        catalog["consensus_models"] = [
            {
                "id": mid,
                "label": existing_labels.get(mid) or (models.get(mid) or {}).get("display_name") or mid,
                "tier": tier_tag,
            }
            for mid, tier_tag in target_ids
        ]

    return report_rows


def render_model_routing(harness: str, catalog: dict) -> str:
    hcfg = catalog["harnesses"][harness]
    payload = {
        "$schema": "../../models/schema.json",
        "harness": harness,
        "default_tier": hcfg["default_tier"],
        "tiers": hcfg["tiers"],
    }
    # Optional cross-tier policy (schema.json RoutingPolicy); passed through verbatim, advisory only.
    if catalog.get("routing_policy"):
        payload["routingPolicy"] = catalog["routing_policy"]
    return _dump_json(payload)


def _yaml_dump(data: dict) -> str:
    class _IndentDumper(yaml.SafeDumper):
        def increase_indent(self, flow=False, indentless=False):
            return super().increase_indent(flow=flow, indentless=False)

    return yaml.dump(
        data,
        Dumper=_IndentDumper,
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
        width=120,
    )


def render_omp_models_yml(existing_text: str, catalog: dict) -> str:
    if yaml is None:
        raise RuntimeError("PyYAML is required to render agent/harnesses/omp/models.yml")
    providers = catalog.get("omp_providers") or {}
    if existing_text:
        try:
            parsed = yaml.safe_load(existing_text)
            if isinstance(parsed, dict) and parsed.get("providers") == providers:
                return existing_text
        except Exception:
            pass
    body = _yaml_dump({"providers": providers})
    cleaned_lines = [line.rstrip() for line in body.splitlines()]
    return (
        "# ~/.omp/agent/models.yml (Canonical SSoT in agent/harnesses/omp/models.yml)\n"
        + "\n".join(cleaned_lines)
        + "\n"
    )


OMP_LEAN_PROFILE_YML = """
# Lean Engineering Profile (Wayland/Sway; SoT also in update-model-catalog.py OMP_LEAN_PROFILE_YML)
tui:
  renderEmbeds: false

todo:
  enabled: true

memory:
  enabled: true

commit:
  enabled: true

disassembler:
  enabled: false

tools:
  disabled:
    - tts
    - generate_image
    - computer
"""


def render_omp_config_yml(existing_text: str, catalog: dict) -> str:
    if yaml is None:
        raise RuntimeError("PyYAML is required to render agent/harnesses/omp/config.yml")
    omp_cfg = catalog.get("omp_config") or {}
    roles = omp_cfg.get("modelRoles") or {}
    chains = omp_cfg.get("retry_fallbackChains") or {}

    roles_block = _yaml_dump({"modelRoles": roles}).rstrip()
    chains_dumped = _yaml_dump({"fallbackChains": chains}).rstrip()
    chains_block = "\n".join("  " + line if line else "" for line in chains_dumped.splitlines())

    out = re.sub(
        r"^modelRoles:\n(?:[ \t]+.*\n?)*",
        roles_block + "\n",
        existing_text,
        count=1,
        flags=re.MULTILINE,
    )
    out = re.sub(
        r"^  fallbackChains:\n(?:[ ]{4,}.*\n?)*",
        chains_block + "\n",
        out,
        count=1,
        flags=re.MULTILINE,
    )
    if "# Lean Engineering Profile" not in out:
        out = out.rstrip("\n") + "\n" + OMP_LEAN_PROFILE_YML
    return "\n".join(line.rstrip() for line in out.splitlines()) + "\n"


def render_sol_pi_json(existing_text: str, catalog: dict) -> str:
    data = json.loads(existing_text)
    sol_cfg = (catalog.get("omp_config") or {}).get("sol_pi") or {}
    if "evidencePreservingReducerProvider" in sol_cfg:
        data["evidencePreservingReducerProvider"] = sol_cfg["evidencePreservingReducerProvider"]
    if "evidencePreservingReducerModel" in sol_cfg:
        data["evidencePreservingReducerModel"] = sol_cfg["evidencePreservingReducerModel"]
    return _dump_json(data)


def build_derived_outputs(root: Path, catalog: dict) -> dict[Path, str]:
    outputs: dict[Path, str] = {}
    for h in DERIVED_HARNESSES:
        outputs[root / "agent" / "harnesses" / h / "model-routing.json"] = render_model_routing(h, catalog)
    models_yml_path = root / "agent" / "harnesses" / "omp" / "models.yml"
    models_yml_existing = models_yml_path.read_text(encoding="utf-8") if models_yml_path.is_file() else ""
    outputs[models_yml_path] = render_omp_models_yml(models_yml_existing, catalog)
    cfg_path = root / "agent" / "harnesses" / "omp" / "config.yml"
    outputs[cfg_path] = render_omp_config_yml(cfg_path.read_text(encoding="utf-8"), catalog)
    sol_path = root / "agent" / "harnesses" / "omp" / "sol-pi.json"
    outputs[sol_path] = render_sol_pi_json(sol_path.read_text(encoding="utf-8"), catalog)
    return outputs


def _validate_written_tree(root: Path) -> tuple[bool, str]:
    for h in DERIVED_HARNESSES:
        json.loads((root / "agent" / "harnesses" / h / "model-routing.json").read_text(encoding="utf-8"))
    json.loads(canonical_catalog_path(root).read_text(encoding="utf-8"))
    json.loads((root / "agent" / "harnesses" / "omp" / "sol-pi.json").read_text(encoding="utf-8"))
    if yaml is not None:
        yaml.safe_load((root / "agent" / "harnesses" / "omp" / "models.yml").read_text(encoding="utf-8"))
        yaml.safe_load((root / "agent" / "harnesses" / "omp" / "config.yml").read_text(encoding="utf-8"))

    resolver = root / "agent" / "scripts" / "resolve-model-tier.py"
    proc = subprocess.run(
        [sys.executable, str(resolver), "--check", "all"],
        cwd=str(root),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return False, proc.stdout + proc.stderr
    return True, proc.stdout.strip()


def apply_with_rollback(root: Path, catalog_path: Path, catalog_text: str, outputs: dict[Path, str]) -> tuple[bool, str]:
    targets = {catalog_path: catalog_text, **outputs}
    backups: dict[Path, str | None] = {
        p: (p.read_text(encoding="utf-8") if p.exists() else None)
        for p in targets
    }
    try:
        for path, content in targets.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        ok, msg = _validate_written_tree(root)
        if not ok:
            raise RuntimeError(f"Validation failed, rolled back all catalog updates:\n{msg}")
        return True, msg
    except Exception as exc:
        for path, orig in backups.items():
            if orig is None:
                path.unlink(missing_ok=True)
            else:
                path.write_text(orig, encoding="utf-8")
        return False, str(exc)


def print_report(fetch_notes: list[str], opt_rows: list[dict]):
    if fetch_notes:
        print("=== Fetch Sources ===")
        for n in fetch_notes:
            print(f"  - {n}")
    if opt_rows:
        print("\n=== Multi-Objective Pareto Tier Evaluation ===")
        for r in opt_rows:
            cur_s = f"{r['current_score']:.3f}" if r["current_score"] is not None else "n/a"
            win_s = f"{r['winner_score']:.3f}" if r["winner_score"] is not None else "n/a"
            print(
                f"  [{r['harness']:6s}] {r['tier']:6s} | {r['action']:6s} | "
                f"{r['current']} ({cur_s}) -> {r['winner']} ({win_s})"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description="Update and sync the multi-harness SSoT model catalog.")
    parser.add_argument("--check", action="store_true", help="Verify catalog.json and derived files are in sync and valid.")
    parser.add_argument("--sync-only", action="store_true", help="Sync derived files from catalog.json without fetching/optimizing.")
    parser.add_argument("--fetch", action="store_true", help="Fetch public/local catalogs and update model metadata.")
    parser.add_argument("--optimize", action="store_true", help="Run Pareto optimization across harness tiers.")
    parser.add_argument("--dry-run", action="store_true", help="Evaluate changes without modifying files.")
    parser.add_argument("--report", action="store_true", help="Print detailed fetch and Pareto scoring report.")
    parser.add_argument("--timeout", type=float, default=5.0, help="HTTP timeout per feed in seconds.")
    args = parser.parse_args()

    root = find_repo_root()
    cat_path = canonical_catalog_path(root)
    if not cat_path.is_file():
        print(f"FAIL: catalog not found: {cat_path}", file=sys.stderr)
        return 1

    original_catalog = _load_json(cat_path)
    working_catalog = copy.deepcopy(original_catalog)

    if args.check:
        expected = build_derived_outputs(root, working_catalog)
        drifted = []
        for path, want in expected.items():
            if not path.is_file():
                drifted.append(f"missing: {path}")
                continue
            actual = path.read_text(encoding="utf-8")
            if path.suffix == ".json":
                if json.loads(actual) != json.loads(want):
                    drifted.append(f"drift: {path}")
            elif path.name in ("models.yml", "config.yml") and yaml is not None:
                if yaml.safe_load(actual) != yaml.safe_load(want):
                    drifted.append(f"drift: {path}")
            elif actual != want:
                drifted.append(f"drift: {path}")

        ok, msg = _validate_written_tree(root)
        if drifted or not ok:
            for d in drifted:
                print(f"FAIL: {d}", file=sys.stderr)
            if not ok:
                print(f"FAIL: validation error:\n{msg}", file=sys.stderr)
            return 1
        print(f"PASS: catalog.json and all {len(expected)} derived files are in sync and valid")
        return 0

    # Default pipeline when invoked without --sync-only/--check runs fetch + optimize
    do_fetch = args.fetch or (not args.sync_only and not args.optimize)
    do_optimize = args.optimize or (not args.sync_only and not args.fetch)

    fetch_notes: list[str] = []
    opt_rows: list[dict] = []

    if do_fetch and not args.sync_only:
        fetch_notes = fetch_and_merge(working_catalog, timeout=args.timeout)

    if do_optimize and not args.sync_only:
        opt_rows = optimize_catalog(working_catalog)

    if (do_fetch or do_optimize) and working_catalog != original_catalog:
        working_catalog["updated_at"] = (
            dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        )

    outputs = build_derived_outputs(root, working_catalog)

    if args.report or args.dry_run:
        print_report(fetch_notes, opt_rows)

    if args.dry_run:
        changed = [str(p.relative_to(root)) for p, content in outputs.items() if not p.exists() or p.read_text(encoding="utf-8") != content]
        if working_catalog != original_catalog:
            changed.insert(0, str(cat_path.relative_to(root)))
        print(f"\nDRY-RUN: {len(changed)} file(s) would be updated: {changed}")
        return 0

    catalog_text = _dump_json(working_catalog) if working_catalog != original_catalog else cat_path.read_text(encoding="utf-8")
    ok, msg = apply_with_rollback(root, cat_path, catalog_text, outputs)
    if not ok:
        print(f"FAIL: {msg}", file=sys.stderr)
        return 1

    print(f"PASS: catalog and {len(outputs)} derived file(s) synced and validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
