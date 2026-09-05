#!/usr/bin/env bash
# ==============================================================================
# scripts/skill-stats.sh
# Dual-tier metrics tracking, aggregation, and meta-evolution support for skills
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve base directories
if [ -n "${AGY_HOME:-}" ] && [ -d "$AGY_HOME" ]; then
  BASE_DATA_DIR="$AGY_HOME/session-data/skills"
elif [ -d "$HOME/.gemini" ]; then
  BASE_DATA_DIR="$HOME/.gemini/session-data/skills"
elif [ -d "$HOME/.agy" ]; then
  BASE_DATA_DIR="$HOME/.agy/session-data/skills"
else
  BASE_DATA_DIR="$HOME/.claude/session-data/swarm"
fi

EVENT_STREAM_FILE="${SKILL_EVENTS_FILE:-$BASE_DATA_DIR/skill-events.jsonl}"

# Fail-open wrapper for subcommands
classify_error() {
  local err_text="${1:-}"
  python3 -c "
import re, sys

err = sys.argv[1] if len(sys.argv) > 1 else ''

if re.search(r'(golangci-lint|hadolint|clippy|pyright|flake8|pylint|rubocop|shellcheck|zsh -n|eslint|tsc)', err, re.I):
    print('linter_error')
elif re.search(r'(Vald Law|\.pb\.go|_vtproto\.pb\.go|go build in vald|cargo build in vald)', err, re.I):
    print('vald_law_violation')
elif re.search(r'(FAIL:|--- FAIL|panic:|assertion failed|pytest.*failed|cargo test.*failed|Test.*failed)', err, re.I):
    print('test_failure')
elif re.search(r'(syntax error|SyntaxError|cannot parse|unexpected token|compilation error)', err, re.I):
    print('syntax_error')
elif re.search(r'(timeout|timed out|deadline exceeded|context deadline)', err, re.I):
    print('timeout')
elif re.search(r'(permission denied|protected path|forbidden|EACCES|unauthorized)', err, re.I):
    print('permission_denied')
elif re.search(r'(schema violation|missing required key|invalid json|type error|AttributeError)', err, re.I):
    print('schema_violation')
else:
    print('unknown')
" "$err_text"
}

find_skill_stats_path() {
  local skill_name="$1"
  local target_root="${2:-$REPO_ROOT}"

  # 2026-09-03: claude/pi/agy 個別のSKILL.stats.jsonはagent/skills/<name>/SKILL.stats.json
  # (単一正典)へ統合済み(scripts/merge-skill-stats.py参照)。agent/skillsはMakefile.d/install.mk・
  # nix/modules/home/dotfiles/agent-tools.nixが既にディレクトリ丸ごとclaude/pi/agy/geminiへ
  # symlinkしているため、追加の配線無しに全ツールから同一ファイルとして見える。
  echo "$target_root/agent/skills/$skill_name/SKILL.stats.json"
}

init_default_stats() {
  local skill_name="$1"
  local target_path="$2"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  mkdir -p "$(dirname "$target_path")"
  python3 -c "
import json, sys

path = sys.argv[1]
name = sys.argv[2]
now = sys.argv[3]

stats = {
    'schema_version': '1.0.0',
    'skill_name': name,
    'version': '1.0.0',
    'description': f'Metrics and lifecycle statistics for {name}',
    'category': 'domain-specialist' if 'pattern' in name or 'testing' in name else 'swarm-orchestrator',
    'metrics': {
        'execution_count': 0,
        'success_count': 0,
        'failure_count': 0,
        'success_rate': 1.0,
        'retry_count': 0,
        'total_duration_ms': 0,
        'avg_duration_ms': 0.0,
        'min_duration_ms': 0,
        'max_duration_ms': 0,
        'total_tokens_in': 0,
        'total_tokens_out': 0,
        'avg_tokens_per_call': 0.0,
        'cache_read_tokens': 0,
        'cache_hit_rate': 0.0
    },
    'lifecycle': {
        'created_at': now,
        'first_executed': None,
        'last_executed': None,
        'last_status': 'initial'
    },
    'failure_signatures': [],
    'prompt_revision_history': [
        {
            'revision': 1,
            'timestamp': now,
            'author': 'initial',
            'commit_hash': None,
            'change_summary': 'Initial baseline schema definition',
            'diff_type': 'docs-only',
            'trigger': 'initial',
            'baseline_success_rate_before': None,
            'baseline_success_rate_after': 1.0,
            'target_metric': None
        }
    ]
}

with open(path, 'w', encoding='utf-8') as f:
    json.dump(stats, f, indent=2)
" "$target_path" "$skill_name" "$now"
}

record_start() {
  local skill_name="${1:?Missing skill_name}"
  shift
  local invoker="agent"
  local task_id=""
  local session_id="${CLAUDE_SESSION_ID:-${AGY_SESSION_ID:-manual-session}}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --invoker) invoker="$2"; shift 2 ;;
      --task) task_id="$2"; shift 2 ;;
      --session) session_id="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local event_id="evt-$(date +%s%N 2>/dev/null || date +%s)-${RANDOM}"

  echo "EVENT_ID=$event_id"
  echo "TIMESTAMP=$ts"
  echo "SKILL=$skill_name"
}

record_end() {
  local skill_name="${1:?Missing skill_name}"
  local event_id="${2:?Missing event_id}"
  local status="${3:?Missing status (success|failure|timeout|cancelled)}"
  local duration_ms="${4:-0}"
  local tokens_in="${5:-0}"
  local tokens_out="${6:-0}"
  shift 6 || true

  local error_sig=""
  local error_sample=""
  local retry_count=0
  local invoker="agent"

  while [ $# -gt 0 ]; do
    case "$1" in
      --error-sig) error_sig="$2"; shift 2 ;;
      --error-sample) error_sample="$2"; shift 2 ;;
      --retry) retry_count="$2"; shift 2 ;;
      --invoker) invoker="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [ "$status" = "failure" ] && [ -z "$error_sig" ] && [ -n "$error_sample" ]; then
    error_sig="$(classify_error "$error_sample")"
  fi

  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Ensure event stream directory exists
  mkdir -p "$(dirname "$EVENT_STREAM_FILE")"

  # 1. Append to Event Stream
  python3 -c "
import json, sys

event = {
    'event_id': sys.argv[1],
    'timestamp': sys.argv[2],
    'skill_name': sys.argv[3],
    'status': sys.argv[4],
    'duration_ms': int(sys.argv[5]),
    'tokens_in': int(sys.argv[6]),
    'tokens_out': int(sys.argv[7]),
    'error_signature': sys.argv[8] if sys.argv[8] else None,
    'error_sample': sys.argv[9] if sys.argv[9] else None,
    'retry_count': int(sys.argv[10]),
    'invoker': sys.argv[11]
}

with open(sys.argv[12], 'a', encoding='utf-8') as f:
    f.write(json.dumps(event) + '\n')
" "$event_id" "$ts" "$skill_name" "$status" "$duration_ms" "$tokens_in" "$tokens_out" "$error_sig" "$error_sample" "$retry_count" "$invoker" "$EVENT_STREAM_FILE" 2>/dev/null || true

  # 2. Update the materialized SKILL.stats.json at its single canonical location
  # (2026-09-03: agent/skills/<name>/SKILL.stats.json, formerly written to agy/claude/pi
  # skills/ separately — see find_skill_stats_path()).
  local stats_paths=(
    "$REPO_ROOT/agent/skills/$skill_name/SKILL.stats.json"
  )

  for stats_path in "${stats_paths[@]}"; do
    if [ ! -f "$stats_path" ]; then
      mkdir -p "$(dirname "$stats_path")"
      init_default_stats "$skill_name" "$stats_path"
    fi

    if [ -f "$stats_path" ]; then
      python3 -c "
import json, sys, os, fcntl

stats_file = sys.argv[1]
skill_name = sys.argv[2]
status = sys.argv[3]
duration_ms = int(sys.argv[4])
tokens_in = int(sys.argv[5])
tokens_out = int(sys.argv[6])
error_sig = sys.argv[7] if sys.argv[7] else None
error_sample = sys.argv[8] if sys.argv[8] else None
retry_count = int(sys.argv[9])
ts = sys.argv[10]

try:
    with open(stats_file, 'r+', encoding='utf-8') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            data = json.load(f)
        except Exception:
            data = {}

        data.setdefault('schema_version', '1.0.0')
        data.setdefault('skill_name', skill_name)
        data.setdefault('version', '1.0.0')
        data.setdefault('description', f'Metrics and lifecycle statistics for {skill_name}')
        data.setdefault('category', 'domain-specialist' if 'pattern' in skill_name or 'testing' in skill_name else 'swarm-orchestrator')
        data.setdefault('failure_signatures', [])
        data.setdefault('prompt_revision_history', [
            {
                'revision': 1,
                'timestamp': ts,
                'author': 'initial',
                'commit_hash': None,
                'change_summary': 'Initial baseline schema definition',
                'diff_type': 'docs-only',
                'trigger': 'initial',
                'baseline_success_rate_before': None,
                'baseline_success_rate_after': 1.0,
                'target_metric': None
            }
        ])

        metrics = data.setdefault('metrics', {})
        exec_count = metrics.get('execution_count', 0) + 1
        metrics['execution_count'] = exec_count

        if status == 'success':
            metrics['success_count'] = metrics.get('success_count', 0) + 1
        else:
            metrics['failure_count'] = metrics.get('failure_count', 0) + 1

        succ_count = metrics.get('success_count', 0)
        metrics['success_rate'] = round(succ_count / exec_count, 4) if exec_count > 0 else 1.0

        metrics['retry_count'] = metrics.get('retry_count', 0) + retry_count

        total_dur = metrics.get('total_duration_ms', 0) + duration_ms
        metrics['total_duration_ms'] = total_dur
        metrics['avg_duration_ms'] = round(total_dur / exec_count, 2) if exec_count > 0 else 0.0

        min_dur = metrics.get('min_duration_ms', 0)
        max_dur = metrics.get('max_duration_ms', 0)
        metrics['min_duration_ms'] = duration_ms if min_dur == 0 else min(min_dur, duration_ms)
        metrics['max_duration_ms'] = max(max_dur, duration_ms)

        total_in = metrics.get('total_tokens_in', 0) + tokens_in
        total_out = metrics.get('total_tokens_out', 0) + tokens_out
        metrics['total_tokens_in'] = total_in
        metrics['total_tokens_out'] = total_out
        metrics['avg_tokens_per_call'] = round((total_in + total_out) / exec_count, 2) if exec_count > 0 else 0.0

        lifecycle = data.setdefault('lifecycle', {})
        if not lifecycle.get('first_executed'):
            lifecycle['first_executed'] = ts
        lifecycle['last_executed'] = ts
        lifecycle['last_status'] = status

        if error_sig:
            sigs = data.setdefault('failure_signatures', [])
            found = False
            for s in sigs:
                if s.get('category') == error_sig:
                    s['occurrence_count'] = s.get('occurrence_count', 0) + 1
                    s['last_seen'] = ts
                    if error_sample:
                        s['sample_error'] = error_sample[:200]
                    found = True
                    break
            if not found:
                sigs.append({
                    'signature_id': f'SIG_{error_sig.upper()}_{len(sigs)+1}',
                    'category': error_sig,
                    'description': f'Error classified as {error_sig}',
                    'occurrence_count': 1,
                    'first_seen': ts,
                    'last_seen': ts,
                    'sample_error': (error_sample[:200] if error_sample else ''),
                    'resolved_in_revision': None
                })

        f.seek(0)
        f.truncate()
        json.dump(data, f, indent=2)
        fcntl.flock(f, fcntl.LOCK_UN)
except Exception as e:
    sys.stderr.write(f'Warning: failed to update {stats_file}: {e}\n')
" "$stats_path" "$skill_name" "$status" "$duration_ms" "$tokens_in" "$tokens_out" "$error_sig" "$error_sample" "$retry_count" "$ts" 2>/dev/null || true
    fi
  done

  echo "SUCCESS: Recorded execution for $skill_name ($status, ${duration_ms}ms)"
}

get_stats() {
  local skill_name="${1:?Missing skill_name}"
  local path
  path="$(find_skill_stats_path "$skill_name")"

  if [ -f "$path" ]; then
    cat "$path"
  else
    echo "{\"error\": \"No stats found for skill '$skill_name' at $path\"}"
    return 1
  fi
}

check_low_performing() {
  local threshold="0.80"
  local min_runs=5
  local target_root="$REPO_ROOT"

  while [ $# -gt 0 ]; do
    case "$1" in
      --threshold) threshold="$2"; shift 2 ;;
      --min-runs) min_runs="$2"; shift 2 ;;
      --repo-root) target_root="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  python3 -c "
import json, glob, sys, os

threshold = float(sys.argv[1])
min_runs = int(sys.argv[2])
target_root = sys.argv[3]

pattern = os.path.join(target_root, '**/SKILL.stats.json')
files = glob.glob(pattern, recursive=True)

low_perf = []

for fpath in files:
    try:
        with open(fpath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        name = data.get('skill_name', os.path.basename(os.path.dirname(fpath)))
        metrics = data.get('metrics', {})
        exec_count = metrics.get('execution_count', 0)
        succ_rate = metrics.get('success_rate', 1.0)
        retry_count = metrics.get('retry_count', 0)
        retry_ratio = (retry_count / exec_count) if exec_count > 0 else 0.0

        sigs = data.get('failure_signatures', [])
        recurring_sigs = [s for s in sigs if s.get('occurrence_count', 0) >= 2]

        reasons = []
        if exec_count >= min_runs and succ_rate < threshold:
            reasons.append(f'low_success_rate ({succ_rate:.2f} < {threshold})')
        if exec_count >= min_runs and retry_ratio > 0.50:
            reasons.append(f'high_retry_ratio ({retry_ratio:.2f} > 0.50)')
        if recurring_sigs:
            sig_names = [f\"{s.get('category')} (x{s.get('occurrence_count')})\" for s in recurring_sigs]
            reasons.append(f\"recurring_signatures [{', '.join(sig_names)}]\")

        if reasons:
            low_perf.append({
                'skill_name': name,
                'path': fpath,
                'execution_count': exec_count,
                'success_rate': succ_rate,
                'retry_ratio': round(retry_ratio, 2),
                'reasons': reasons
            })
    except Exception:
        continue

print(json.dumps(low_perf, indent=2))
" "$threshold" "$min_runs" "$target_root"
}

register_revision() {
  local skill_name="${1:?Missing skill_name}"
  local diff_type="${2:-docs-only}"
  local trigger="${3:-manual}"
  local summary="${4:-Prompt optimization revision}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local stats_paths=(
    "$REPO_ROOT/agent/skills/$skill_name/SKILL.stats.json"
  )

  for stats_path in "${stats_paths[@]}"; do
    if [ -f "$stats_path" ]; then
      python3 -c "
import json, sys, fcntl

stats_file = sys.argv[1]
diff_type = sys.argv[2]
trigger = sys.argv[3]
summary = sys.argv[4]
ts = sys.argv[5]
skill_name = sys.argv[6]

try:
    with open(stats_file, 'r+', encoding='utf-8') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            data = json.load(f)
        except Exception:
            data = {}
        data.setdefault('schema_version', '1.0.0')
        data.setdefault('skill_name', skill_name)
        hist = data.setdefault('prompt_revision_history', [])
        rev_num = len(hist) + 1
        rate_before = data.get('metrics', {}).get('success_rate', 1.0)
        hist.append({
            'revision': rev_num,
            'timestamp': ts,
            'author': 'swarm-evolve' if trigger in ['meta-evolution', 'low_success_rate'] else 'human',
            'commit_hash': None,
            'change_summary': summary,
            'diff_type': diff_type,
            'trigger': trigger,
            'baseline_success_rate_before': rate_before,
            'baseline_success_rate_after': None,
            'target_metric': 'success_rate >= 0.85'
        })
        f.seek(0)
        f.truncate()
        json.dump(data, f, indent=2)
        fcntl.flock(f, fcntl.LOCK_UN)
    print(f'Successfully registered revision {rev_num} in {stats_file}')
except Exception as e:
    sys.stderr.write(f'Error registering revision: {e}\n')
" "$stats_path" "$diff_type" "$trigger" "$summary" "$ts" "$skill_name"
    fi
  done
}

aggregate_all() {
  local as_json=0
  if [ "${1:-}" = "--json" ]; then
    as_json=1
  fi

  python3 -c "
import json, glob, sys, os

as_json = int(sys.argv[1])
pattern = os.path.join(sys.argv[2], 'agent/skills/**/SKILL.stats.json')
files = sorted(glob.glob(pattern, recursive=True))

results = []
total_runs = 0
total_succ = 0
total_fail = 0

for fpath in files:
    try:
        with open(fpath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        m = data.get('metrics', {})
        runs = m.get('execution_count', 0)
        succ = m.get('success_count', 0)
        fail = m.get('failure_count', 0)
        total_runs += runs
        total_succ += succ
        total_fail += fail
        results.append({
            'skill': data.get('skill_name'),
            'runs': runs,
            'success_rate': m.get('success_rate', 1.0),
            'avg_ms': m.get('avg_duration_ms', 0.0),
            'last_status': data.get('lifecycle', {}).get('last_status', 'initial')
        })
    except Exception:
        continue

if as_json:
    summary = {
        'total_skills': len(results),
        'total_executions': total_runs,
        'overall_success_rate': round(total_succ / total_runs, 4) if total_runs > 0 else 1.0,
        'skills': results
    }
    print(json.dumps(summary, indent=2))
else:
    print(f'SKILL METRICS AGGREGATION ({len(results)} skills)')
    print(f'Total Executions: {total_runs} | Total Success: {total_succ} | Total Failure: {total_fail}')
    print('-' * 70)
    print(f'{\"Skill Name\":<28} | {\"Runs\":<5} | {\"Success Rate\":<12} | {\"Avg Duration\":<12} | {\"Status\":<8}')
    print('-' * 70)
    for r in results:
        rate_str = f\"{r['success_rate']*100:.1f}%\"
        dur_str = f\"{r['avg_ms']:.1f}ms\"
        print(f\"{r['skill']:<28} | {r['runs']:<5} | {rate_str:<12} | {dur_str:<12} | {r['last_status']:<8}\")
" "$as_json" "$REPO_ROOT"
}

# Main dispatcher
cmd="${1:-help}"
shift || true

case "$cmd" in
  record-start) record_start "$@" ;;
  record-end) record_end "$@" ;;
  get) get_stats "$@" ;;
  check-low-performing) check_low_performing "$@" ;;
  register-revision) register_revision "$@" ;;
  aggregate) aggregate_all "$@" ;;
  classify-error) classify_error "$@" ;;
  help|--help|-h)
    echo "Usage: skill-stats.sh <command> [args...]"
    echo "Commands:"
    echo "  record-start <skill_name> [--invoker <caller>] [--task <id>]"
    echo "  record-end <skill_name> <event_id> <status> <dur_ms> <tok_in> <tok_out> [--error-sig <cat>] [--error-sample <sample>]"
    echo "  get <skill_name>"
    echo "  check-low-performing [--threshold 0.80] [--min-runs 5]"
    echo "  register-revision <skill_name> <diff_type> <trigger> <summary>"
    echo "  aggregate [--json]"
    echo "  classify-error <error_text>"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
