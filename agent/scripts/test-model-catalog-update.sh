#!/usr/bin/env bash
# Test suite for SSoT model catalog updater (fetch, Pareto optimize, cross-family guard, sync, rollback, Bun loader)
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPDATER="$ROOT/agent/scripts/update-model-catalog.py"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

fail=0
check() {
    local desc="$1" ok="$2"
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc" >&2
        fail=$((fail + 1))
    fi
}

echo "=== Model Catalog Updater Verification ==="

# 1. Live repo SSoT check
python3 "$UPDATER" --check
check "live repo --check passes" 1

# 2. Isolated copy for fixture-driven --fetch + --optimize + --sync.
# The fixture "better" models must out-score the incumbents by more than the hysteresis margin for ANY
# pricing/context the daily live feed may have written into catalog.json (not just the committed values).
TMP_REPO="$WORK/repo"
mkdir -p "$TMP_REPO/agent/models" "$TMP_REPO/agent/scripts" \
    "$TMP_REPO/agent/harnesses/pi" "$TMP_REPO/agent/harnesses/claude" \
    "$TMP_REPO/agent/harnesses/agy" "$TMP_REPO/agent/harnesses/hermes"

cp "$ROOT/agent/models/catalog.json" "$TMP_REPO/agent/models/catalog.json"
cp "$ROOT/agent/models/schema.json" "$TMP_REPO/agent/models/schema.json"
cp "$ROOT/agent/scripts/update-model-catalog.py" "$TMP_REPO/agent/scripts/update-model-catalog.py"
cp "$ROOT/agent/scripts/resolve-model-tier.py" "$TMP_REPO/agent/scripts/resolve-model-tier.py"
for h in pi claude agy hermes; do
    cp "$ROOT/agent/harnesses/$h/model-routing.json" "$TMP_REPO/agent/harnesses/$h/model-routing.json"
done
cp "$ROOT/agent/harnesses/pi/settings.json" "$TMP_REPO/agent/harnesses/pi/settings.json"
cp "$ROOT/agent/harnesses/pi/models.json" "$TMP_REPO/agent/harnesses/pi/models.json"
cp "$ROOT/agent/harnesses/pi/sol-pi.json" "$TMP_REPO/agent/harnesses/pi/sol-pi.json"

FIXTURE_LITELLM="$WORK/litellm.json"
FIXTURE_OR="$WORK/openrouter.json"
FIXTURE_OG="$WORK/opencode_go.json"
FIXTURE_OL="$WORK/ollama.json"
FIXTURE_AG="$WORK/antigravity.json"

cat > "$FIXTURE_LITELLM" <<'JSON'
{
  "openai/gpt-6.5-astra": {
    "input_cost_per_token": 1.0e-7,
    "output_cost_per_token": 4.0e-7,
    "max_input_tokens": 1048576,
    "max_output_tokens": 65536,
    "supports_reasoning": true,
    "eligible_tiers": ["XHigh", "Max"],
    "scores": {"coding": 100.0, "reasoning": 100.0, "speed": 90.0}
  },
  "openai/sora-2-pro": {
    "mode": "video_generation",
    "input_cost_per_token": 0.0,
    "output_cost_per_token": 0.0
  },
  "openai/gpt-unscored-9": {
    "mode": "chat",
    "input_cost_per_token": 1.0e-7,
    "output_cost_per_token": 1.0e-7,
    "max_input_tokens": 1048576
  },
  "anthropic/claude-opus-5-9": {
    "input_cost_per_token": 1.0e-6,
    "output_cost_per_token": 4.0e-6,
    "max_input_tokens": 1000000,
    "max_output_tokens": 65536,
    "supports_reasoning": true,
    "eligible_tiers": ["XHigh"],
    "scores": {"coding": 100.0, "reasoning": 100.0, "speed": 99.0}
  }
}
JSON

echo '{"data": []}' > "$FIXTURE_OR"
cat > "$FIXTURE_OG" <<'JSON'
{
  "data": [
    {
      "id": "deepseek-v4.5-flash",
      "name": "DeepSeek V4.5 Flash (OpenCode Go)",
      "contextWindow": 262144,
      "maxTokens": 32768,
      "reasoning": true,
      "eligible_tiers": ["Low"],
      "scores": {"coding": 92.0, "reasoning": 89.0, "speed": 98.0}
    }
  ]
}
JSON
echo '{"models": []}' > "$FIXTURE_OL"
echo '{"version": 1, "models": []}' > "$FIXTURE_AG"

MODEL_CATALOG_LITELLM_FIXTURE="$FIXTURE_LITELLM" \
MODEL_CATALOG_OPENROUTER_FIXTURE="$FIXTURE_OR" \
MODEL_CATALOG_OPENCODE_GO_FIXTURE="$FIXTURE_OG" \
MODEL_CATALOG_OLLAMA_FIXTURE="$FIXTURE_OL" \
MODEL_CATALOG_ANTIGRAVITY_FIXTURE="$FIXTURE_AG" \
python3 "$TMP_REPO/agent/scripts/update-model-catalog.py" --fetch --optimize --report

python3 "$TMP_REPO/agent/scripts/update-model-catalog.py" --check
check "fixture update + sync passes --check" 1

python3 - "$TMP_REPO" <<'PY'
import json, sys
from pathlib import Path

r = Path(sys.argv[1])
pi = json.loads((r / "agent/harnesses/pi/model-routing.json").read_text())
hermes = json.loads((r / "agent/harnesses/hermes/model-routing.json").read_text())
sol = json.loads((r / "agent/harnesses/pi/sol-pi.json").read_text())
settings = json.loads((r / "agent/harnesses/pi/settings.json").read_text())
mods = json.loads((r / "agent/harnesses/pi/models.json").read_text())
cat = json.loads((r / "agent/models/catalog.json").read_text())

assert pi["tiers"]["Low"]["model"] == "opencode-go/deepseek-v4.5-flash", pi["tiers"]["Low"]
assert hermes["tiers"]["Low"]["model"] == "opencode-go/deepseek-v4.5-flash", hermes["tiers"]["Low"]
# Cross-family guard: anthropic/claude-opus-5-9 must NOT hijack XHigh while High is anthropic
assert pi["tiers"]["XHigh"]["model"] == "openai/gpt-6.5-astra", pi["tiers"]["XHigh"]
assert hermes["tiers"]["XHigh"]["model"] == "openai/gpt-6.5-astra", hermes["tiers"]["XHigh"]
# Downstream Pi files must reflect the upgrade
assert sol["evidencePreservingReducerModel"] == "deepseek-v4.5-flash", sol
assert settings["defaultProvider"] == "anthropic" and settings["defaultModel"] == "claude-opus-5-5", settings
assert "npm:@estebanforge/pi-antigravity-bridge@1.16.0" in settings["packages"], settings
assert cat["pi_config"]["modelRoles"]["fast"].startswith("opencode-go/deepseek-v4.5-flash:"), cat["pi_config"]["modelRoles"]
assert cat["pi_config"]["modelRoles"]["review"].startswith("openai/gpt-6.5-astra:"), cat["pi_config"]["modelRoles"]
assert any(m["id"] == "deepseek-v4.5-flash" for m in mods["providers"]["opencode-go"]["models"]), mods

# Feed ingestion guards: no non-chat models, heuristic-only candidates stay out of every tier pool,
# and feed-discovered models are never granted the closed Antigravity (agy) harness.
assert "openai/sora-2-pro" not in cat["models"], "non-chat LiteLLM model was ingested"
un = cat["models"]["openai/gpt-unscored-9"]
assert un["eligible_tiers"] == [] and un["status"] == "candidate", un
for key in ("openai/gpt-6.5-astra", "anthropic/claude-opus-5-9", "openai/gpt-unscored-9"):
    assert "agy" not in cat["models"][key]["harness_support"], key
agy = json.loads((r / "agent/harnesses/agy/model-routing.json").read_text())
assert "sora" not in json.dumps(agy), "sora leaked into agy routing"
PY
check "Pareto optimization promotes better models & preserves cross-family XHigh + syncs all Pi configs" 1

# 2b. Availability guard: a model the harness cannot host must fail validation
python3 - "$TMP_REPO" <<'PY'
import importlib.util, json, sys
from pathlib import Path

r = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("upd", r / "agent/scripts/update-model-catalog.py")
upd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upd)

cat = json.loads((r / "agent/models/catalog.json").read_text())
assert upd.validate_harness_models(cat) == [], upd.validate_harness_models(cat)
bad = json.loads(json.dumps(cat))
bad["harnesses"]["agy"]["tiers"]["Low"]["model"] = "sora-2-pro"
bad["harnesses"]["agy"]["tiers"]["High"]["fallbacks"][0]["model"] = "claude-haiku-5-5"
bad["models"]["openai/gpt-6.2-astra"]["harness_support"].append("agy")
errs = "\n".join(upd.validate_harness_models(bad))
assert "sora-2-pro" in errs and "claude-haiku-5-5" in errs and "gpt-6.2-astra" in errs, errs
PY
check "validate_harness_models rejects models a harness cannot host (agy: sora/haiku/openai)" 1

# 2c. agy allowlist matches the real `agy models` listing when the CLI is installed (skipped otherwise)
if command -v agy &>/dev/null; then
    if AGY_LIST="$(timeout 30 agy models 2>/dev/null)" && [ -n "$AGY_LIST" ]; then
        python3 - "$ROOT" "$AGY_LIST" <<'PY'
import json, re, sys
from pathlib import Path

cat = json.loads((Path(sys.argv[1]) / "agent/models/catalog.json").read_text())
live = {re.sub(r"-(low|medium|high|xhigh)$", "", l.split()[0]) for l in sys.argv[2].splitlines() if l.strip() and "\t" in l}
missing = sorted(set(cat["harness_model_allowlist"]["agy"]) - live)
assert not missing, f"harness_model_allowlist.agy not offered by `agy models`: {missing}"
PY
        check "harness_model_allowlist.agy is a subset of live \`agy models\`" 1
    else
        echo "SKIP: agy models unavailable"
    fi
fi

# 3. Rollback atomicity test: invalid output injected -> apply_with_rollback restores everything
python3 - "$TMP_REPO" <<'PY'
import importlib.util, json, sys
from pathlib import Path

r = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("upd", r / "agent/scripts/update-model-catalog.py")
upd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upd)

cat_path = r / "agent/models/catalog.json"
orig_cat = cat_path.read_text()
orig_pi = (r / "agent/harnesses/pi/model-routing.json").read_text()

broken = json.loads(orig_cat)
broken["harnesses"]["pi"]["tiers"]["Low"]["effort"] = "invalid-effort"
outs = upd.build_derived_outputs(r, broken)
ok, msg = upd.apply_with_rollback(r, cat_path, json.dumps(broken, indent=2) + "\n", outs)
assert not ok, "Expected validation failure to trigger rollback"
assert cat_path.read_text() == orig_cat, "catalog.json was not rolled back!"
assert (r / "agent/harnesses/pi/model-routing.json").read_text() == orig_pi, "pi/model-routing.json was not rolled back!"
PY
check "Rollback atomicity restores catalog.json and derived files on validation failure" 1

# 3b. sol-pi.json upstream shape + pi namespace survive render; settings.json preserves packages/tools
python3 -I -B - "$TMP_REPO" <<'PYEOF'
import importlib.util, json, sys
from pathlib import Path

r = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("upd", r / "agent/scripts/update-model-catalog.py")
upd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upd)

catalog = json.loads((r / "agent/models/catalog.json").read_text())
orig = json.loads((r / "agent/harnesses/pi/sol-pi.json").read_text())
bool_keys = [k for k, v in orig.items() if isinstance(v, bool)]
assert bool_keys, "fixture sol-pi.json must carry top-level mechanism booleans"
assert orig.get("version") == 1, "fixture sol-pi.json must be upstream-shaped (version: 1)"
assert isinstance(orig.get("pi"), dict) and orig["pi"], "fixture sol-pi.json must carry the pi namespace"

out = json.loads(upd.render_sol_pi_json(json.dumps(orig), catalog))
for k in bool_keys + ["version", "pi", "cacheWriteReadRatio"]:
    assert out[k] == orig[k], f"render_sol_pi_json lost or changed {k}"
extra = dict(orig, pi=dict(orig["pi"], futureKnob={"enabled": True}))
out2 = json.loads(upd.render_sol_pi_json(json.dumps(extra), catalog))
assert out2["pi"]["futureKnob"] == {"enabled": True}, "unknown pi-namespace key dropped"

bare_settings = json.dumps({"enableAnalytics": False, "packages": ["npm:@estebanforge/pi-antigravity-bridge@1.16.0"]})
parsed_s = json.loads(upd.render_pi_settings_json(bare_settings, catalog))
assert parsed_s["defaultProvider"] == "anthropic"
assert parsed_s["defaultModel"] == "claude-opus-5-5"
assert parsed_s["packages"] == ["npm:@estebanforge/pi-antigravity-bridge@1.16.0"]
assert upd.render_pi_settings_json(upd.render_pi_settings_json(bare_settings, catalog), catalog) == upd.render_pi_settings_json(bare_settings, catalog)
PYEOF
check "sol-pi.json upstream shape + pi namespace preserved; Pi settings.json rendered idempotently" 1


# 4. Bun dynamic catalog loader unit test
if command -v bun &>/dev/null; then
    (cd "$ROOT/agent/harnesses/pi/extensions" && bun test lib/model-catalog.test.ts)
    check "Pi lib/model-catalog.test.ts passes under bun test" 1
else
    echo "SKIP: bun not found for model-catalog.test.ts"
fi

if [ "$fail" -gt 0 ]; then
    echo "test-model-catalog-update: $fail failure(s)" >&2
    exit 1
fi
echo
echo "test-model-catalog-update: 全テストPASS"
exit 0
