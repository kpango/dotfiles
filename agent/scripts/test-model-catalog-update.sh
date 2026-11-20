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

# 2. Isolated copy for fixture-driven --fetch + --optimize + --sync
TMP_REPO="$WORK/repo"
mkdir -p "$TMP_REPO/agent/models" "$TMP_REPO/agent/scripts" \
    "$TMP_REPO/agent/harnesses/omp" "$TMP_REPO/agent/harnesses/claude" \
    "$TMP_REPO/agent/harnesses/agy" "$TMP_REPO/agent/harnesses/hermes"

cp "$ROOT/agent/models/catalog.json" "$TMP_REPO/agent/models/catalog.json"
cp "$ROOT/agent/models/schema.json" "$TMP_REPO/agent/models/schema.json"
cp "$ROOT/agent/scripts/update-model-catalog.py" "$TMP_REPO/agent/scripts/update-model-catalog.py"
cp "$ROOT/agent/scripts/resolve-model-tier.py" "$TMP_REPO/agent/scripts/resolve-model-tier.py"
for h in omp claude agy hermes; do
    cp "$ROOT/agent/harnesses/$h/model-routing.json" "$TMP_REPO/agent/harnesses/$h/model-routing.json"
done
cp "$ROOT/agent/harnesses/omp/config.yml" "$TMP_REPO/agent/harnesses/omp/config.yml"
cp "$ROOT/agent/harnesses/omp/models.yml" "$TMP_REPO/agent/harnesses/omp/models.yml"
cp "$ROOT/agent/harnesses/omp/sol-pi.json" "$TMP_REPO/agent/harnesses/omp/sol-pi.json"

FIXTURE_LITELLM="$WORK/litellm.json"
FIXTURE_OR="$WORK/openrouter.json"
FIXTURE_OG="$WORK/opencode_go.json"
FIXTURE_OL="$WORK/ollama.json"
FIXTURE_AG="$WORK/antigravity.json"

cat > "$FIXTURE_LITELLM" <<'JSON'
{
  "openai/gpt-6.5-astra": {
    "input_cost_per_token": 1.0e-6,
    "output_cost_per_token": 4.0e-6,
    "max_input_tokens": 524288,
    "max_output_tokens": 65536,
    "supports_reasoning": true,
    "eligible_tiers": ["XHigh", "Max"],
    "scores": {"coding": 99.0, "reasoning": 99.5, "speed": 75.0}
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
import json, sys, yaml
from pathlib import Path

r = Path(sys.argv[1])
omp = json.loads((r / "agent/harnesses/omp/model-routing.json").read_text())
hermes = json.loads((r / "agent/harnesses/hermes/model-routing.json").read_text())
sol = json.loads((r / "agent/harnesses/omp/sol-pi.json").read_text())
cfg = yaml.safe_load((r / "agent/harnesses/omp/config.yml").read_text())
mods = yaml.safe_load((r / "agent/harnesses/omp/models.yml").read_text())

assert omp["tiers"]["Low"]["model"] == "opencode-go/deepseek-v4.5-flash", omp["tiers"]["Low"]
assert hermes["tiers"]["Low"]["model"] == "opencode-go/deepseek-v4.5-flash", hermes["tiers"]["Low"]
# Cross-family guard: anthropic/claude-opus-5-9 must NOT hijack XHigh while High is anthropic
assert omp["tiers"]["XHigh"]["model"] == "openai/gpt-6.5-astra", omp["tiers"]["XHigh"]
assert hermes["tiers"]["XHigh"]["model"] == "openai/gpt-6.5-astra", hermes["tiers"]["XHigh"]
# Downstream OMP files must reflect the upgrade
assert sol["evidencePreservingReducerModel"] == "deepseek-v4.5-flash", sol
assert cfg["modelRoles"]["fast"].startswith("opencode-go/deepseek-v4.5-flash:"), cfg["modelRoles"]
assert cfg["modelRoles"]["review"].startswith("openai/gpt-6.5-astra:"), cfg["modelRoles"]
assert any(m["id"] == "deepseek-v4.5-flash" for m in mods["providers"]["opencode-go"]["models"]), mods
PY
check "Pareto optimization promotes better models & preserves cross-family XHigh + syncs all OMP configs" 1

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
orig_omp = (r / "agent/harnesses/omp/model-routing.json").read_text()

broken = json.loads(orig_cat)
broken["harnesses"]["omp"]["tiers"]["Low"]["effort"] = "invalid-effort"
outs = upd.build_derived_outputs(r, broken)
ok, msg = upd.apply_with_rollback(r, cat_path, json.dumps(broken, indent=2) + "\n", outs)
assert not ok, "Expected validation failure to trigger rollback"
assert cat_path.read_text() == orig_cat, "catalog.json was not rolled back!"
assert (r / "agent/harnesses/omp/model-routing.json").read_text() == orig_omp, "omp/model-routing.json was not rolled back!"
PY
check "Rollback atomicity restores catalog.json and derived files on validation failure" 1

# 3b. sol-pi.json extension keys (*Config) survive render; OMP Lean Profile is rendered
python3 -I -B - "$TMP_REPO" <<'PYEOF'
import importlib.util, json, sys
from pathlib import Path

r = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("upd", r / "agent/scripts/update-model-catalog.py")
upd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upd)

catalog = json.loads((r / "agent/models/catalog.json").read_text())
orig = json.loads((r / "agent/harnesses/omp/sol-pi.json").read_text())
cfg_keys = [k for k in orig if k.endswith("Config")]
assert cfg_keys, "fixture sol-pi.json must carry *Config keys"
bool_keys = [k for k, v in orig.items() if isinstance(v, bool)]
assert bool_keys, "fixture sol-pi.json must carry top-level booleans"

out = json.loads(upd.render_sol_pi_json(json.dumps(orig), catalog))
for k in cfg_keys + bool_keys + ["version", "ref"]:
    assert out[k] == orig[k], f"render_sol_pi_json lost or changed {k}"
extra = dict(orig, futureKnobConfig={"enabled": True})
out2 = json.loads(upd.render_sol_pi_json(json.dumps(extra), catalog))
assert out2["futureKnobConfig"] == {"enabled": True}, "unknown *Config key dropped"

import yaml
bare = "defaultThinkingLevel: high\n\nmodelRoles:\n  default: a/b:high\n\nretry:\n  fallbackChains:\n    default:\n      - a/b:high\n"
parsed = yaml.safe_load(upd.render_omp_config_yml(bare, catalog))
assert parsed["tui"]["renderEmbeds"] is False
assert parsed["tools"]["disabled"] == ["tts", "generate_image", "computer"]
for k in ("todo", "memory", "commit", "disassembler"):
    assert k in parsed, f"lean profile missing {k}"
again = upd.render_omp_config_yml(upd.render_omp_config_yml(bare, catalog), catalog)
assert again == upd.render_omp_config_yml(bare, catalog), "lean profile render is not idempotent"
PYEOF
check "sol-pi.json *Config/boolean keys preserved; OMP Lean Profile rendered idempotently" 1


# 4. Bun dynamic catalog loader unit test
if command -v bun &>/dev/null; then
    (cd "$ROOT/agent/harnesses/omp/extensions" && bun test lib/model-catalog.test.ts)
    check "OMP lib/model-catalog.test.ts passes under bun test" 1
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
