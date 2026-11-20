#!/usr/bin/env bash
# agent/scripts/evolve/harness2-offline.py (Harness² オフライン自己進化パイプライン) の全5ステージと
# Fail-Closed 入力検証を検証する自動テスト。
#   Stage1: N>=3 フィルタ / Stage2: C1-C8 分類・INV vs DOM / Stage3: Net Token Budget<=0・SKILL.md 制約
#   Stage4: Held-Out 回帰棄却・Security Monotonicity Gate (stub) / Stage5: SHA-256 重複排除・追記のみ・diff 出力のみ
# 本番リポジトリには一切書かない: 全ての fixture / 出力は mktemp -d 配下 (trap で一括削除)。
#
# usage: agent/scripts/test-harness2-offline.sh
# env:   HARNESS2_PY=<path>  テスト対象スクリプトの差し替え (mutation チェック用)
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
H2="${HARNESS2_PY:-$ROOT/agent/scripts/evolve/harness2-offline.py}"
EXP_SRC="$ROOT/agent/context/library/EXPERIENCE.md"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
# gate の複製 (tempfile) をこの実行専用の場所に作らせる: 並列実行や他プロセスの複製と混ざらず、残骸を正確に数えられる
mkdir "$TMP/tmpd"
export TMPDIR="$TMP/tmpd"

total_fail=0
section() { echo; echo "=== $1 ==="; }
ok() { echo "[OK] $1"; }
bad() { echo "[FAIL] $1"; total_fail=$((total_fail + 1)); }
check() { # desc expected actual
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 : expected=[$2] got=[$3]"; fi
}
check_has() { # desc haystack needle
    if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1 : needle=[$3] not in [$2]"; fi
}

# ---------------------------------------------------------------- fixtures
chars() { head -c "$1" </dev/zero | tr '\0' "$2"; }
skill_text() { # LINES DESCLEN [FILL]
    local lines="$1" dl="$2" fill="${3:-1}" i x
    printf -- '---\nname: foo\ndescription: %s\n---\n' "$(chars "$dl" d)"
    x="$(chars "$fill" x)"
    for ((i = 4; i < lines; i++)); do printf '%s\n' "$x"; done
}

REPO="$TMP/repo"
mkdir -p "$REPO/agent/harnesses/omp/extensions" "$REPO/agent/rules" "$REPO/agent/context/library" \
    "$REPO/agent/agents" "$REPO/agent/skills/foo" "$REPO/agent/scripts"
for f in agent/harnesses/omp/SYSTEM.md agent/rules/r.md agent/AGENTS.md agent/agents/a.md \
    agent/context/library/EXPERIENCE.md agent/scripts/x.py agent/harnesses/omp/extensions/e.ts; do
    chars 400 a >"$REPO/$f" # baseline = 400 chars = 100 tokens (chars/4)
done
skill_text 600 100 >"$REPO/agent/skills/foo/SKILL.md"
printf 'SECURITY_MARKER\n' >"$REPO/agent/rules/sec.md"

chars 200 a >"$TMP/t_small" # 50 tokens (delta<0)
chars 800 a >"$TMP/t_big"   # 200 tokens (delta>0)
chars 400 b >"$TMP/t_same"  # 100 tokens (delta==0, but content differs)
skill_text 500 100 >"$TMP/s_ok"
skill_text 501 100 >"$TMP/s_lines501"
skill_text 500 161 >"$TMP/s_desc161"
skill_text 500 160 >"$TMP/s_desc160"
skill_text 500 100 5 >"$TMP/s_grow"

printf '#!/usr/bin/env bash\necho run >>"%s/gate.log"\nexit 0\n' "$TMP" >"$TMP/ok.sh"
printf '#!/usr/bin/env bash\necho run >>"%s/gate.log"\nexit 1\n' "$TMP" >"$TMP/fail.sh"
export HARNESS2_TEST_TMP="$TMP"
cat >"$TMP/marker.sh" <<'EOF'
#!/usr/bin/env bash
echo "$HARNESS2_REPO_ROOT" >>"$HARNESS2_TEST_TMP/roots.log"
[[ "$(pwd -P)" == "$(cd "$HARNESS2_REPO_ROOT" && pwd -P)" ]] || exit 3
grep -q SECURITY_MARKER "$HARNESS2_REPO_ROOT/agent/rules/sec.md"
EOF
cat >"$TMP/rootarg.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >>"$HARNESS2_TEST_TMP/roots.log"
[[ "$1" == "$HARNESS2_REPO_ROOT" && -f "$1/agent/rules/sec.md" ]]
EOF
cat >"$TMP/notroot.sh" <<'EOF'
#!/usr/bin/env bash
echo run >>"$HARNESS2_TEST_TMP/gate.log"
[[ "$1" != "$2" ]]
EOF
cat >"$TMP/bigout.sh" <<'EOF'
#!/usr/bin/env bash
head -c 200000000 /dev/zero
EOF

EXPD="$TMP/exp"
EXP="$EXPD/EXPERIENCE.md"
PROP="$TMP/prop"
mkdir -p "$EXPD"

PROBES_OK='[{"name":"p1","before":false,"after":true},{"name":"p2","before":true,"after":true},{"name":"p3","before":true,"after":true}]'

trace_lines() { # SIG TARGET COUNT NTASKS
    local i
    for ((i = 0; i < $3; i++)); do
        jq -nc --arg s "$1" --arg t "$2" --arg k "task$((i % $4))" '{signature:$s,task:$k,target:$t,message:"boom"}'
    done
}
cand() { # id sig target textfile [probes-json]
    jq -n --arg id "$1" --arg sig "$2" --arg t "$3" --rawfile txt "$4" --argjson pr "${5:-$PROBES_OK}" \
        '{id:$id,signature:$sig,target:$t,new_text:$txt,probes:$pr}'
}

# 既定の gate (bwrap 隔離) は stub が $TMP に書けないため、stub を使う既存テストは明示フラグで隔離を外す。隔離そのものは「試行4-4」で検証する
UNSB=(--allow-unsandboxed-gate)
run_h2() { python3 -I -B "$H2" "${UNSB[@]}" "$@" >"$TMP/out.txt" 2>"$TMP/err.txt"; RC=$?; }
fresh_state() { rm -rf "$PROP"; command cp "$EXP_SRC" "$EXP" 2>/dev/null || printf '# stub\n' >"$EXP"; : >"$TMP/gate.log"; : >"$TMP/roots.log"; }
GATE_SH="$TMP/ok.sh"
std_run() { # traces cands [extra...]
    local tr="$1" cs="$2"
    shift 2
    run_h2 --traces "$tr" --candidates "$cs" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" \
        --security-cmd "bash $GATE_SH" --json "$@"
}
jq_out() { jq -r "$1" "$TMP/out.txt" 2>/dev/null; }
cstat() { jq_out ".candidates[]|select(.id==\"$1\")|.status"; }
creason() { jq_out ".candidates[]|select(.id==\"$1\")|.reasons|join(\",\")"; }
repo_hash() { (cd "$REPO" && find . -type f -exec sha256sum {} + | sort | sha256sum); }

verify_ids() { # EXPERIENCE.md path -> OK | diagnostics
    python3 -I -B - "$H2" "$1" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("h2", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
text = open(sys.argv[2], encoding="utf-8").read()
entries = m.parse_experience(text)
bad = [e["id"] for e in entries if e["id"] != m.entry_id(e["pattern"], e["target"], e["scope"])]
print("OK" if entries and not bad else f"BAD ids={bad} n={len(entries)}")
PY
}

# ================================================================ EXPERIENCE.md 正典
section "EXPERIENCE.md (C3 正典) のスキーマと初期エントリ"
n="$(grep -c '^### [0-9a-f]\{16\}$' "$EXP_SRC" 2>/dev/null || true)"
check "初期蒸留エントリが4件" "4" "${n:-0}"
check "全エントリの id = SHA-256(pattern\\ntarget\\nscope) の先頭16hex" "OK" "$(verify_ids "$EXP_SRC" | tail -1)"
check "EXPERIENCE.md にバイト基準でない古い見積もり記述が残っていない" "0" "$(grep -c 'ceil(chars/4)' "$EXP_SRC" 2>/dev/null || true)"
check "EXPERIENCE.md がバイト基準の見積もりを記述" "1" "$(grep -c 'ceil(UTF-8 bytes/4)' "$EXP_SRC" 2>/dev/null || true)"
for kw in "RTK" "Action Fusion" "Pricing Cliff" "Net Token Budget"; do
    if grep -q "$kw" "$EXP_SRC" 2>/dev/null; then ok "EXPERIENCE.md に '$kw'"; else bad "EXPERIENCE.md に '$kw' が無い"; fi
done

# ================================================================ Stage 1
section "Stage1: N>=3 フィルタ"
{ trace_lines "sig a" agent/scripts/x.py 2 2; trace_lines "sig b" agent/scripts/x.py 3 3; } >"$TMP/tr1.jsonl"
{ cand cA "sig a" agent/scripts/x.py "$TMP/t_small"; cand cB "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c1.json"
fresh_state
std_run "$TMP/tr1.jsonl" "$TMP/c1.json"
check "rc=0" "0" "$RC"
check "2件のシグネチャは棄却 (cluster)" "below_min_occurrences" "$(jq_out '.clusters[]|select(.signature=="sig a")|.reason')"
check "3件のシグネチャは採用 (cluster)" "accepted" "$(jq_out '.clusters[]|select(.signature=="sig b")|.status')"
check "2件由来の候補は棄却" "rejected" "$(cstat cA)"
check "2件由来の棄却理由" "noise_signature" "$(creason cA)"
check "3件由来の候補は採用" "accepted" "$(cstat cB)"
fresh_state
std_run "$TMP/tr1.jsonl" "$TMP/c1.json" --min-occurrences 2
check "--min-occurrences 2 なら2件も採用" "accepted" "$(cstat cA)"

# ================================================================ Stage 2
section "Stage2: C1-C8 分類 / INV vs DOM"
{ trace_lines "sig b" agent/scripts/x.py 3 3; trace_lines "sig d" agent/scripts/x.py 3 1; } >"$TMP/tr2.jsonl"
{
    cand k1 "sig b" agent/harnesses/omp/SYSTEM.md "$TMP/t_small"
    cand k2 "sig b" agent/rules/r.md "$TMP/t_small"
    cand k3 "sig b" agent/context/library/EXPERIENCE.md "$TMP/t_small"
    cand k4 "sig b" agent/AGENTS.md "$TMP/t_small"
    cand k5 "sig b" agent/agents/a.md "$TMP/t_small"
    cand k6 "sig b" agent/skills/foo/SKILL.md "$TMP/s_ok"
    cand k7 "sig b" agent/scripts/x.py "$TMP/t_small"
    cand k8 "sig b" agent/harnesses/omp/extensions/e.ts "$TMP/t_small"
    cand kD "sig d" agent/scripts/x.py "$TMP/t_small"
    cand kU "sig b" README.md "$TMP/t_small"
} | jq -s . >"$TMP/c2.json"
fresh_state
std_run "$TMP/tr2.jsonl" "$TMP/c2.json"
check "rc=0" "0" "$RC"
for i in 1 2 3 4 5 6 7 8; do
    check "k$i -> C$i" "C$i" "$(jq_out ".candidates[]|select(.id==\"k$i\")|.component")"
    check "k$i は採用" "accepted" "$(cstat "k$i")"
done
check "複数タスクに跨る失敗は INV" "INV" "$(jq_out '.candidates[]|select(.id=="k7")|.scope')"
check "単一タスクの失敗は DOM" "DOM" "$(jq_out '.candidates[]|select(.id=="kD")|.scope')"
check "分類不能な target は棄却" "unclassified_target" "$(creason kU)"

# swarm-evolve 仮説カテゴリ: A=.trail/ B=skills/ C=harnesses|models|hooks|extensions
check "仮説カテゴリ: skills/ は B" "B" "$(jq_out '.candidates[]|select(.id=="k6")|.category')"
check "仮説カテゴリ: harnesses/ は C" "C" "$(jq_out '.candidates[]|select(.id=="k1")|.category')"
check "仮説カテゴリ: extensions/ は C" "C" "$(jq_out '.candidates[]|select(.id=="k8")|.category')"
check "仮説カテゴリ: 該当なしは null" "null" "$(jq_out '.candidates[]|select(.id=="k7")|.category')"
jq '(.[]|select(.id=="k6")) += {category:"C"} | (.[]|select(.id=="k8")) += {category:"C"} | (.[]|select(.id=="k1")) += {category:"B"}' \
    "$TMP/c2.json" >"$TMP/c2cat.json"
fresh_state
std_run "$TMP/tr2.jsonl" "$TMP/c2cat.json"
check "宣言カテゴリが導出と食い違えば棄却 (B宣言のskills→C)" "category_mismatch" "$(creason k6)"
check "宣言カテゴリが導出と食い違えば棄却 (B宣言のharnesses)" "category_mismatch" "$(creason k1)"
check "宣言カテゴリが導出と一致すれば採用" "accepted" "$(cstat k8)"
jq '(.[]|select(.id=="k8")) += {category:"Z"}' "$TMP/c2.json" >"$TMP/c2bad.json"
fresh_state
std_run "$TMP/tr2.jsonl" "$TMP/c2bad.json"
check "不正な category 値は入力エラー (rc!=0)" "1" "$([ "$RC" != 0 ] && echo 1 || echo 0)"

# ================================================================ Stage 3
section "Stage3: Net Token Budget <= 0 / SKILL.md 制約"
trace_lines "sig b" agent/scripts/x.py 3 3 >"$TMP/tr3.jsonl"
{
    cand b1 "sig b" agent/harnesses/omp/SYSTEM.md "$TMP/t_big"
    cand b2 "sig b" agent/rules/r.md "$TMP/t_big"
    cand b4 "sig b" agent/AGENTS.md "$TMP/t_big"
    cand b6 "sig b" agent/skills/foo/SKILL.md "$TMP/s_grow"
    cand bz "sig b" agent/rules/r.md "$TMP/t_same"
    cand bs "sig b" agent/rules/r.md "$TMP/t_small"
    cand b5 "sig b" agent/agents/a.md "$TMP/t_big"
    cand b7 "sig b" agent/scripts/x.py "$TMP/t_big"
    cand b8 "sig b" agent/harnesses/omp/extensions/e.ts "$TMP/t_big"
    cand bl "sig b" agent/skills/foo/SKILL.md "$TMP/s_lines501"
    cand bd "sig b" agent/skills/foo/SKILL.md "$TMP/s_desc161"
    cand bo "sig b" agent/skills/foo/SKILL.md "$TMP/s_desc160"
    cand bn "sig b" agent/rules/r.md "$REPO/agent/rules/r.md"
} | jq -s . >"$TMP/c3.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c3.json"
check "rc=0" "0" "$RC"
for id in b1 b2 b4 b6; do
    check "常時ロード層の増加 ($id) は棄却" "net_token_budget" "$(creason $id)"
done
check "delta_tokens が報告される (b2 = +100)" "100" "$(jq_out '.candidates[]|select(.id=="b2")|.delta_tokens')"
check "delta==0 は採用 (境界)" "accepted" "$(cstat bz)"
check "delta<0 は採用" "accepted" "$(cstat bs)"
for id in b5 b7 b8; do
    check "常時ロード層以外の増加 ($id) は採用" "accepted" "$(cstat $id)"
done
check "SKILL.md 501行は棄却 (トークンは減少)" "skill_lines" "$(creason bl)"
check "description 161文字は棄却" "skill_description" "$(creason bd)"
check "description 160文字は採用" "accepted" "$(cstat bo)"
check "無変更は棄却" "no_change" "$(creason bn)"

# ================================================================ Stage 4: Held-Out
section "Stage4: Contrastive Probe / Held-Out 回帰"
PROBES6='[{"name":"p1","before":true,"after":true},{"name":"p2","before":true,"after":true},{"name":"p3","before":true,"after":true},{"name":"p4","before":true,"after":true},{"name":"p5","before":true,"after":true},{"name":"p6","before":true,"after":true}]'
{ cand h0 "sig b" agent/scripts/x.py "$TMP/t_small" "$PROBES6"; } | jq -s . >"$TMP/c4a.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c4a.json"
split1="$(jq -c '.candidates[0].split' "$TMP/out.txt")"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c4a.json"
check "Training/Held-Out 分割は決定論的" "$split1" "$(jq -c '.candidates[0].split' "$TMP/out.txt")"
held="$(jq -r '.candidates[0].split.held_out[0]' "$TMP/out.txt")"
train="$(jq -r '.candidates[0].split.train[0]' "$TMP/out.txt")"
check "Held-Out は空でない" "false" "$([[ -z "$held" || "$held" == null ]] && echo true || echo false)"
check "Training も空でない" "false" "$([[ -z "$train" || "$train" == null ]] && echo true || echo false)"
reg_held="$(jq -c --arg h "$held" 'map(.after = (.name != $h))' <<<"$PROBES6")"
reg_train="$(jq -c --arg h "$train" 'map(.after = (.name != $h))' <<<"$PROBES6")"
{
    cand hr "sig b" agent/scripts/x.py "$TMP/t_small" "$reg_held"
    cand ht "sig b" agent/scripts/x.py "$TMP/t_small" "$reg_train"
    cand hn "sig b" agent/scripts/x.py "$TMP/t_small" "[]"
    cand hg "sig b" agent/scripts/x.py "$TMP/t_small" "$PROBES6"
} | jq -s . >"$TMP/c4b.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c4b.json"
check "Held-Out で1件回帰した候補は棄却" "heldout_regression" "$(creason hr)"
check "回帰なしの候補は採用" "accepted" "$(cstat hg)"
check "probe が無い候補は棄却" "no_probes" "$(creason hn)"
check "修正なしの Training 回帰は棄却" "training_regression" "$(creason ht)"
trainall="$(jq -c '.candidates[0].split.train' "$TMP/out.txt")"
heldall="$(jq -c '.candidates[0].split.held_out' "$TMP/out.txt")"
mixed1="$(jq -nc --argjson t "$trainall" --argjson h "$heldall" '[($t|to_entries[]|{name:.value,before:((.key==1 or .key==2)|not),after:(.key!=0)}),($h[]|{name:.,before:true,after:true})]')"
mixed2="$(jq -nc --argjson t "$trainall" --argjson h "$heldall" '[($t|to_entries[]|{name:.value,before:(.key!=1),after:((.key==0 or .key==3)|not)}),($h[]|{name:.,before:true,after:true})]')"
{
    cand tm1 "sig b" agent/scripts/x.py "$TMP/t_small" "$mixed1"
    cand tm2 "sig b" agent/scripts/x.py "$TMP/t_small" "$mixed2"
} | jq -s . >"$TMP/c4c.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c4c.json"
check "Training: 回帰1 < 修正2 は採用" "accepted" "$(cstat tm1)"
check "Training の回帰件数を警告として報告" "1" "$(jq_out '.candidates[]|select(.id=="tm1")|.training_regressions')"
check "Training の修正件数を報告" "2" "$(jq_out '.candidates[]|select(.id=="tm1")|.training_fixes')"
check "Training: 回帰2 > 修正1 は棄却" "training_regression" "$(creason tm2)"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c4a.json" --seed 7
s_a="$(jq -c '.candidates[0].split' "$TMP/out.txt")"
std_run "$TMP/tr3.jsonl" "$TMP/c4a.json" --seed 7
check "同じ --seed なら分割は同一" "$s_a" "$(jq -c '.candidates[0].split' "$TMP/out.txt")"
distinct=""
for sd in 1 2 3 4 5 6; do
    std_run "$TMP/tr3.jsonl" "$TMP/c4a.json" --seed "$sd"
    distinct+="$(jq -c '.candidates[0].split.held_out' "$TMP/out.txt")"$'\n'
done
check "--seed を変えると Held-Out が変わりうる" "true" "$([[ "$(printf '%s' "$distinct" | sort -u | wc -l)" -ge 2 ]] && echo true || echo false)"

# ================================================================ Stage 4: Security gate
section "Stage4: Security Monotonicity Gate (stub)"
{ cand g1 "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c5.json"
fresh_state
GATE_SH="$TMP/ok.sh" std_run "$TMP/tr3.jsonl" "$TMP/c5.json"
check "gate が通れば採用" "accepted" "$(cstat g1)"
check "gate を実際に実行した (baseline 1 + 候補 1)" "2" "$(wc -l <"$TMP/gate.log" | tr -d ' ')"
fresh_state
GATE_SH="$TMP/fail.sh"
std_run "$TMP/tr3.jsonl" "$TMP/c5.json"
check "gate が落ちたら棄却 (baseline 失敗)" "security_gate_baseline" "$(creason g1)"
check "security_gate.ok=false を報告" "false" "$(jq_out '.security_gate.ok')"
GATE_SH="$TMP/ok.sh"
fresh_state
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c5.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --security-cmd "bash $TMP/fail.sh" --json
check "複数 gate のうち1つが落ちても棄却" "security_gate_baseline" "$(creason g1)"
fresh_state
HARNESS2_SECURITY_CMDS="bash $TMP/fail.sh" run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c5.json" \
    --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" --json
check "環境変数 HARNESS2_SECURITY_CMDS でも stub 差し替え可能" "security_gate_baseline" "$(creason g1)"

section "Stage4: Gate は候補を適用した複製 tree で走る / baseline / 差し替えの可視化"
printf x >"$TMP/t_x"
printf SECURITY_MARKER >"$TMP/t_marker"
{
    cand gm "sig b" agent/rules/sec.md "$TMP/t_x"
    cand gk "sig b" agent/rules/sec.md "$TMP/t_marker"
    cand go "sig b" agent/rules/r.md "$TMP/t_small"
} | jq -s . >"$TMP/c7.json"
fresh_state
before_hash="$(repo_hash)"
GATE_SH="$TMP/marker.sh" std_run "$TMP/tr3.jsonl" "$TMP/c7.json"
check "gate の対象文字列を削る候補は棄却" "security_gate" "$(creason gm)"
check "対象文字列を保つ候補は採用 (sec.md)" "accepted" "$(cstat gk)"
check "無害な候補は採用 (r.md)" "accepted" "$(cstat go)"
check "baseline の gate は --repo-root で走る" "$REPO" "$(head -1 "$TMP/roots.log")"
check "gate 実行回数 = baseline 1 + 候補 3" "4" "$(wc -l <"$TMP/roots.log" | tr -d ' ')"
check "候補の gate は baseline と別の複製で走る" "3" "$(tail -n +2 "$TMP/roots.log" | grep -vxc "$REPO")"
gone=true
while read -r d; do [[ -e "$d" ]] && gone=false; done < <(tail -n +2 "$TMP/roots.log")
check "複製は後始末される" "true" "$gone"
check "実 repo は変更されない (候補は複製にのみ適用)" "$before_hash" "$(repo_hash)"
fresh_state
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c7.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/rootarg.sh {root}" --json
check "{root} が複製 root に置換され HARNESS2_REPO_ROOT と一致" "accepted" "$(cstat go)"
fresh_state
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c7.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/notroot.sh {root} $REPO" --json
check "baseline が既に落ちていれば全候補を棄却" "security_gate_baseline,security_gate_baseline,security_gate_baseline" \
    "$(creason gm),$(creason gk),$(creason go)"
check "baseline の gate は1回だけ" "1" "$(wc -l <"$TMP/gate.log" | tr -d ' ')"
check "security_gate.ok=false (baseline)" "false" "$(jq_out '.security_gate.ok')"
check "差し替えを overridden=true で報告" "true" "$(jq_out '.security_gate.overridden')"
check "実行コマンド一覧を報告" "1" "$(jq_out '.security_gate.commands|length')"
fresh_state
env -u HARNESS2_SECURITY_CMDS python3 -I -B "$H2" "${UNSB[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c5.json" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$PROP" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check "既定 gate は overridden=false" "false" "$(jq_out '.security_gate.overridden')"
check_has "既定 gate のコマンド" "$(jq_out '.security_gate.commands|join(" ")')" "test-security-rules.sh"
check_has "既定 gate のコマンド (parity)" "$(jq_out '.security_gate.commands|join(" ")')" "test-write-scope-parity.sh"
fresh_state
HARNESS2_SECURITY_CMDS="bash $TMP/ok.sh" run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c5.json" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$PROP" --json
check "環境変数による差し替えも overridden=true" "true" "$(jq_out '.security_gate.overridden')"
fresh_state
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c5.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/bigout.sh" --json
check "巨大出力の gate でも rc=0 (出力は保持しない)" "0" "$RC"
check "巨大出力でも gate の exit code で判定" "accepted" "$(cstat g1)"
for v in "   " $'\n\n' $' \n\t\n'; do
    HARNESS2_SECURITY_CMDS="$v" run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c5.json" --repo-root "$REPO" \
        --experience "$EXP" --out-dir "$PROP" --json
    if [[ "$RC" -eq 2 && "$(cat "$TMP/err.txt")" == *"no security gate commands"* && "$(cat "$TMP/err.txt")" != *Traceback* ]]; then
        ok "空の HARNESS2_SECURITY_CMDS は fail-closed ($(printf '%q' "$v"))"
    else bad "空の HARNESS2_SECURITY_CMDS が受理された ($(printf '%q' "$v")) rc=$RC err=$(cat "$TMP/err.txt")"; fi
done
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c5.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "   " --json
check "空白のみの --security-cmd は rc=2" "2" "$RC"
check_has "空白のみの --security-cmd のメッセージ" "$(cat "$TMP/err.txt")" "invalid security command"

section "Stage3: UTF-8 バイト基準のトークン見積もり / SKILL.md frontmatter の厳格解析"
python3 -I -B -c "print('あ'*400, end='')" >"$TMP/t_cjk"
{ cand cj "sig b" agent/rules/r.md "$TMP/t_cjk"; } | jq -s . >"$TMP/c8a.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c8a.json"
check "400文字の ASCII -> 400文字の CJK は棄却" "net_token_budget" "$(creason cj)"
check "delta はバイト基準 (+200)" "200" "$(jq_out '.candidates[]|select(.id=="cj")|.delta_tokens')"
skill_fm() { # FILE FRONTMATTER-BODY(with \n)
    { printf -- '---\n'; printf '%b' "$2"; printf -- '---\nbody\n'; } >"$1"
}
L100="$(chars 100 p)"; L150="$(chars 150 q)"; L20="$(chars 20 r)"
skill_fm "$TMP/f_plain" "name: foo\ndescription: $L100\n  $L150\n  $L150\n"
skill_fm "$TMP/f_dup" "name: foo\ndescription: $L20\ndescription: $L20\n"
skill_fm "$TMP/f_fold" "name: foo\ndescription: >\n  $L100\n  $L100\n"
skill_fm "$TMP/f_lit" "name: foo\ndescription: |\n  $L100\n  $L100\n"
skill_fm "$TMP/f_foldok" "name: foo\ndescription: >\n  $L20\n  $L20\n"
skill_fm "$TMP/f_qkey" "name: foo\n\"description\": $L20\n"
skill_fm "$TMP/f_alias" "name: foo\ndescription: *x\n"
skill_fm "$TMP/f_none" "name: foo\n"
skill_fm "$TMP/f_nested" "name: foo\nmetadata:\n  description: $L150$L150\ndescription: $L20\n"
{
    cand fp "sig b" agent/skills/foo/SKILL.md "$TMP/f_plain"
    cand fd "sig b" agent/skills/foo/SKILL.md "$TMP/f_dup"
    cand ff "sig b" agent/skills/foo/SKILL.md "$TMP/f_fold"
    cand fl "sig b" agent/skills/foo/SKILL.md "$TMP/f_lit"
    cand fo "sig b" agent/skills/foo/SKILL.md "$TMP/f_foldok"
    cand fq "sig b" agent/skills/foo/SKILL.md "$TMP/f_qkey"
    cand fa "sig b" agent/skills/foo/SKILL.md "$TMP/f_alias"
    cand fn "sig b" agent/skills/foo/SKILL.md "$TMP/f_none"
    cand fe "sig b" agent/skills/foo/SKILL.md "$TMP/f_nested"
} | jq -s . >"$TMP/c8b.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c8b.json"
check "複数行 plain scalar (402文字) は棄却" "skill_description" "$(creason fp)"
check "重複する description キーは棄却" "skill_frontmatter" "$(creason fd)"
check "折り畳み > の長い description は棄却" "skill_description" "$(creason ff)"
check "リテラル | の長い description は棄却" "skill_description" "$(creason fl)"
check "短い折り畳み > は採用" "accepted" "$(cstat fo)"
check "引用符付きキーは棄却 (非標準構造)" "skill_frontmatter" "$(creason fq)"
check "alias 値は棄却" "skill_frontmatter" "$(creason fa)"
check "description 欠落は棄却" "skill_frontmatter" "$(creason fn)"
check "入れ子キー配下の description は無視して採用" "accepted" "$(cstat fe)"

# ================================================================ Stage 5
section "Stage5: SHA-256 重複排除 / 追記のみ / diff 出力のみ"
{ trace_lines "sig b" agent/scripts/x.py 3 3; trace_lines "sig d" agent/scripts/x.py 3 1; } >"$TMP/tr5.jsonl"
{ cand e1 "sig b" agent/scripts/x.py "$TMP/t_small"; cand e2 "sig a" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c6.json"
fresh_state
command cp "$EXP" "$TMP/exp.orig"
before_hash="$(repo_hash)"
std_run "$TMP/tr5.jsonl" "$TMP/c6.json"
check "1回目 rc=0" "0" "$RC"
check "1回目: 2件追加" "2" "$(jq_out '.experience.added|length')"
check "EXPERIENCE.md のエントリ数 = 4 + 2" "6" "$(grep -c '^### [0-9a-f]\{16\}$' "$EXP")"
if head -c "$(wc -c <"$TMP/exp.orig")" "$EXP" | cmp -s - "$TMP/exp.orig"; then ok "追記のみ (既存部分はバイト一致)"; else bad "既存エントリが書き換えられた"; fi
check "追加エントリの id が SHA-256 規約に一致" "OK" "$(verify_ids "$EXP" | tail -1)"
command cp "$EXP" "$TMP/exp.after1"
std_run "$TMP/tr5.jsonl" "$TMP/c6.json"
check "2回目: 追加0件" "0" "$(jq_out '.experience.added|length')"
check "2回目: 重複2件を検出" "2" "$(jq_out '.experience.duplicates|length')"
if cmp -s "$EXP" "$TMP/exp.after1"; then ok "2回実行しても EXPERIENCE.md は増えない"; else bad "2回目で EXPERIENCE.md が変化した"; fi
diff_f="$PROP/harness2-e1.diff"
if [[ -f "$diff_f" ]] && grep -q '^--- a/agent/scripts/x.py' "$diff_f" && grep -q '^+++ b/agent/scripts/x.py' "$diff_f"; then
    ok "採用候補の diff が evolve-proposals に出力される"
else bad "採用候補の diff が無い/形式不正: $diff_f"; fi
check "棄却候補の diff は出ない" "false" "$([[ -e "$PROP/harness2-e2.diff" ]] && echo true || echo false)"
check "対象ファイルへは書かない (リポジトリのハッシュ不変)" "$before_hash" "$(repo_hash)"
if command -v patch >/dev/null 2>&1; then
    if patch -p1 --dry-run -s -d "$REPO" <"$diff_f" >/dev/null 2>&1; then ok "出力 diff は patch -p1 で適用可能"; else bad "出力 diff が patch -p1 で適用できない"; fi
fi
fresh_state
command cp "$EXP" "$TMP/exp.dry"
std_run "$TMP/tr5.jsonl" "$TMP/c6.json" --dry-run
check "--dry-run rc=0" "0" "$RC"
check "--dry-run は dry_run=true を報告" "true" "$(jq_out '.dry_run')"
if cmp -s "$EXP" "$TMP/exp.dry"; then ok "--dry-run は EXPERIENCE.md を変更しない"; else bad "--dry-run で EXPERIENCE.md が変化した"; fi
check "--dry-run は out-dir を作らない" "false" "$([[ -e "$PROP" ]] && echo true || echo false)"
fresh_state
run_h2 --traces "$TMP/tr5.jsonl" --candidates "$TMP/c6.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$REPO/agent/out" --security-cmd "bash $TMP/ok.sh" --json
check "保護領域 (repo/agent 配下) への out-dir は rc=2" "2" "$RC"
check_has "保護領域 out-dir のメッセージ" "$(cat "$TMP/err.txt")" "inside"
check "保護領域に何も作られない" "false" "$([[ -e "$REPO/agent/out" ]] && echo true || echo false)"
mkdir -p "$TMP/other"
printf '# x\n' >"$TMP/other/rules.md"
run_h2 --traces "$TMP/tr5.jsonl" --repo-root "$REPO" --experience "$TMP/other/rules.md" --out-dir "$PROP" --json
check "--experience が EXPERIENCE.md 以外なら rc=2" "2" "$RC"
check_has "--experience 拒否メッセージ" "$(cat "$TMP/err.txt")" "EXPERIENCE.md"

# ================================================================ Fail-Closed
section "Fail-Closed: 不正入力は rc=2 と明確なメッセージ (Traceback なし)"
fresh_state
expect_rc2() { # desc needle args...
    local desc="$1" needle="$2"
    shift 2
    run_h2 "$@"
    local err
    err="$(cat "$TMP/err.txt")"
    if [[ "$RC" -eq 2 && "$err" == *"$needle"* && "$err" != *Traceback* ]]; then ok "$desc"; else bad "$desc : rc=$RC needle=[$needle] stderr=[$err]"; fi
}
BASE=(--repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json)
expect_rc2 "引数なし" "required"
expect_rc2 "存在しない traces" "cannot read traces" --traces "$TMP/nope.jsonl" "${BASE[@]}"
printf '%s\n' '{"signature":"s","task":"t","target":"agent/scripts/x.py"}' 'not json' >"$TMP/bad_json.jsonl"
expect_rc2 "不正な JSON (行番号付き)" "invalid JSON at line 2" --traces "$TMP/bad_json.jsonl" "${BASE[@]}"
: >"$TMP/empty.jsonl"
expect_rc2 "空の traces" "is empty" --traces "$TMP/empty.jsonl" "${BASE[@]}"
printf '\n\n' >"$TMP/blank.jsonl"
expect_rc2 "空行のみの traces" "is empty" --traces "$TMP/blank.jsonl" "${BASE[@]}"
printf '%s\n' '{"signature":"s","task":"t","target":"agent/scripts/x.py"}' >"$TMP/noperm.jsonl"
chmod 000 "$TMP/noperm.jsonl"
if [[ -r "$TMP/noperm.jsonl" ]]; then
    echo "[SKIP] 読めないファイル : chmod 000 でも読める実行環境 (root 等)"
else
    expect_rc2 "読めないファイル (chmod 000)" "cannot read traces" --traces "$TMP/noperm.jsonl" "${BASE[@]}"
fi
head -c 1100000 </dev/zero | tr '\0' 'a' >"$TMP/huge.jsonl"
expect_rc2 "巨大な入力ファイル" "exceeds" --traces "$TMP/huge.jsonl" "${BASE[@]}"
yes '{"signature":"s","task":"t","target":"agent/scripts/x.py"}' | head -n 10001 >"$TMP/many.jsonl"
expect_rc2 "トレース件数の上限超過" "more than 10000" --traces "$TMP/many.jsonl" "${BASE[@]}"
printf '%s\n' '{"task":"t","target":"agent/scripts/x.py"}' >"$TMP/no_sig.jsonl"
expect_rc2 "スキーマ違反 (signature 欠落, 行番号付き)" "line 1: 'signature' must be a non-empty string" --traces "$TMP/no_sig.jsonl" "${BASE[@]}"
printf '%s\n' '[1,2]' >"$TMP/not_obj.jsonl"
expect_rc2 "スキーマ違反 (オブジェクトでない)" "must be a JSON object" --traces "$TMP/not_obj.jsonl" "${BASE[@]}"
printf '%s\n' '{"signature":"s","task":"t","target":"../etc/passwd"}' >"$TMP/dotdot.jsonl"
expect_rc2 "トレース target の .. を拒否" "invalid target" --traces "$TMP/dotdot.jsonl" "${BASE[@]}"
printf '%s\n' '{"signature":"s","task":"t","target":"/etc/passwd"}' >"$TMP/abs.jsonl"
expect_rc2 "トレース target の絶対パスを拒否" "invalid target" --traces "$TMP/abs.jsonl" "${BASE[@]}"
expect_rc2 "存在しない candidates" "cannot read candidates" --traces "$TMP/tr3.jsonl" --candidates "$TMP/nope.json" "${BASE[@]}"
printf '{bad' >"$TMP/c_badjson.json"
expect_rc2 "candidates の不正な JSON" "candidates" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c_badjson.json" "${BASE[@]}"
printf '{"a":1}' >"$TMP/c_obj.json"
expect_rc2 "candidates が配列でない" "must be a JSON array" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c_obj.json" "${BASE[@]}"
{ cand d1 "sig b" agent/scripts/x.py "$TMP/t_small"; cand d1 "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c_dup.json"
expect_rc2 "candidate id 重複" "duplicate candidate id" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c_dup.json" "${BASE[@]}"
{ cand "../evil" "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c_id.json"
expect_rc2 "candidate id に不正な文字" "invalid candidate id" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c_id.json" "${BASE[@]}"
{ cand t1 "sig b" ../outside.py "$TMP/t_small"; } | jq -s . >"$TMP/c_tgt.json"
expect_rc2 "candidate target の .. を拒否" "invalid target" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c_tgt.json" "${BASE[@]}"
{ cand pp "sig b" agent/scripts/x.py "$TMP/t_small" '[{"name":"p","before":"yes","after":true}]'; } | jq -s . >"$TMP/c_pr.json"
expect_rc2 "probe のスキーマ違反" "probes" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c_pr.json" "${BASE[@]}"
expect_rc2 "存在しない experience" "cannot read experience" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$TMP/nodir/EXPERIENCE.md" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
expect_rc2 "--min-occurrences 0" "--min-occurrences" --traces "$TMP/tr3.jsonl" --min-occurrences 0 "${BASE[@]}"
ln -s "$TMP/exp.orig" "$REPO/agent/rules/link.md"
{ cand sl "sig b" agent/rules/link.md "$TMP/t_small"; } | jq -s . >"$TMP/c_sl.json"
expect_rc2 "リポジトリ外へ解決される symlink target を拒否" "outside" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c_sl.json" "${BASE[@]}"
rm -f "$REPO/agent/rules/link.md"

# ---------------------------------------------------------------- 制御文字 / サロゲートの注入
section "入力サニタイズ: 制御文字・サロゲートの注入拒否 (rc=2, 副作用なし)"
CTRL_NEEDLE="invisible or surrogate characters"
exp_hash() { sha256sum "$EXP" | cut -d' ' -f1; }
fresh_state
exp0="$(exp_hash)"
CHARS=('\n' '\r' '\t' '\u0000' '\u001b' '\u007f' '\u2028' '\u0085' '\ud800' '\u2029' '\u0090' '\u200b' '\u200e' '\u202e' '\u2066' '\ufeff' '\u2060' '\udb40\udc41' '\ufff9' '\ufe0f' '\udb40\udd00' '\u061c' '\u00ad' '\u180e' '\u206a' '\u2065' '\u3164' '\uffa0' '\u2800' '\u034f' '\ue000')
CNAMES=('LF' 'CR' 'TAB' 'NUL' 'ESC' 'DEL' 'U+2028' 'U+0085' 'lone-surrogate' 'U+2029' 'C1-U+0090' 'ZWSP' 'LRM' 'RLO' 'LRI' 'BOM' 'WJ' 'tag-U+E0041' 'U+FFF9' 'VS16' 'VS17-U+E0100' 'ALM' 'SHY' 'MVS' 'ISS' 'U+2065' 'HANGUL-FILLER' 'HALFWIDTH-HANGUL-FILLER' 'BRAILLE-BLANK' 'CGJ' 'PUA-U+E000')
TR_TPL='{"signature":"sig b","task":"t","target":"agent/scripts/x.py"}'
for fld in signature task target; do
    for i in "${!CHARS[@]}"; do
        c="${CHARS[$i]}"
        case "$fld" in
            signature) line='{"signature":"sig@@b","task":"t","target":"agent/scripts/x.py"}' ;;
            task) line='{"signature":"sig b","task":"t@@","target":"agent/scripts/x.py"}' ;;
            target) line='{"signature":"sig b","task":"t","target":"agent/scripts/x@@.py"}' ;;
        esac
        printf '%s\n%s\n%s\n' "${line%%@@*}$c${line#*@@}" "$TR_TPL" "$TR_TPL" >"$TMP/inj.jsonl"
        expect_rc2 "trace.$fld に ${CNAMES[$i]}" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
    done
done
RAW_CHARS=($'\xe2\x80\xa8' $'\xc2\x85' $'\x0b' $'\x0c' $'\x1e' $'\xe2\x80\x8b' $'\xe2\x80\xae')
RAW_NAMES=('raw U+2028' 'raw U+0085' 'raw VT' 'raw FF' 'raw RS' 'raw ZWSP' 'raw RLO')
# 生の C0 制御文字は JSON 仕様違反として JSON パーサ段階で fail-closed (rc=2)。U+2028/U+0085 は JSON 上は合法なので文字検査で拒否
RAW_NEEDLES=("$CTRL_NEEDLE" "$CTRL_NEEDLE" 'invalid JSON' 'invalid JSON' 'invalid JSON' "$CTRL_NEEDLE" "$CTRL_NEEDLE")
for i in "${!RAW_CHARS[@]}"; do
    printf '{"signature":"sig%sb","task":"t","target":"agent/scripts/x.py"}\n' "${RAW_CHARS[$i]}" >"$TMP/inj.jsonl"
    expect_rc2 "trace.signature に ${RAW_NAMES[$i]} (JSON 文字列内)" "${RAW_NEEDLES[$i]}" --traces "$TMP/inj.jsonl" "${BASE[@]}"
done
printf '{"signature":"sig b","task":"t","target":"agent/scripts/x.py","message":"m\\ud800"}\n' >"$TMP/inj.jsonl"
expect_rc2 "trace.message にサロゲート" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
printf '{"signature":"sig b","task":"t","target":"agent/scripts/x\\n### 0123456789abcdef\\n- pattern: injected\\n- target: agent/rules/r.md","message":"m"}\n' >"$TMP/inj.jsonl"
expect_rc2 "target に偽エントリ見出しを埋め込む" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
C_TPL='[{"id":"x1","signature":"sig b","target":"agent/scripts/x.py","new_text":"zz","probes":[{"name":"p1","before":true,"after":true}]}]'
for fld in id signature target probe new_text; do
    for i in "${!CHARS[@]}"; do
        c="${CHARS[$i]}"
        [[ "$fld" == new_text && ("$i" -eq 0 || "$i" -eq 2) ]] && continue # new_text は LF/TAB のみ許容
        case "$fld" in
            id) body='[{"id":"x@@","signature":"sig b","target":"agent/scripts/x.py","new_text":"zz","probes":[]}]'; needle="invalid candidate id" ;;
            signature) body='[{"id":"x1","signature":"sig@@b","target":"agent/scripts/x.py","new_text":"zz","probes":[]}]'; needle="$CTRL_NEEDLE" ;;
            target) body='[{"id":"x1","signature":"sig b","target":"agent/rules/r@@.md","new_text":"zz","probes":[]}]'; needle="$CTRL_NEEDLE" ;;
            probe) body='[{"id":"x1","signature":"sig b","target":"agent/scripts/x.py","new_text":"zz","probes":[{"name":"p@@","before":true,"after":true}]}]'; needle="$CTRL_NEEDLE" ;;
            new_text) body='[{"id":"x1","signature":"sig b","target":"agent/scripts/x.py","new_text":"z@@z","probes":[]}]'; needle="$CTRL_NEEDLE" ;;
        esac
        printf '%s' "${body%%@@*}$c${body#*@@}" >"$TMP/inj_c.json"
        expect_rc2 "candidate.$fld に ${CNAMES[$i]}" "$needle" --traces "$TMP/tr3.jsonl" --candidates "$TMP/inj_c.json" "${BASE[@]}"
    done
done
printf '[{"id":"x1\\n","signature":"sig b","target":"agent/scripts/x.py","new_text":"zz","probes":[]}]' >"$TMP/inj_c.json"
expect_rc2 "candidate id 末尾の LF ($ アンカーの抜け)" "invalid candidate id" --traces "$TMP/tr3.jsonl" --candidates "$TMP/inj_c.json" "${BASE[@]}"
check "拒否された入力は EXPERIENCE.md を変更しない" "$exp0" "$(exp_hash)"
check "拒否された入力は out-dir を作らない" "false" "$([[ -e "$PROP" ]] && echo true || echo false)"
{ trace_lines "sig b" agent/scripts/x.py 3 3
  printf '{"signature":"sig m","task":"a","target":"agent/scripts/x.py","message":"m\\n### 0123456789abcdef\\n- pattern: x\\u2028- scope: INV"}\n%.0s' 1 2 3; } >"$TMP/msg.jsonl"
fresh_state
run_h2 --traces "$TMP/msg.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "message の改行は無害化されて rc=0" "0" "$RC"
check "message から偽見出しが作られない" "0" "$(grep -c '^### 0123456789abcdef$' "$EXP")"
check "message から偽フィールドが作られない" "0" "$(grep -c '^- pattern: x$' "$EXP")"
check "追加されたエントリ数 (4 + 2)" "6" "$(grep -c '^### [0-9a-f]\{16\}$' "$EXP")"

# ---------------------------------------------------------------- symlink / out-dir
section "symlink 経由の書き込み抜けと --out-dir の保護範囲"
printf 'VICTIM\n' >"$TMP/victim.txt"
printf 'PROTECTED\n' >"$REPO/agent/rules/prot.md"
mkdir -p "$TMP/sl"
ln -s "$TMP/victim.txt" "$TMP/sl/EXPERIENCE.md"
before_hash="$(repo_hash)"
fresh_state
expect_rc2 "--experience が repo 外ファイルへの symlink" "symbolic link" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$TMP/sl/EXPERIENCE.md" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "symlink 先 (repo 外) は変更されない" "VICTIM" "$(cat "$TMP/victim.txt")"
expect_rc2 "--experience が保護パスへの symlink" "symbolic link" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$TMP/sl/EXPERIENCE.md" --out-dir "$PROP" --dry-run --json
rm -f "$TMP/sl/EXPERIENCE.md"
ln -s "$REPO/agent/rules/prot.md" "$TMP/sl/EXPERIENCE.md"
expect_rc2 "保護パスへの symlink を拒否" "symbolic link" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$TMP/sl/EXPERIENCE.md" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "保護パスのファイルは変更されない" "PROTECTED" "$(cat "$REPO/agent/rules/prot.md")"
{ cand e1 "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c9.json"
fresh_state
mkdir -p "$PROP"
ln -s "$TMP/victim.txt" "$PROP/harness2-e1.diff"
std_run "$TMP/tr3.jsonl" "$TMP/c9.json"
check "diff の宛先が symlink でも rc=0" "0" "$RC"
check "事前に置かれた diff symlink の先は上書きされない" "VICTIM" "$(cat "$TMP/victim.txt")"
check "宛先は通常ファイルに置換される" "false" "$([[ -L "$PROP/harness2-e1.diff" ]] && echo true || echo false)"
check_has "置換後の diff に内容がある" "$(cat "$PROP/harness2-e1.diff")" "+++ b/agent/scripts/x.py"
check "一時ファイルが残らない" "0" "$(find "$PROP" -name '.harness2-*' | wc -l | tr -d ' ')"
ln -sfn "$REPO/agent" "$TMP/lnk"
expect_rc2 "out-dir が repo/agent への symlink 配下" "inside" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$TMP/lnk/sub" --security-cmd "bash $TMP/ok.sh" --json
expect_rc2 "out-dir = repo root" "inside" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$REPO" --security-cmd "bash $TMP/ok.sh" --json
expect_rc2 "out-dir = repo 直下のサブディレクトリ" "inside" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$REPO/sub" --security-cmd "bash $TMP/ok.sh" --json
expect_rc2 "out-dir に .. を含み repo root に解決される" "inside" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$REPO/agent/.." --security-cmd "bash $TMP/ok.sh" --json
check "実 repo は変更されない" "$before_hash" "$(repo_hash)"

# ---------------------------------------------------------------- 深い入れ子 / 非原子性 / 並行実行
section "Fail-Closed: 深い入れ子 / 非原子性 / 並行実行"
python3 -I -B -c "import sys; sys.stdout.write('[' * 400000)" >"$TMP/deep.jsonl"
expect_rc2 "深く入れ子の traces は rc=2 (RecursionError を出さない)" "nesting" --traces "$TMP/deep.jsonl" "${BASE[@]}"
expect_rc2 "深く入れ子の candidates は rc=2" "nesting" --traces "$TMP/tr3.jsonl" --candidates "$TMP/deep.jsonl" "${BASE[@]}"
fresh_state
mkdir -p "$PROP/harness2-e1.diff"
exp0="$(exp_hash)"
expect_rc2 "diff の書き込みに失敗すると rc=2" "cannot write proposal" --traces "$TMP/tr5.jsonl" --candidates "$TMP/c9.json" "${BASE[@]}"
check "diff 書き込み失敗時は EXPERIENCE.md を変更しない (非原子性なし)" "$exp0" "$(exp_hash)"
rm -rf "$PROP"
fresh_state
pids=()
for i in $(seq 1 12); do
    python3 -I -B "$H2" "${UNSB[@]}" --traces "$TMP/tr5.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$TMP/pp$i" \
        --security-cmd "bash $TMP/ok.sh" --json >"$TMP/par$i.out" 2>"$TMP/par$i.err" &
    pids+=("$!")
done
prc=0
for p in "${pids[@]}"; do wait "$p" || prc=$((prc + 1)); done
check "並列12実行がすべて rc=0" "0" "$prc"
check "並列実行でも見出しの重複が無い" "0" "$(grep '^### [0-9a-f]\{16\}$' "$EXP" | sort | uniq -d | wc -l | tr -d ' ')"
check "並列実行後のエントリ数 (4 + 2)" "6" "$(grep -c '^### [0-9a-f]\{16\}$' "$EXP")"
check "並列実行後も id が SHA-256 規約に一致" "OK" "$(verify_ids "$EXP" | tail -1)"

section "追加: 最終 fail-closed ハンドラ / 通常ファイルでない EXPERIENCE.md / message の ESC"
python3 -I -B -c "print('{\"signature\":\"s\",\"task\":\"t\",\"target\":\"agent/scripts/x.py\",\"n\":' + '9'*6000 + '}')" >"$TMP/bigint.jsonl"
expect_rc2 "巨大整数 (ValueError) も traceback でなく rc=2" "invalid input" --traces "$TMP/bigint.jsonl" "${BASE[@]}"
mkdir -p "$TMP/dirx/EXPERIENCE.md"
expect_rc2 "--experience が通常ファイルでない (dry-run)" "not a regular file" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" \
    --experience "$TMP/dirx/EXPERIENCE.md" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --dry-run --json
printf '{"signature":"sig e","task":"a","target":"agent/scripts/x.py","message":"m\\u001b[31mred"}\n%.0s' 1 2 3 >"$TMP/esc.jsonl"
fresh_state
run_h2 --traces "$TMP/esc.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "ESC を含む message でも rc=0" "0" "$RC"
check "ESC が EXPERIENCE.md に入らない" "0" "$(grep -c $'\x1b' "$EXP")"
check "ESC を含む message のエントリは追加される" "5" "$(grep -c '^### [0-9a-f]\{16\}$' "$EXP")"

# ================================================================ 試行3
section "試行3-1: new_text の制御文字・不可視文字と diff の行分割"
fresh_state
exp0="$(exp_hash)"
printf '[{"id":"hid","signature":"sig b","target":"agent/scripts/x.py","new_text":"keep\\nHIDDEN\\n\\u001b[1A\\u001b[2K\\n","probes":[]}]' >"$TMP/hid.json"
expect_rc2 "ESC で行を隠す new_text を拒否" "$CTRL_NEEDLE" --traces "$TMP/tr3.jsonl" --candidates "$TMP/hid.json" "${BASE[@]}"
for pair in 'CR:\r' 'VT:\u000b' 'FF:\u000c' 'FS:\u001c' 'GS:\u001d' 'RS:\u001e' 'NEL:\u0085' 'LS: ' 'PS: ' 'C1:\u0090' 'ZWSP:​' 'RLO:‮' 'BOM:﻿'; do
    nm="${pair%%:*}"; ch="${pair#*:}"
    body='[{"id":"nt","signature":"sig b","target":"agent/scripts/x.py","new_text":"a@@b\n","probes":[]}]'
    printf '%s' "${body%%@@*}$ch${body#*@@}" >"$TMP/nt.json"
    expect_rc2 "new_text に $nm" "$CTRL_NEEDLE" --traces "$TMP/tr3.jsonl" --candidates "$TMP/nt.json" "${BASE[@]}"
done
check "拒否された new_text は out-dir/EXPERIENCE.md に影響しない" "false$exp0" "$([[ -e "$PROP" ]] && echo true || echo false)$(exp_hash)"
printf 'a\fb\nc\n' >"$REPO/agent/scripts/ff.py"
printf 'x\tz  \nc\n' >"$TMP/t_tab"
printf 'tail-without-newline' >"$TMP/t_nonl"
{ cand ff1 "sig b" agent/scripts/ff.py "$TMP/t_tab"; cand ff2 "sig b" agent/scripts/x.py "$TMP/t_nonl"; } | jq -s . >"$TMP/c10.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c10.json"
check "ff.py (FF を含む既存ファイル) への候補は採用" "accepted" "$(cstat ff1)"
mkdir -p "$TMP/applied"
rm -rf "$TMP/applied/agent"; cp -r "$REPO/agent" "$TMP/applied/agent"
if patch -p1 -s -d "$TMP/applied" <"$PROP/harness2-ff1.diff" >/dev/null 2>&1 && cmp -s "$TMP/applied/agent/scripts/ff.py" "$TMP/t_tab"; then
    ok "FF を含む既存ファイルの diff が patch で正確に適用される"
else bad "FF を含む既存ファイルの diff が適用できない/結果が不一致"; fi
rm -rf "$TMP/applied/agent"; cp -r "$REPO/agent" "$TMP/applied/agent"
if patch -p1 -s -d "$TMP/applied" <"$PROP/harness2-ff2.diff" >/dev/null 2>&1 && cmp -s "$TMP/applied/agent/scripts/x.py" "$TMP/t_nonl"; then
    ok "末尾改行なしの new_text の diff が patch で正確に適用される"
else bad "末尾改行なしの new_text の diff が適用できない/結果が不一致"; fi
check "diff は 0600" "600" "$(stat -c %a "$PROP/harness2-ff1.diff")"
for ch in '​' '‮' '﻿' '￹' '󠁁' '⁦'; do
    printf '{"signature":"sig b","task":"t","target":"agent/scripts/x.py","message":"m%sx"}\n' "$ch" >"$TMP/inj.jsonl"
    expect_rc2 "trace.message に不可視/双方向文字 $ch" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
done

section "試行3-2: SKILL.md description の YAML 意味論"
P50="$(chars 50 p)"; Q50="$(chars 50 q)"; L100="$(chars 100 p)"; L56="$(chars 56 q)"; L60="$(chars 60 q)"
blank150="$(printf '\\n%.0s' $(seq 1 150))"
skill_fm "$TMP/g_blank" "name: foo\ndescription: |\n  $P50\n${blank150}  $Q50\n"
skill_fm "$TMP/g_trailblank" "name: foo\ndescription: |\n  $P50\n\n\nlicense: x\n"
skill_fm "$TMP/g_xindent_lit" "name: foo\ndescription: |\n  $L100\n      $L56\n"
skill_fm "$TMP/g_xindent_fold" "name: foo\ndescription: >\n  $P50\n    $Q50\n"
skill_fm "$TMP/g_map" "name: foo\ndescription:\n  a: b\n"
skill_fm "$TMP/g_list" "name: foo\ndescription:\n  - x\n"
skill_fm "$TMP/g_tab" "name: foo\ndescription: $P50\n\t$Q50\n"
skill_fm "$TMP/g_tab2" "name: foo\ndescription: $P50\n  \t$Q50\n"
skill_fm "$TMP/g_colon" "name: foo\ndescription: $P50\n  word: $Q50\n"
skill_fm "$TMP/g_indicator" "name: foo\ndescription: |2\n    $P50\n"
skill_fm "$TMP/g_jitter" "name: foo\ndescription: $P50\n  $Q50\n      $P50\n"
{
    cand sb "sig b" agent/skills/foo/SKILL.md "$TMP/g_blank"
    cand st "sig b" agent/skills/foo/SKILL.md "$TMP/g_trailblank"
    cand sl "sig b" agent/skills/foo/SKILL.md "$TMP/g_xindent_lit"
    cand sf "sig b" agent/skills/foo/SKILL.md "$TMP/g_xindent_fold"
    cand sm "sig b" agent/skills/foo/SKILL.md "$TMP/g_map"
    cand ss "sig b" agent/skills/foo/SKILL.md "$TMP/g_list"
    cand sa "sig b" agent/skills/foo/SKILL.md "$TMP/g_tab"
    cand sa2 "sig b" agent/skills/foo/SKILL.md "$TMP/g_tab2"
    cand sc "sig b" agent/skills/foo/SKILL.md "$TMP/g_colon"
    cand si "sig b" agent/skills/foo/SKILL.md "$TMP/g_indicator"
    cand sj "sig b" agent/skills/foo/SKILL.md "$TMP/g_jitter"
} | jq -s . >"$TMP/c11.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c11.json"
check "literal ブロック内の空行パディングは棄却 (曖昧)" "skill_frontmatter" "$(creason sb)"
check "ブロック末尾の空行のみは採用" "accepted" "$(cstat st)"
check "literal の追加インデントは保って測る (161文字)" "skill_description" "$(creason sl)"
check "folded の追加インデントは棄却 (曖昧)" "skill_frontmatter" "$(creason sf)"
check "入れ子 mapping 値は棄却" "skill_frontmatter" "$(creason sm)"
check "sequence 値は棄却" "skill_frontmatter" "$(creason ss)"
check "タブ継続行は棄却" "skill_frontmatter" "$(creason sa)"
check "空白+タブ継続行は棄却" "skill_frontmatter" "$(creason sa2)"
check "継続行の ': ' は棄却 (mapping に化ける)" "skill_frontmatter" "$(creason sc)"
check "明示インデント指示子 |2 は棄却" "skill_frontmatter" "$(creason si)"
check "plain 継続行のインデント揺れは連結長で測る (採用: 152文字)" "accepted" "$(cstat sj)"

section "試行3-3: preflight / 部分書き込みの巻き戻し / 人間向け警告"
{ cand pf "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c12.json"
mkdir -p "$TMP/badexp" "$TMP/fifo"
printf '\xff\xfe broken\n' >"$TMP/badexp/EXPERIENCE.md"
rm -rf "$PROP"
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c12.json" --repo-root "$REPO" --experience "$TMP/badexp/EXPERIENCE.md" \
    --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "不正 UTF-8 の EXPERIENCE.md は rc=2" "2" "$RC"
check_has "不正 UTF-8 のメッセージ" "$(cat "$TMP/err.txt")" "not valid UTF-8"
check "不正 UTF-8 なら diff を一切書かない (preflight)" "false" "$([[ -e "$PROP" ]] && echo true || echo false)"
rm -rf "$PROP"
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c12.json" --repo-root "$REPO" --experience "$TMP/sl/EXPERIENCE.md" \
    --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "symlink の EXPERIENCE.md は rc=2 (候補あり)" "2" "$RC"
check "symlink なら diff を一切書かない (preflight)" "false" "$([[ -e "$PROP" ]] && echo true || echo false)"
rm -f "$TMP/fifo/EXPERIENCE.md"; mkfifo "$TMP/fifo/EXPERIENCE.md"
rm -rf "$PROP"
timeout 20 python3 -I -B "$H2" "${UNSB[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c12.json" --repo-root "$REPO" --experience "$TMP/fifo/EXPERIENCE.md" \
    --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
RC=$?
check "FIFO の EXPERIENCE.md は hang せず rc=2" "2" "$RC"
check_has "FIFO のメッセージ" "$(cat "$TMP/err.txt")" "not a regular file"
timeout 20 python3 -I -B "$H2" "${UNSB[@]}" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" --experience "$TMP/fifo/EXPERIENCE.md" \
    --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --dry-run --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check "FIFO の EXPERIENCE.md は dry-run (O_RDONLY) でも hang せず rc=2" "2" "$?"
check "FIFO なら diff を一切書かない" "false" "$([[ -e "$PROP" ]] && echo true || echo false)"
# 部分書き込み: RLIMIT_FSIZE で追記の途中に EFBIG を起こし、元の長さに戻ることを確認
mkdir -p "$TMP/small"
{ printf '# small\n'; head -c 960 </dev/zero | tr '\0' '.'; printf '\n'; } >"$TMP/small/EXPERIENCE.md"
command cp "$TMP/small/EXPERIENCE.md" "$TMP/small.orig"
rm -rf "$PROP"
( ulimit -f 1; python3 -I -B "$H2" "${UNSB[@]}" --traces "$TMP/tr5.jsonl" --repo-root "$REPO" --experience "$TMP/small/EXPERIENCE.md" \
    --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json >"$TMP/out.txt" 2>"$TMP/err.txt"; echo $? >"$TMP/rc.txt" )
check "追記が部分書き込みで失敗すると rc=2" "2" "$(cat "$TMP/rc.txt")"
check_has "部分書き込み失敗のメッセージ" "$(cat "$TMP/err.txt")" "cannot append"
if cmp -s "$TMP/small/EXPERIENCE.md" "$TMP/small.orig"; then ok "部分書き込みは ftruncate で元の長さ・内容に戻る"; else bad "部分書き込みの残骸が残った: $(wc -c <"$TMP/small/EXPERIENCE.md") bytes"; fi
fresh_state
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/c12.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh"
check_has "上書き時は人間向け出力にも警告を出す" "$(cat "$TMP/out.txt")" "WARNING: security gate overridden"
check_has "警告にコマンドが含まれる" "$(cat "$TMP/out.txt")" "$TMP/ok.sh"
fresh_state
env -u HARNESS2_SECURITY_CMDS python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --dry-run >"$TMP/out.txt" 2>"$TMP/err.txt"
check "既定 gate なら警告を出さない" "0" "$(grep -c 'WARNING' "$TMP/out.txt")"

section "試行3-4: SIGTERM の後始末 / 相対 --repo-root / gate の環境 allowlist"
cat >"$TMP/hang.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "$HARNESS2_REPO_ROOT" != "$HARNESS2_TEST_REAL" ]]; then
    echo "$HARNESS2_REPO_ROOT" >"$HARNESS2_TEST_TMP/hang.root"
    sleep 300 &
    echo $! >"$HARNESS2_TEST_TMP/hang.child"
    wait
fi
EOF
export HARNESS2_TEST_REAL="$REPO"
rm -f "$TMP/hang.root" "$TMP/hang.child"
fresh_state
exp0="$(exp_hash)"
python3 -I -B "$H2" "${UNSB[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c12.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/hang.sh" --json >"$TMP/out.txt" 2>"$TMP/err.txt" &
pypid=$!
for _ in $(seq 1 100); do [[ -s "$TMP/hang.child" ]] && break; sleep 0.1; done
copy_root="$(cat "$TMP/hang.root" 2>/dev/null)"
child="$(cat "$TMP/hang.child" 2>/dev/null)"
kill -TERM "$pypid" 2>/dev/null
wait "$pypid"; sig_rc=$?
check "SIGTERM で 128+15=143 で終了" "143" "$sig_rc"
alive=false; for _ in $(seq 1 30); do kill -0 "$child" 2>/dev/null && sleep 0.1 || { alive=done; break; }; done
check "gate の子プロセスが孤児として残らない" "done" "$alive"
check "gate の複製が削除される" "false" "$([[ -n "$copy_root" && -e "$copy_root" ]] && echo true || echo false)"
check "SIGTERM 時も EXPERIENCE.md は不変" "$exp0" "$(exp_hash)"
[[ "${child:-}" ]] && kill -KILL "$child" 2>/dev/null
rm -f "$TMP/roots.log"; : >"$TMP/roots.log"
fresh_state
( cd "$TMP" && python3 -I -B "$H2" "${UNSB[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c12.json" --repo-root repo --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/rootarg.sh {root}" --json >"$TMP/out.txt" 2>"$TMP/err.txt" )
check "相対 --repo-root は絶対パスに解決される (baseline)" "$REPO" "$(head -1 "$TMP/roots.log")"
check "相対 --repo-root でも候補 gate が通る" "accepted" "$(cstat pf)"
cat >"$TMP/envdump.sh" <<'EOF'
#!/usr/bin/env bash
env >"$HARNESS2_TEST_TMP/gate.env"
EOF
fresh_state
AWS_SECRET_ACCESS_KEY=topsecret SOME_API_TOKEN=tok run_h2 --traces "$TMP/tr3.jsonl" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "bash $TMP/envdump.sh" --candidates "$TMP/c12.json" --json
check "gate には PATH が渡る" "1" "$(grep -c '^PATH=' "$TMP/gate.env")"
check "gate には HARNESS2_REPO_ROOT が渡る" "1" "$(grep -c '^HARNESS2_REPO_ROOT=' "$TMP/gate.env")"
check "gate には PYTHONDONTWRITEBYTECODE=1 が渡る" "1" "$(grep -c '^PYTHONDONTWRITEBYTECODE=1$' "$TMP/gate.env")"
check "gate に秘密の環境変数は渡らない" "0" "$(grep -c 'AWS_SECRET_ACCESS_KEY\|SOME_API_TOKEN' "$TMP/gate.env")"

# ================================================================ 試行4
section "試行4-1: description の chomping / 空白のみ行 / バックスラッシュ"
blanks() { local n="$1" i; for ((i = 0; i < n; i++)); do printf '\\n'; done; }
for ind in '|+' '>+'; do
    for n in 0 1 5 300; do
        [[ "$ind" == '|+' ]] && id="klit$n" || id="kfold$n"
        skill_fm "$TMP/h_$id" "name: foo\ndescription: $ind\n  $P50\n$(blanks "$n")"
        cand "$id" "sig b" agent/skills/foo/SKILL.md "$TMP/h_$id"
    done
done >"$TMP/h_keep.stream"
for ind in '|' '>'; do
    for n in 0 1 5 300; do
        [[ "$ind" == '|' ]] && id="clit$n" || id="cfold$n"
        skill_fm "$TMP/h_$id" "name: foo\ndescription: $ind\n  $P50\n$(blanks "$n")"
        cand "$id" "sig b" agent/skills/foo/SKILL.md "$TMP/h_$id"
    done
done >"$TMP/h_clip.stream"
A159="$(chars 159 a)"; A160="$(chars 160 a)"
skill_fm "$TMP/h_l159" "name: foo\ndescription: |\n  $A159\n"
skill_fm "$TMP/h_l160" "name: foo\ndescription: |\n  $A160\n"
skill_fm "$TMP/h_l160s" "name: foo\ndescription: |-\n  $A160\n"
skill_fm "$TMP/h_f159" "name: foo\ndescription: >\n  $A159\n"
skill_fm "$TMP/h_f160" "name: foo\ndescription: >\n  $A160\n"
skill_fm "$TMP/h_f160s" "name: foo\ndescription: >-\n  $A160\n"
ws102="$(printf ' %.0s' $(seq 1 102))"
wsbody=""; for ((i = 0; i < 8; i++)); do wsbody+="${ws102}\n"; done  # 8行 (トークン予算を超えない大きさ) で空白のみ行ガードだけを検査
skill_fm "$TMP/h_wsmany" "name: foo\ndescription: |\n  $P50\n$wsbody"
skill_fm "$TMP/h_wsone" "name: foo\ndescription: |\n  $P50\n  \n"
printf -- '---\nname: foo\ndescription: "a\\u2028b"\n---\nbody\n' >"$TMP/h_bs1"
printf -- '---\nname: foo\ndescription: "a\\nb"\n---\nbody\n' >"$TMP/h_bs2"
printf -- '---\nname: foo\ndescription: C:\\path\n---\nbody\n' >"$TMP/h_bs3"
printf -- '---\nname: foo\ndescription: plain ok\n---\nbody\n' >"$TMP/h_plainok"
{
    cat "$TMP/h_keep.stream" "$TMP/h_clip.stream"
    cand l159 "sig b" agent/skills/foo/SKILL.md "$TMP/h_l159"
    cand l160 "sig b" agent/skills/foo/SKILL.md "$TMP/h_l160"
    cand l160s "sig b" agent/skills/foo/SKILL.md "$TMP/h_l160s"
    cand f159 "sig b" agent/skills/foo/SKILL.md "$TMP/h_f159"
    cand f160 "sig b" agent/skills/foo/SKILL.md "$TMP/h_f160"
    cand f160s "sig b" agent/skills/foo/SKILL.md "$TMP/h_f160s"
    cand wsm "sig b" agent/skills/foo/SKILL.md "$TMP/h_wsmany"
    cand wso "sig b" agent/skills/foo/SKILL.md "$TMP/h_wsone"
    cand bs1 "sig b" agent/skills/foo/SKILL.md "$TMP/h_bs1"
    cand bs2 "sig b" agent/skills/foo/SKILL.md "$TMP/h_bs2"
    cand bs3 "sig b" agent/skills/foo/SKILL.md "$TMP/h_bs3"
    cand pok "sig b" agent/skills/foo/SKILL.md "$TMP/h_plainok"
} | jq -s . >"$TMP/c13.json"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c13.json"
check "chomping keep (|+) は末尾空行 0/1/5/300 のすべてで棄却" "skill_frontmatter,skill_frontmatter,skill_frontmatter,skill_frontmatter" \
    "$(creason klit0),$(creason klit1),$(creason klit5),$(creason klit300)"
check "chomping keep (>+) は末尾空行 0/1/5/300 のすべてで棄却" "skill_frontmatter,skill_frontmatter,skill_frontmatter,skill_frontmatter" \
    "$(creason kfold0),$(creason kfold1),$(creason kfold5),$(creason kfold300)"
check "clip (|) は末尾の空行を数えず採用 (0/1/5/300)" "accepted,accepted,accepted,accepted" \
    "$(cstat clit0),$(cstat clit1),$(cstat clit5),$(cstat clit300)"
check "clip (>) は末尾の空行を数えず採用 (0/1/5/300)" "accepted,accepted,accepted,accepted" \
    "$(cstat cfold0),$(cstat cfold1),$(cstat cfold5),$(cstat cfold300)"
check "| clip 159文字 (+末尾改行1 = 160) は採用" "accepted" "$(cstat l159)"
check "| clip 160文字 (+末尾改行1 = 161) は棄却" "skill_description" "$(creason l160)"
check "|- strip 160文字は採用" "accepted" "$(cstat l160s)"
check "> clip 159文字は採用" "accepted" "$(cstat f159)"
check "> clip 160文字 (+末尾改行1) は棄却" "skill_description" "$(creason f160)"
check ">- strip 160文字は採用" "accepted" "$(cstat f160s)"
check "block 内の空白のみ行 (102空白 x8) は棄却" "skill_frontmatter" "$(creason wsm)"
check "block 末尾の空白のみ行は棄却" "skill_frontmatter" "$(creason wso)"
check "description の \\u エスケープ (クォート内) は棄却" "skill_frontmatter" "$(creason bs1)"
check "description の \\n エスケープは棄却" "skill_frontmatter" "$(creason bs2)"
check "description のバックスラッシュ (plain) は棄却" "skill_frontmatter" "$(creason bs3)"
check "通常の plain description は採用" "accepted" "$(cstat pok)"
fz="$(python3 -I -B - "$H2" "$ROOT" 2>&1 <<'PY'
import importlib.util, random, sys, glob
spec = importlib.util.spec_from_file_location("h2", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = sorted(glob.glob(sys.argv[2] + "/agent/skills/*/SKILL.md"))
badreal = [f for f in real if (d := m.skill_description(open(f, encoding="utf-8").read())) is None or len(d) > 160]
try:
    import yaml
except ImportError:
    yaml = None
rnd = random.Random(20261120)
STY = ["", "|", "|-", "|+", ">", ">-", ">+", "'", '"']
def gen():
    sty = rnd.choice(STY); ind = " " * rnd.choice([1, 2, 2, 2, 3, 4])
    words = lambda: " ".join("w" * rnd.randint(1, 12) for _ in range(rnd.randint(1, 8)))
    lines = []
    if sty in ("'", '"'):
        first = sty + words(); more = [ind + words() for _ in range(rnd.randint(0, 2))]
        if more: more[-1] += sty
        else: first += sty
        head = "description: " + first; body = more
    elif sty == "":
        head = "description: " + words(); body = [ind + words() for _ in range(rnd.randint(0, 3))]
    else:
        head = "description: " + sty; body = [ind + words() for _ in range(rnd.randint(0, 3))]
    for _ in range(rnd.randint(0, 3)):
        pos = rnd.randint(0, len(body)); body.insert(pos, rnd.choice(["", "", " ", ind, ind + " ", "   " * 3, "\t"]))
    for _ in range(rnd.choice([0, 0, 1, 2, 5, 40])):
        body.append(rnd.choice(["", "", ind]))
    if rnd.random() < 0.3 and body: body[rnd.randrange(len(body))] = " " * rnd.randint(0, 8) + words()
    pre = ["name: foo"]; post = rnd.choice([[], ["license: x"], ["tools:", "  - a"]])
    return "\n".join(["---"] + pre + [head] + body + post + ["---", "body", ""])
cmp_n = viol = 0; ex = []
for i in range(6000):
    t = gen(); ours = m.skill_description(t)
    if yaml is None or ours is None: continue
    fm = "\n".join(t.split("\n")[1:t.split("\n").index("---", 1)]) + "\n"
    try: d = yaml.safe_load(fm)
    except yaml.YAMLError: continue
    yd = d.get("description") if isinstance(d, dict) else None
    if not isinstance(yd, str): continue
    cmp_n += 1
    if len(ours) < len(yd):
        viol += 1; ex.append((len(ours), len(yd), t[:120]))
print("REAL_BAD=%d YAML=%s COMPARED=%d VIOLATIONS=%d %s" % (len(badreal), "yes" if yaml else "no", cmp_n, viol, ex[:2]))
PY
)"
echo "$fz" | tail -1
check "実 agent/skills/*/SKILL.md 34件が全て通る" "REAL_BAD=0" "$(echo "$fz" | tail -1 | grep -o 'REAL_BAD=[0-9]*')"
if [[ "$fz" == *"YAML=yes"* ]]; then
    check "PyYAML との突き合わせで過少計測が 0 件 (乱数 fuzz)" "VIOLATIONS=0" "$(echo "$fz" | tail -1 | grep -o 'VIOLATIONS=[0-9]*')"
    cmpn="$(echo "$fz" | tail -1 | grep -o 'COMPARED=[0-9]*' | cut -d= -f2)"
    check "fuzz の比較件数が十分 (>= 500)" "true" "$([[ "${cmpn:-0}" -ge 500 ]] && echo true || echo false)"
else echo "[SKIP] PyYAML が無い環境: fuzz 突き合わせをスキップ"; fi

section "試行4-2: 不可視文字 (variation selector / PUA 等) と target 許可リスト"
for ch in '\ufe0f' '\udb40\udd00' '\u061c' '\u00ad' '\u180e' '\u206a' '\u2065' '\u3164' '\uffa0' '\u2800' '\u034f' '\ue000' '\uf8ff'; do
    printf '{"signature":"sig%sb","task":"t","target":"agent/scripts/x.py","message":"m%sx"}\n' "$ch" "$ch" >"$TMP/inj.jsonl"
    expect_rc2 "signature に不可視文字 $ch" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
    printf '{"signature":"sig b","task":"t","target":"agent/scripts/x.py","message":"m%sx"}\n' "$ch" >"$TMP/inj.jsonl"
    expect_rc2 "message に不可視文字 $ch" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
    printf '[{"id":"nt","signature":"sig b","target":"agent/scripts/x.py","new_text":"a%sb\\n","probes":[]}]' "$ch" >"$TMP/nt.json"
    expect_rc2 "new_text に不可視文字 $ch" "$CTRL_NEEDLE" --traces "$TMP/tr3.jsonl" --candidates "$TMP/nt.json" "${BASE[@]}"
done
for pair in 'space: ' 'quote:\u0027' 'dquote:\"' 'backslash:\\\\' 'star:*' 'qmark:?' 'semi:;' 'dollar:$' 'paren:(' 'amp:&' 'pipe:|' 'lt:<' 'gt:>' 'tilde:~' 'hash:#' 'pct:%' 'bang:!' 'brace:{' 'bracket:[' 'backtick:`' 'eq:=' 'comma:,' 'colon::'; do
    nm="${pair%%:*}"; ch="${pair#*:}"
    printf '{"signature":"sig b","task":"t","target":"agent/agents/foo%s.md"}\n' "$ch" >"$TMP/inj.jsonl"
    expect_rc2 "trace.target に $nm" "invalid target" --traces "$TMP/inj.jsonl" "${BASE[@]}"
    printf '[{"id":"tg","signature":"sig b","target":"agent/agents/foo%s.md","new_text":"z\\n","probes":[]}]' "$ch" >"$TMP/nt.json"
    expect_rc2 "candidate.target に $nm" "invalid target" --traces "$TMP/tr3.jsonl" --candidates "$TMP/nt.json" "${BASE[@]}"
done
badnames="$(cd "$ROOT" && find agent -type f -not -path '*/node_modules/*' -not -path '*/__pycache__/*' | grep -vcE '^[A-Za-z0-9._/@+-]+$' || true)"
check "実在する agent/ 配下の全ファイル名が許可リストに合う" "0" "$badnames"

section "試行4-3: 上書き警告は stderr にも (--json でも) 出し、制御文字をエスケープする"
fresh_state
python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" \
    --security-cmd "bash $TMP/ok.sh" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check_has "--json でも stderr に上書き警告" "$(cat "$TMP/err.txt")" "WARNING: security gate overridden"
check "JSON の warnings に上書き警告が入る" "true" "$(jq_out '[.warnings[]|select(contains("security gate overridden"))]|length>0')"
fresh_state
python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" \
    --security-cmd $'true\x1b[31m' --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check "警告の stderr に生の ESC が出ない" "0" "$(grep -c $'\x1b' "$TMP/err.txt")"
check_has "警告ではコマンドの制御文字がエスケープされる" "$(cat "$TMP/err.txt")" '\u001b'
fresh_state
python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" \
    --security-cmd $'true\x1b[31m' >"$TMP/out.txt" 2>"$TMP/err.txt"
check "人間向け stdout にも生の ESC が出ない" "0" "$(grep -c $'\x1b' "$TMP/out.txt")"

# ---------------------------------------------------------------- sandbox
section "試行4-4: 候補ごとの gate は bwrap で隔離される (隔離できなければ fail-closed)"
printf 'import sys\nsys.exit(0)\n' >"$REPO/agent/scripts/evil.py"
mkdir -p "$TMP/outside" "$TMP/nobin" "$TMP/failbin"
printf '#!/bin/sh\nexit 1\n' >"$TMP/failbin/bwrap"; chmod +x "$TMP/failbin/bwrap"
{ cand sbp "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c14.json"
fresh_state
python3 -I -B "$H2" --gate-empty-proc --traces "$TMP/tr3.jsonl" --candidates "$TMP/c14.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "/usr/bin/true" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
sb_rc=$?
if [[ "$sb_rc" -eq 0 && "$(jq_out '.security_gate.sandbox')" == bwrap* ]]; then
    check "隔離下の gate は sandbox=bwrap を報告" "true" "$(jq_out '.security_gate.sandbox|startswith("bwrap")')"
    MARK="$TMP/outside/marker"
    port_file="$TMP/listener.port"; : >"$TMP/conn.log"; rm -f "$port_file"
    python3 -I -B - "$port_file" "$TMP/conn.log" <<'PY' &
import socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(5)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
while True:
    c, _ = s.accept()
    open(sys.argv[2], "a").write("c")
    c.close()
PY
    lpid=$!
    for _ in $(seq 1 50); do [[ -s "$port_file" ]] && break; sleep 0.1; done
    PORT="$(cat "$port_file")"
    python3 -I -B - "$TMP/evil_new.py" "$MARK" "$PORT" <<'PY'
import sys
out, mark, port = sys.argv[1:4]
code = f'''import os, socket, sys
wrote = False
for t in ({mark!r}, "/usr/h2marker", "/etc/h2marker"):
    try:
        open(t, "w").write("x"); wrote = True
    except OSError:
        pass
try:
    socket.create_connection(("127.0.0.1", {int(port)}), timeout=2); wrote = True
except OSError:
    pass
sys.exit(1 if wrote else 0)
'''
open(out, "w").write(code)
PY
    { cand ev "sig b" agent/scripts/evil.py "$TMP/evil_new.py"; } | jq -s . >"$TMP/c15.json"
    fresh_state
    python3 -I -B "$H2" --gate-empty-proc --traces "$TMP/tr3.jsonl" --candidates "$TMP/c15.json" --repo-root "$REPO" --experience "$EXP" \
        --out-dir "$PROP" --security-cmd "python3 {root}/agent/scripts/evil.py" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
    check "隔離下: 候補コードの外部書き込みはすべて拒否され gate を通る" "accepted" "$(cstat ev)"
    check "隔離下: 複製の外にマーカーが作られない" "false" "$([[ -e "$MARK" ]] && echo true || echo false)"
    check "隔離下: /usr /etc への書き込みも拒否される" "false" "$([[ -e /usr/h2marker || -e /etc/h2marker ]] && echo true || echo false)"
    check "隔離下: ネットワーク接続は拒否される (listener に届かない)" "0" "$(wc -c <"$TMP/conn.log" | tr -d ' ')"
    fresh_state
    python3 -I -B "$H2" --allow-unsandboxed-gate --traces "$TMP/tr3.jsonl" --candidates "$TMP/c15.json" --repo-root "$REPO" \
        --experience "$EXP" --out-dir "$PROP" --security-cmd "python3 {root}/agent/scripts/evil.py" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
    check "対照: 隔離なしなら同じコードが書き込めて棄却される" "security_gate" "$(creason ev)"
    check "対照: 隔離なしでは実際にマーカーが作られる (テストの感度)" "true" "$([[ -e "$MARK" ]] && echo true || echo false)"
    check "対照: 隔離なしでは listener に接続できる" "true" "$([[ "$(wc -c <"$TMP/conn.log" | tr -d ' ')" -ge 1 ]] && echo true || echo false)"
    rm -f "$MARK"
    kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null
    # 既定 gate 2 本が隔離下でそのまま通る (実 tree)。fresh procfs を拒否する環境 (空 /proc では bun が動かない) では fail-closed
    { cand rp "sig b" agent/scripts/h2_sandbox_probe.py "$TMP/t_small"; } | jq -s . >"$TMP/c16.json"
    fresh_state
    env -u HARNESS2_SECURITY_CMDS python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c16.json" --repo-root "$ROOT" \
        --experience "$EXP" --out-dir "$PROP" --dry-run --json >"$TMP/out.txt" 2>"$TMP/err.txt"
    if [[ "$?" -eq 2 ]]; then
        check_has "この環境は fresh procfs を拒否: 既定 gate は fail-closed" "$(cat "$TMP/err.txt")" "refuses a fresh procfs"
        echo "[SKIP] 既定 gate 2 本の隔離下通過: この環境は --proc を拒否する (空 /proc では bun が動かない)"
    else
        check "既定 gate 2 本が隔離下でそのまま通る (baseline)" "true" "$(jq_out '.security_gate.ok')"
        check "既定 gate 2 本が隔離下で候補を通す" "accepted" "$(cstat rp)"
        check "既定 gate は bwrap 隔離で走る" "bwrap" "$(jq_out '.security_gate.sandbox')"
    fi
    # 隔離の中身: /usr /etc は read-only、baseline は ro・候補の複製は rw、環境は clearenv + 固定値
    export HARNESS2_TEST_REAL="$REPO"  # ホストにだけ存在する HARNESS2_* (隔離内へ転送されないことを probe が確認する)
    cat >"$REPO/agent/scripts/probe.py" <<'PYEOF'
import os, sys
root = sys.argv[1]
ro = lambda p: bool(os.statvfs(p).f_flag & os.ST_RDONLY)
ok = ro("/usr") and ro("/etc")
ok = ok and (ro(root) == (root == sys.argv[2]))
ok = ok and not any(k.startswith("HARNESS2_TEST") for k in os.environ)  # ホストの HARNESS2_* は転送されない
ok = ok and "USER" not in os.environ and "LOGNAME" not in os.environ
ok = ok and os.environ.get("HOME") == "/tmp/home" and os.environ.get("PATH") == "/usr/local/bin:/usr/bin:/bin"
sys.exit(0 if ok else 1)
PYEOF
    fresh_state
    USER=h2user LOGNAME=h2user python3 -I -B "$H2" --gate-empty-proc --traces "$TMP/tr3.jsonl" --candidates "$TMP/c14.json" --repo-root "$REPO" --experience "$EXP" \
        --out-dir "$PROP" --security-cmd "python3 {root}/agent/scripts/probe.py {root} $REPO" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
    check "隔離の中身: /usr・/etc は ro、baseline は ro、複製は rw、環境は clearenv 後の固定値 (baseline)" "true" "$(jq_out '.security_gate.ok')"
    check "隔離の中身 (候補の複製)" "accepted" "$(cstat sbp)"
else
    echo "[SKIP] bwrap が使えない環境 (rc=$sb_rc): 隔離の実機テストをスキップ"
    if [[ "$(cat "$TMP/err.txt")" == *"cannot create a gate sandbox"* ]]; then ok "隔離を作れない環境では fail-closed (rc=$sb_rc)"; else bad "bwrap 不在でも fail-closed にならない: $(cat "$TMP/err.txt")"; fi
fi
fresh_state
exp0="$(exp_hash)"
env PATH="$TMP/nobin" /usr/bin/python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c14.json" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$PROP" --security-cmd "/usr/bin/true" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check "bwrap が PATH に無ければ rc=2" "2" "$?"
check_has "bwrap 不在のメッセージ" "$(cat "$TMP/err.txt")" "cannot create a gate sandbox"
check_has "メッセージが --allow-unsandboxed-gate に言及する" "$(cat "$TMP/err.txt")" "--allow-unsandboxed-gate"
check "隔離できなければ diff を書かない" "false" "$([[ -e "$PROP" ]] && echo true || echo false)"
check "隔離できなければ EXPERIENCE.md を変更しない" "$exp0" "$(exp_hash)"
env PATH="$TMP/failbin" /usr/bin/python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c14.json" --repo-root "$REPO" \
    --experience "$EXP" --out-dir "$PROP" --security-cmd "/usr/bin/true" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check "bwrap が動かない (user namespace 不可) 環境でも rc=2" "2" "$?"
check_has "動かない bwrap のメッセージ" "$(cat "$TMP/err.txt")" "cannot create a gate sandbox"
env PATH="$TMP/failbin" /usr/bin/python3 -I -B "$H2" --allow-unsandboxed-gate --traces "$TMP/tr3.jsonl" --candidates "$TMP/c14.json" \
    --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" --security-cmd "/usr/bin/bash $TMP/ok.sh" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check "--allow-unsandboxed-gate なら従来どおり走る" "accepted" "$(cstat sbp)"
check "sandbox=none を JSON に報告" "true" "$(jq_out '.security_gate.sandbox|startswith("none")')"
check_has "隔離なし実行の警告が stderr に出る" "$(cat "$TMP/err.txt")" "WITHOUT isolation"
check "隔離なし実行の警告が JSON warnings にも入る" "true" "$(jq_out '[.warnings[]|select(contains("WITHOUT isolation"))]|length>0')"
check "隔離テスト後に gate の複製が残らない" "0" "$(ls -d "$TMPDIR"/harness2-gate-* 2>/dev/null | wc -l | tr -d ' ')"
leftover="$(pgrep -u "$(id -u)" -af "$TMP" | grep -v "pgrep" | cut -c1-160)"
check "隔離テスト後にプロセスが残らない" "" "$leftover"

section "試行4-5: PyYAML 突き合わせの配線"
if python3 -I -c 'import yaml' 2>/dev/null; then
    yu="$(python3 -I -B - "$H2" <<'PY'
import importlib.util, sys, tempfile
from pathlib import Path
spec = importlib.util.spec_from_file_location("h2", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
long = "---\nname: foo\ndescription: " + "x" * 400 + "\n---\nbody\n"
a = m.yaml_undermeasured(long, 10)
b = m.yaml_undermeasured(long, 400)
c = m.yaml_undermeasured("---\ndescription: a: b\n---\n", 4)
d = m.yaml_undermeasured("---\ndescription: 123\n---\n", 3)
m.skill_description = lambda t: "short"  # 読み取り側のバグを模擬
with tempfile.TemporaryDirectory() as td:
    cand = {"id": "x", "signature": "s", "target": "agent/skills/foo/SKILL.md", "new_text": long, "probes": [{"name": "p", "before": True, "after": True}]}
    r = m.evaluate(cand, {"s": {"scope": "INV"}}, Path(td), "seed", lambda c: None)
print(a, b, c, d, "skill_frontmatter" in r["reasons"])
PY
)"
    check "yaml_undermeasured: 過少計測 / 一致 / 構文エラー / 非文字列 / evaluate への配線" "True False True True True" "$yu"
    skill_fm "$TMP/y_colon" "name: foo\ndescription: abc: def\n"
    { cand yc "sig b" agent/skills/foo/SKILL.md "$TMP/y_colon"; } | jq -s . >"$TMP/c17.json"
    fresh_state
    std_run "$TMP/tr3.jsonl" "$TMP/c17.json"
    check "YAML が構文エラーにする description は棄却 (独自 reader が通しても)" "skill_frontmatter" "$(creason yc)"
else echo "[SKIP] PyYAML が無い環境: 突き合わせの配線テストをスキップ"; fi

# ================================================================ 試行5
section "試行5-1: ホストの /proc を見せない (空 /proc は明示フラグ) / リソース制限"
SBF=(--gate-empty-proc)
{ cand sbq "sig b" agent/scripts/x.py "$TMP/t_small"; } | jq -s . >"$TMP/c20.json"
fresh_state
python3 -I -B "$H2" "${SBF[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c20.json" --repo-root "$REPO" --experience "$EXP" \
    --out-dir "$PROP" --security-cmd "/usr/bin/true" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
sb5_rc=$?
if [[ "$sb5_rc" -eq 0 && "$(jq_out '.security_gate.sandbox')" == bwrap* ]]; then
    mode5="$(jq_out '.security_gate.sandbox')"
    # --- /proc: 別プロセスの cmdline が読めない
    printf 'import os, sys\nfound = []\nfor d in os.listdir("/proc"):\n    if d.isdigit():\n        try:\n            if b"H2PROCMARKER" in open("/proc/%%s/cmdline" %% d, "rb").read(): found.append(d)\n        except OSError:\n            pass\nsys.exit(1 if found else 0)\n' >"$REPO/agent/scripts/procprobe.py"
    python3 -I -B -c 'import time; time.sleep(120)' H2PROCMARKER &  # 別プロセス (引数にマーカー)
    mpid=$!
    sleep 0.3
    fresh_state
    python3 -I -B "$H2" "${SBF[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c20.json" --repo-root "$REPO" --experience "$EXP" \
        --out-dir "$PROP" --security-cmd "python3 {root}/agent/scripts/procprobe.py" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
    check "隔離下: ホストの他プロセスの cmdline は読めない (baseline)" "true" "$(jq_out '.security_gate.ok')"
    check "隔離下: ホストの他プロセスの cmdline は読めない (候補の複製)" "accepted" "$(cstat sbq)"
    fresh_state
    python3 -I -B "$H2" --allow-unsandboxed-gate --traces "$TMP/tr3.jsonl" --candidates "$TMP/c20.json" --repo-root "$REPO" --experience "$EXP" \
        --out-dir "$PROP" --security-cmd "python3 {root}/agent/scripts/procprobe.py" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
    check "対照: 隔離なしなら同じ probe がホストの cmdline を読める (テストの感度)" "false" "$(jq_out '.security_gate.ok')"
    kill "$mpid" 2>/dev/null; wait "$mpid" 2>/dev/null
    # --- リソース制限
    python3 -I -B - "$TMP" <<'PY'
import sys
t = sys.argv[1]
HEAD = "import os, sys, time\nhere = os.path.dirname(os.path.abspath(__file__))\n"
codes = {
 "fsize": HEAD + '''written = 0; blocked = False
try:
    with open(os.path.join(here, "big.bin"), "wb") as f:
        chunk = b"x" * (8 << 20)
        while written < (200 << 20):
            f.write(chunk); f.flush(); written += len(chunk)
except OSError:
    blocked = True
sys.exit(0 if blocked and written <= (136 << 20) else 1)
''',
 "fork": HEAD + '''kids = []; blocked = False
try:
    for i in range(1500):
        pid = os.fork()
        if pid == 0:
            time.sleep(20); os._exit(0)
        kids.append(pid)
except OSError:
    blocked = True
for p in kids:
    os.kill(p, 9)
sys.exit(0 if blocked else 1)
''',
 "tmp": HEAD + '''total = 0; blocked = False
try:
    for i in range(10):
        with open("/tmp/fill%d" % i, "wb") as f:
            for _ in range(8):
                f.write(b"x" * (8 << 20)); f.flush(); total += 8 << 20
except OSError:
    blocked = True
sys.exit(0 if blocked and total <= (300 << 20) else 1)
''',
 "as": HEAD + '''try:
    b = bytearray(5 << 30)
    blocked = False
except MemoryError:
    blocked = True
sys.exit(0 if blocked else 1)
''',
 "quota": HEAD + '''for i in range(3):
    with open(os.path.join(here, "q%d.bin" % i), "wb") as f:
        for _ in range(12):
            f.write(b"x" * (8 << 20)); f.flush()
time.sleep(60)
sys.exit(0)
''',
}
for k, v in codes.items():
    open("%s/ev_%s.py" % (t, k), "w").write(v)
PY
    printf 'import sys\nsys.exit(0)\n' >"$REPO/agent/scripts/evil2.py"
    for kind in fsize fork tmp as; do
        { cand "lim$kind" "sig b" agent/scripts/evil2.py "$TMP/ev_$kind.py"; } | jq -s . >"$TMP/c21.json"
        fresh_state
        python3 -I -B "$H2" "${SBF[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c21.json" --repo-root "$REPO" --experience "$EXP" \
            --out-dir "$PROP" --security-cmd "python3 {root}/agent/scripts/evil2.py" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
        case "$kind" in
            fsize) msg="RLIMIT_FSIZE: 1ファイル 200MiB の書き込みは 128MiB 付近で止まる" ;;
            fork) msg="RLIMIT_NPROC: fork 1500 連打は途中で止まる" ;;
            tmp) msg="/tmp の tmpfs は 256MiB で満杯になり ENOSPC" ;;
            as) msg="RLIMIT_AS: 5GiB の確保は MemoryError で止まる" ;;
        esac
        check "$msg (gate を通る = 候補コードが制限で止められた)" "accepted" "$(cstat "lim$kind")"
    done
    { cand limquota "sig b" agent/scripts/evil2.py "$TMP/ev_quota.py"; } | jq -s . >"$TMP/c21.json"
    fresh_state
    t0=$(date +%s)
    python3 -I -B "$H2" "${SBF[@]}" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c21.json" --repo-root "$REPO" --experience "$EXP" \
        --out-dir "$PROP" --security-cmd "python3 {root}/agent/scripts/evil2.py" --json >"$TMP/out.txt" 2>"$TMP/err.txt"
    el=$(( $(date +%s) - t0 ))
    check "複製の容量上限 (256MiB) 超過で gate を打ち切り候補を棄却" "security_gate" "$(creason limquota)"
    check "容量超過は gate timeout を待たず速やかに打ち切られる (< 40s)" "true" "$([[ "$el" -lt 40 ]] && echo true || echo false)"
    check "容量超過後に複製が残らない" "0" "$(ls -d "$TMPDIR"/harness2-gate-* 2>/dev/null | wc -l | tr -d ' ')"
else
    echo "[SKIP] bwrap (空 /proc 含む) が使えない環境 (rc=$sb5_rc): /proc・リソース制限の実機テストをスキップ"
fi
# 既定 gate は空 /proc では bun が動かないため、fresh procfs を拒否する環境では明示フラグ無しで fail-closed
fresh_state
env -u HARNESS2_SECURITY_CMDS python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --candidates "$TMP/c20.json" --repo-root "$ROOT" \
    --experience "$EXP" --out-dir "$PROP" --dry-run --json >"$TMP/out.txt" 2>"$TMP/err.txt"
d5_rc=$?
if [[ "$d5_rc" -eq 2 ]]; then
    # rc=2 の原因は 2 系統ある: (a) bwrap はあるが fresh procfs を拒否する、(b) bwrap 不在または
    # namespace を作れない (入れ子コンテナ等)。どちらも fail-closed なので、原因ごとに
    # 対応する回避策フラグを検証する ((b) に "refuses a fresh procfs" を要求すると誤 FAIL になる)。
    d5_err="$(cat "$TMP/err.txt")"
    if [[ "$d5_err" == *"refuses a fresh procfs"* ]]; then
        check_has "fresh procfs を拒否する環境では --gate-empty-proc 無しで fail-closed (rc=2)" "$d5_err" "refuses a fresh procfs"
        check_has "メッセージが回避策 (--gate-empty-proc / --allow-unsandboxed-gate) を示す" "$d5_err" "--gate-empty-proc"
    else
        check_has "sandbox を作れない環境でも既定 gate は fail-closed (rc=2)" "$d5_err" "cannot create a gate sandbox"
        check_has "メッセージが回避策 (--allow-unsandboxed-gate) を示す" "$d5_err" "--allow-unsandboxed-gate"
    fi
    check "fail-closed なら EXPERIENCE.md/出力は変わらない" "false" "$([[ -e "$PROP" ]] && echo true || echo false)"
else
    check "fresh procfs が使える環境: 既定 gate 2 本が隔離下で通る" "accepted" "$(cstat sbq)"
fi
check "GATE_ENV_ALLOW は 1 回だけ定義" "1" "$(grep -c '^GATE_ENV_ALLOW = ' "$H2")"
check "kill_group は 1 回だけ定義" "1" "$(grep -c '^def kill_group' "$H2")"

section "試行5-2: PyYAML が無い環境での description (保守的な部分集合)"
# PyYAML を import 不能にした独自 reader を、PyYAML (基準) の長さと突き合わせる
ny="$(python3 -I -B - "$H2" "$ROOT" 2>&1 <<'PY'
import importlib.util, random, sys, glob
import yaml as real
def load(name, block_yaml):
    if block_yaml: sys.modules["yaml"] = None
    spec = importlib.util.spec_from_file_location(name, sys.argv[1]); m = importlib.util.module_from_spec(spec)
    try: spec.loader.exec_module(m)
    finally: sys.modules["yaml"] = real
    return m
m = load("h2_noyaml", True)
assert m.yaml is None
SP = [" ", " ", " ", " ", "　", "\u0085", " ", " ", " ", "\x0b", "\x0c", " "]
forms = []
for ch in SP:
    forms += [f"description: a{ch}bcd", f"description:{ch}abc", f"description: abc{ch}", f"description: |\n  a{ch}b\n", f"description: >\n  a\n  {ch}b\n",
              f"description: \"a{ch}b\"", f"description: a\n  {ch}b", f"description: |\n  {ch}\n  b\n", f"description: |\n  a\n{ch}\n  b\n"]
forms += ['description: "aaaa\nkey: ' + "x" * 200 + '"', "description: 'aaaa\nkey: " + "y" * 200 + "'", 'description: "a"\n  "b"',
          "description: |\n  a\n  \n  b\n", "description: a\n\n  b\n", "description: a # " + "z" * 200]
rnd = random.Random(7)
for _ in range(1500):
    ch = rnd.choice(SP + [" ", "\t", "a"])
    body = rnd.choice(["description: x{0}y", "description: |\n  x{0}y\n  z", "description: >\n  x\n  {0}y", "description: \"x{0}y\"\n  z", "description: x\n  {0}y\n  z"])
    forms.append(body.format(ch * rnd.randint(1, 3)))
n = viol = none = 0; ex = []
for f in forms:
    t = "---\nname: foo\n" + f + "\n---\nbody\n"
    ours = m.skill_description(t)
    if ours is None: none += 1
    try: d = real.safe_load("name: foo\n" + f + "\n")
    except real.YAMLError: continue
    yd = d.get("description") if isinstance(d, dict) else None
    if not isinstance(yd, str): continue
    n += 1
    if ours is not None and len(ours) < len(yd):
        viol += 1; ex.append((len(ours), len(yd), f[:60]))
quoted = m.skill_description('---\nname: foo\ndescription: "quoted"\n---\n')
multi = m.skill_description("---\nname: foo\ndescription: a\n  b\n---\n")
single = m.skill_description("---\nname: foo\ndescription: plain one line\n---\n")
blk = m.skill_description("---\nname: foo\ndescription: |-\n  a\n  b\n---\n")
real_ok = sum(1 for f in sorted(glob.glob(sys.argv[2] + "/agent/skills/*/SKILL.md")) if (d := m.skill_description(open(f, encoding="utf-8").read())) is not None and len(d) <= 160)
print("NOYAML COMPARED=%d VIOLATIONS=%d NONE=%d quoted=%r multi=%r single=%r block=%r REAL_OK=%d %s" % (n, viol, none, quoted, multi, single, blk, real_ok, ex[:2]))
PY
)"
echo "$ny" | tail -1 | cut -c1-260
check "PyYAML 不在: Unicode 空白・引用符+col-0 行・複数行の過少計測が 0 件" "VIOLATIONS=0" "$(echo "$ny" | tail -1 | grep -o 'VIOLATIONS=[0-9]*')"
cmpn="$(echo "$ny" | tail -1 | grep -o 'COMPARED=[0-9]*' | cut -d= -f2)"
check "PyYAML 不在テストの比較件数が十分 (>= 500)" "true" "$([[ "${cmpn:-0}" -ge 500 ]] && echo true || echo false)"
check "PyYAML 不在: 引用符付き scalar は棄却 (None)" "quoted=None" "$(echo "$ny" | tail -1 | grep -o 'quoted=[A-Za-z0-9]*')"
check "PyYAML 不在: 複数行 plain は棄却 (None)" "multi=None" "$(echo "$ny" | tail -1 | grep -o 'multi=[A-Za-z0-9]*')"
check "PyYAML 不在: 1行 plain は受理" "single='plain one line'" "$(echo "$ny" | tail -1 | grep -o "single='plain one line'")"
check "PyYAML 不在: 単純 block (|-) は受理" "ok" "$([[ "$(echo "$ny" | tail -1)" == *"block='a"*"nb'"* ]] && echo ok)"
printf -- '---\nname: foo\ndescription: "%s\nkey: %s"\n---\nbody\n' "aaaa" "$(chars 200 x)" >"$TMP/m1.md"
skill_fm "$TMP/n_plain" "name: foo\ndescription: plain one line\n"
skill_fm "$TMP/n_block" "name: foo\ndescription: |-\n  a\n  b\n"
skill_fm "$TMP/n_quoted" "name: foo\ndescription: \"quoted\"\n"
skill_fm "$TMP/n_multi" "name: foo\ndescription: a\n  b\n"
{
    cand np "sig b" agent/skills/foo/SKILL.md "$TMP/n_plain"
    cand nb "sig b" agent/skills/foo/SKILL.md "$TMP/n_block"
    cand nq "sig b" agent/skills/foo/SKILL.md "$TMP/n_quoted"
    cand nm "sig b" agent/skills/foo/SKILL.md "$TMP/n_multi"
    cand n1 "sig b" agent/skills/foo/SKILL.md "$TMP/m1.md"
} | jq -s . >"$TMP/c22.json"
fresh_state
HARNESS2_NO_YAML=1 std_run "$TMP/tr3.jsonl" "$TMP/c22.json"
check "PyYAML 不在 (CLI): 1行 plain は採用" "accepted" "$(cstat np)"
check "PyYAML 不在 (CLI): 単純 block は採用" "accepted" "$(cstat nb)"
check "PyYAML 不在 (CLI): 引用符付きは棄却" "skill_frontmatter" "$(creason nq)"
check "PyYAML 不在 (CLI): 複数行 plain は棄却" "skill_frontmatter" "$(creason nm)"
check "PyYAML 不在 (CLI): 引用符 + col-0 行 (M1) は棄却" "skill_frontmatter" "$(creason n1)"
check "PyYAML 不在を JSON warnings に出す" "true" "$(jq_out '[.warnings[]|select(contains("PyYAML"))]|length>0')"
check_has "PyYAML 不在を stderr にも出す" "$(cat "$TMP/err.txt")" "PyYAML"
fresh_state
std_run "$TMP/tr3.jsonl" "$TMP/c22.json"
check "PyYAML あり: 警告は出ない" "0" "$(jq_out '[.warnings[]|select(contains("PyYAML"))]|length')"

BSL=$(printf '\\')
section "試行5-3: 不可視文字はカテゴリ指定 (Cc/Cf/Cs/Co/Cn/Zl/Zp/Zs/Mn-VS + 明示追加)"
for ch in '؀' '۝' '܏' '࢐' '࣢' '𑂽' '𓐰' '𛲠' '𝅳' '𝅙' \
    '󰀀' '􏿽' 'ᅟ' 'ᅠ' '឴' '឵' '᠋' '᠌' '᠍' ' ' '　' ' ' ' ' ' ' ' ' ' ' '﷐' '￿' '͸'; do
    printf '{"signature":"sig%sb","task":"t","target":"agent/scripts/x.py"}\n' "$ch" >"$TMP/inj.jsonl"
    expect_rc2 "signature にカテゴリ該当文字 $ch" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
    printf '{"signature":"sig b","task":"t","target":"agent/scripts/x.py","message":"m%sx"}\n' "$ch" >"$TMP/inj.jsonl"
    expect_rc2 "message にカテゴリ該当文字 $ch" "$CTRL_NEEDLE" --traces "$TMP/inj.jsonl" "${BASE[@]}"
    printf '[{"id":"nt","signature":"sig b","target":"agent/scripts/x.py","new_text":"a%sb\\n","probes":[]}]' "$ch" >"$TMP/nt.json"
    expect_rc2 "new_text にカテゴリ該当文字 $ch" "$CTRL_NEEDLE" --traces "$TMP/tr3.jsonl" --candidates "$TMP/nt.json" "${BASE[@]}"
done
printf '[{"id":"nt","signature":"sig b","target":"agent/scripts/x.py","new_text":"日本語 abc\\tdef\\n","probes":[]}]' >"$TMP/nt.json"
fresh_state
run_h2 --traces "$TMP/tr3.jsonl" --candidates "$TMP/nt.json" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "通常の非 ASCII 文字 (日本語) と TAB/LF は new_text で許可される" "0" "$RC"
fresh_state
python3 -I -B "$H2" --traces "$TMP/tr3.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" \
    --security-cmd $'true　x y\xef\xb8\x8f' --json >"$TMP/out.txt" 2>"$TMP/err.txt"
check "警告の表示は Zs/VS も含めてエスケープする (生の U+3000 が出ない)" "0" "$(grep -c $'\xe3\x80\x80' "$TMP/err.txt")"
check_has "警告で U+3000 が \\u3000 に変換される" "$(cat "$TMP/err.txt")" "${BSL}u3000"
check_has "警告で U+00A0 が \\u00a0 に変換される" "$(cat "$TMP/err.txt")" "${BSL}u00a0"
check_has "警告で VS16 が \\ufe0f に変換される" "$(cat "$TMP/err.txt")" "${BSL}ufe0f"

section "試行5-4: message の C1 制御文字 (CSI) は描画時に無害化される"
C1=$'\xc2\x9b'
printf '{"signature":"sig c1","task":"a","target":"agent/scripts/x.py","message":"m%s[31mred"}\n' "$C1" >"$TMP/c1.jsonl"
cat "$TMP/c1.jsonl" "$TMP/c1.jsonl" "$TMP/c1.jsonl" >"$TMP/c1x3.jsonl"
fresh_state
run_h2 --traces "$TMP/c1x3.jsonl" --repo-root "$REPO" --experience "$EXP" --out-dir "$PROP" --security-cmd "bash $TMP/ok.sh" --json
check "C1 を含む message でも rc=0" "0" "$RC"
check "C1 (CSI) が EXPERIENCE.md に入らない" "0" "$(grep -c $'\xc2\x9b' "$EXP")"
check "C1 を含む message のエントリは追加される" "5" "$(grep -c '^### [0-9a-f]\{16\}$' "$EXP")"

echo
echo "---"
if [[ "$total_fail" -gt 0 ]]; then
    echo "test-harness2-offline: $total_fail 件のFAILあり"
    exit 1
fi
echo "test-harness2-offline: 全テストPASS"
exit 0
