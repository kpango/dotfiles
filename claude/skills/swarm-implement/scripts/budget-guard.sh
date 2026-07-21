#!/usr/bin/env bash
# Unified Credit Feedback: タスクごとの試行回数を計数し、上限超過で exit 1。
# usage: budget-guard.sh <task-id> [max-attempts=5] [--mission=<root-slug>] [--mission-max=<N>=20]
#        budget-guard.sh --fable <task-id> [--mission=<root-slug>]
#        budget-guard.sh --fable-maker <base-task-id>
#        budget-guard.sh --reset <task-id> [--mission=<root-slug>]
#   --fable-maker: Fable Maker (診断→実装昇格) の継続 grant。base task の --fable 消費実績
#     (_fable-<base> カウンタ >= 1) を機械的に検証してから <base>-maker 名義の grant を
#     発行する (mission 枠は消費しない・継続も 1 回のみ)。実績が無ければ FABLE_MAKER_NO_BASE
#     で拒否 — 任意タスクが -maker 名義で mission 枠を回避する抜け穴を塞ぐ。
#   --fable: Fable スポット判断ルート (SWARM.md §1 スポット判断層) の消費カウンタ。
#     試行カウンタとは独立に、1 タスク 1 回・1 ミッション 2 回を機械的に強制する
#     (上限は SWARM.md の設計合意による固定値。--mission-max は --fable モードでは無視される。
#     超過は FABLE_BUDGET_EXCEEDED で exit 1 → 呼び出し元は Fable を使わず発動トリガーごとの
#     従来経路へフォールバックする — SWARM.md §1 参照)。--reset は fable カウンタも削除する。
#   --mission=<root-slug>: ネストされた /swarm-loop ツリー全体で共有する予算カウンタ
#     (_mission-total-<root-slug>)をタスク単位カウンタとは独立にインクリメントする。
#     共有カウンタが --mission-max (省略時 20) を超えたら MISSION_BUDGET_EXCEEDED で exit 1
#     (個々の task-id が自身の max-attempts 以下でも関係ない)。
#   共有カウンタの read-modify-write は flock (util-linux) で直列化する。ロック無しの
#   cat→+1→printf は並行呼び出し(2 worktree 以上の並列実装、SWARM.md §4)でインクリメントが
#   失われるレースコンディションになるため必須。
set -euo pipefail

dir="$HOME/.claude/session-data/swarm/budget"
mkdir -p "$dir"

# 定数の単一ソース (fable-budget.conf)。欠落時は同値のフォールバック既定値。
# shellcheck disable=SC1090
conf="${FABLE_BUDGET_CONF:-$(dirname "${BASH_SOURCE[0]}")/fable-budget.conf}"
[ -f "$conf" ] && . "$conf"
: "${FABLE_TASK_MAX:=1}" "${FABLE_MISSION_MAX:=2}" "${FABLE_GRANT_TTL_SECONDS:=600}"
: "${FABLE_SPOT_LOG_MAX_LINES:=1000}" "${FABLE_SPOT_LOG_KEEP_LINES:=500}"
: "${BUDGET_TASK_MAX_DEFAULT:=5}" "${BUDGET_MISSION_MAX_DEFAULT:=20}"

# root-slug に ".." や "/" が含まれても意図しないパスへ書き込まないようサニタイズする
# (task-id の "${task//\//_}" と同じ考え方 + ".." を先に潰す)。
sanitize_slug() {
  local s="$1"
  s="${s//../_}"
  s="${s//\//_}"
  printf '%s' "$s"
}

# task-id のサニタイズ後の値が予約カウンタのファイル名と衝突すると混線する:
#   _mission-total-* / _fable-* : 予約ファイルの接頭辞そのもの。
#   mission-total-* (アンダースコアなし) : fable モードのタスクカウンタ実ファイル名が
#     "_fable-<task-id>" のため、task-id が mission-total-<slug> だと共有カウンタ
#     "_fable-mission-total-<slug>" と同一ファイルに衝突しミッション予算が混線する。
#     実害は fable モードのみだが、同一 task-id は通常/fable 両モードで併用されるため
#     モードを跨いで一律拒否する保守的挙動を意図している (通常モードの実ファイル名は
#     接頭辞なしなので衝突自体は起きない)。
check_reserved_prefix() {
  local raw="$1" sanitized="$2"
  if [[ "$sanitized" == _mission-total-* || "$sanitized" == _fable-* || "$sanitized" == mission-total-* ]]; then
    echo "RESERVED_PREFIX_COLLISION: task-id '$raw' sanitizes to '$sanitized', which collides with a reserved counter-file prefix ('_mission-total-' / '_fable-' / 'mission-total-') — choose a different task-id" >&2
    exit 1
  fi
}

# fable スポットの grant/deny 観測ログ (JSONL) 用エスケープ。ログはトリガー別発火頻度・
# 上限妥当性の調整証跡であり --reset でも削除しない。
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

reset_mode=false
fable_mode=false
fable_maker_mode=false
if [ "${1:-}" = "--reset" ]; then
  reset_mode=true
  shift
elif [ "${1:-}" = "--fable" ]; then
  fable_mode=true
  shift
elif [ "${1:-}" = "--fable-maker" ]; then
  fable_maker_mode=true
  shift
fi

mission=""
mission_max=$BUDGET_MISSION_MAX_DEFAULT
mission_max_explicit=false
positional=()
for arg in "$@"; do
  case "$arg" in
    --mission=*) mission="${arg#--mission=}" ;;
    --mission-max=*) mission_max="${arg#--mission-max=}"; mission_max_explicit=true ;;
    *) positional+=("$arg") ;;
  esac
done

# --mission-max は非負整数のみ許可する。depth (mission-init.sh) と同様の検証。
# 未検証のままだと不正値 (例: "abc") で `[ "$mn" -gt "$mission_max" ]` が exit status 2 で
# 失敗し、if 文の中では「超過していない」と暗黙に扱われて共有予算上限が静かに無効化される。
if $mission_max_explicit && ! [[ "$mission_max" =~ ^[0-9]+$ ]]; then
  echo "INVALID_MISSION_MAX: --mission-max=\"$mission_max\" is not a non-negative integer" >&2
  exit 1
fi

if $reset_mode; then
  task="${positional[0]:?task-id required}"
  sanitized_task="${task//\//_}"
  check_reserved_prefix "$task" "$sanitized_task"
  rm -f "$dir/$sanitized_task" "$dir/_fable-$sanitized_task" "$dir/.lock-fable-$sanitized_task" \
    "$dir/_fable-$sanitized_task-maker" "$dir/.lock-fable-$sanitized_task-maker"
  # grant の回収は task-id 完全一致で行う (suffix glob だと task "b" の reset が task "a-b" の
  # grant を巻き込む)。grant ファイル名は <epoch_nanos>-<task-id> で nanos 部にハイフンは
  # 無いため、最初のハイフン以降がちょうど task-id。base の reset は Fable Maker 継続分
  # (<base>-maker) も一緒に回収する (継続は base に従属する概念のため)。
  for gf in "$dir/.fable-grants"/*; do
    [ -f "$gf" ] || continue
    tp="${gf##*/}"
    tp="${tp#*-}"
    if [ "$tp" = "$sanitized_task" ] || [ "$tp" = "$sanitized_task-maker" ]; then
      rm -f "$gf"
    fi
  done
  if [ -n "$mission" ]; then
    slug="$(sanitize_slug "$mission")"
    rm -f "$dir/_mission-total-$slug" "$dir/.lock-mission-$slug" \
      "$dir/_fable-mission-total-$slug" "$dir/.lock-fable-mission-$slug"
  fi
  echo "reset: $task"
  exit 0
fi

# Fable スポット消費 (試行カウンタとは独立。上限は設計合意の固定値):
# 試行カウンタの「呼び出し = 消費」とは意味論が異なる — 本ガードは Fable スポーンの**前**に
# 呼ばれる許可ゲートであり、拒否した呼び出しはトークンを一切消費させない。したがって
# カウンタは「許可した回数」のみを記録する (拒否で mission 枠を燃やすと、上限到達済みの
# 1 タスクの再呼び出しだけでミッション全体の Fable 予算が空になってしまう)。
# mission カウンタの check-and-increment は並列実装 (worktree 複数) からの同時呼び出しに
# 備え専用ロック内で原子的に行う。
# Fable Maker 継続 grant: base spot の消費実績を検証してから、task=<base>-maker として
# 通常の fable 発行経路 (mission 無し = mission 枠不消費) に合流する。
if $fable_maker_mode; then
  base="${positional[0]:?usage: budget-guard.sh --fable-maker <base-task-id>}"
  sanitized_base="${base//\//_}"
  check_reserved_prefix "$base" "$sanitized_base"
  # base 側にも -maker を拒否する対称ガード: 継続カウンタ (_fable-X-maker) を base 実績と
  # 誤認すると X-maker-maker... の mission 枠不消費な無限連鎖が成立してしまう。
  # 正規の base が -maker で終わることはない (--fable 側の RESERVED_SUFFIX 拒否により)。
  if [[ "$sanitized_base" == *-maker ]]; then
    echo "RESERVED_SUFFIX: --fable-maker の base '$base' が '-maker' で終わる — 継続の連鎖 (X-maker-maker) は禁止。base には元の task-id を渡せ" >&2
    exit 1
  fi
  # base カウンタの読みは非ロックでよい: 継続 grant は base spot の消費 (逐次的な前段) の
  # 後にのみ要求される運用で、読む時点で base カウンタは書き終わっている。
  bn=$(cat "$dir/_fable-$sanitized_base" 2>/dev/null || echo 0)
  if [ "$bn" -lt 1 ]; then
    echo "FABLE_MAKER_NO_BASE: task=$base の base spot 消費実績が無い — Fable Maker 継続 grant は base の budget-guard.sh --fable 消費後にのみ発行できる (SWARM.md §1 スポット判断層)" >&2
    exit 1
  fi
  task="$base-maker"
  sanitized_task="$sanitized_base-maker"
  mission=""
  fable_mode=true
fi

if $fable_mode; then
  fable_task_max=$FABLE_TASK_MAX
  fable_mission_max=$FABLE_MISSION_MAX
  if ! $fable_maker_mode; then
    task="${positional[0]:?usage: budget-guard.sh --fable <task-id> [--mission=<root-slug>]}"
    sanitized_task="${task//\//_}"
    check_reserved_prefix "$task" "$sanitized_task"
    # -maker サフィックスは Fable Maker 継続専用の予約名。直接 --fable で使えると
    # base spot 消費実績の検証 (--fable-maker) を迂回できてしまうため拒否する。
    if [[ "$sanitized_task" == *-maker ]]; then
      echo "RESERVED_SUFFIX: task-id '$task' は '-maker' で終わる — このサフィックスは Fable Maker 継続 grant 専用 (budget-guard.sh --fable-maker <base-task-id> を使うか task-id を変更せよ)" >&2
      exit 1
    fi
  fi

  grants_dir="$dir/.fable-grants"
  spot_log="$HOME/.claude/session-data/swarm/fable-spot-log.jsonl"
  spot_log_max=$FABLE_SPOT_LOG_MAX_LINES
  spot_log_keep=$FABLE_SPOT_LOG_KEEP_LINES
  fn=0; fm=0
  # 追記とローテーションは同一ロック内で行う (並行 writer のローテーション中追記が
  # tail→mv の窓で失われるのを防ぐ)。ログは観測記録のため --reset では消さないが、
  # 無限成長はここで抑える (1000 行超 → 直近 500 行)。
  log_spot() { # <decision: grant|deny_task|deny_mission>
    {
      flock -x 202
      # 過去のローテーション異常終了の残骸を機会的に掃除 (ロック内なので進行中の
      # ローテーションと衝突しない)
      rm -f "$spot_log".rotating.* 2>/dev/null || true
      printf '{"ts":"%s","task":"%s","mission":"%s","decision":"%s","task_count":%s,"mission_count":%s}\n' \
        "$(date -Is)" "$(json_escape "$task")" "$(json_escape "$mission")" "$1" "$fn" "$fm" >>"$spot_log"
      if [ "$(wc -l <"$spot_log")" -gt "$spot_log_max" ]; then
        tail -n "$spot_log_keep" "$spot_log" >"$spot_log.rotating.$$" && mv "$spot_log.rotating.$$" "$spot_log"
      fi
    } 202>"$dir/.lock-fable-log"
  }

  ff="$dir/_fable-$sanitized_task"
  # task カウンタの check-and-increment も flock で直列化する。同一 task-id への並行呼び出し
  # (並列 worktree からの再試行等) が双方 fn=0 を読むと二重許可され「1 タスク 1 回」の
  # 不変条件が破れるため (mission カウンタ側だけロックしても防げない)。ロック順序は常に
  # task (fd 201) → mission (fd 200) の一方向で取得するためデッドロックしない。
  task_lockfile="$dir/.lock-fable-$sanitized_task"
  {
    flock -x 201
    fn=$(cat "$ff" 2>/dev/null || echo 0)
    if [ "$fn" -ge "$fable_task_max" ]; then
      log_spot deny_task
      echo "FABLE_BUDGET_EXCEEDED: task=$task fable-spots=$fn max=$fable_task_max — このタスクは既にスポット判断を消費済み。Fable を使わず発動トリガーの従来経路へフォールバックせよ (SWARM.md §1)" >&2
      exit 1
    fi

    fm=0
    if [ -n "$mission" ]; then
      slug="$(sanitize_slug "$mission")"
      fmf="$dir/_fable-mission-total-$slug"
      lockfile="$dir/.lock-fable-mission-$slug"
      granted=false
      {
        flock -x 200
        fm=$(cat "$fmf" 2>/dev/null || echo 0)
        if [ "$fm" -lt "$fable_mission_max" ]; then
          fm=$((fm + 1))
          printf '%s\n' "$fm" >"$fmf"
          granted=true
        fi
      } 200>"$lockfile"
      if ! $granted; then
        log_spot deny_mission
        echo "FABLE_BUDGET_EXCEEDED: mission=$mission fable-spots=$fm max=$fable_mission_max (task=$task) — スポット判断層の予算超過。Fable を使わず発動トリガーの従来経路へフォールバックせよ (SWARM.md §1)" >&2
        exit 1
      fi
    fi

    fn=$((fn + 1))
    printf '%s\n' "$fn" >"$ff"

    # grant トークン発行: swarm-fable-gate.sh (PreToolUse:Task|Agent hook) が
    # Agent(model:'fable') 起動時に、prompt の [fable-spot:<task-id>] マーカーと
    # 突き合わせて同一 task の grant を 1 つ消費する。1 grant = 1 スポーン。
    mkdir -p "$grants_dir"
    # 期限切れ grant の発行時掃除 (TTL は fable-budget.conf の FABLE_GRANT_TTL_SECONDS を
    # 分単位へ切り上げ。hook 側の消費時掃除と同一ソース)
    find "$grants_dir" -maxdepth 1 -type f -mmin +"$(((FABLE_GRANT_TTL_SECONDS + 59) / 60))" -delete 2>/dev/null || true
    printf 'task=%s\nmission=%s\ngranted_at=%s\n' "$task" "$mission" "$(date -Is)" \
      >"$grants_dir/$(date +%s%N)-$sanitized_task"
    log_spot grant
  } 201>"$task_lockfile"

  if [ -n "$mission" ]; then
    echo "fable spot $fn/$fable_task_max (task=$task, mission=$mission $fm/$fable_mission_max)"
  else
    echo "fable spot $fn/$fable_task_max (task=$task)"
  fi
  exit 0
fi

task="${positional[0]:?usage: budget-guard.sh <task-id> [max-attempts]}"
max="${positional[1]:-$BUDGET_TASK_MAX_DEFAULT}"
sanitized_task="${task//\//_}"
check_reserved_prefix "$task" "$sanitized_task"
f="$dir/$sanitized_task"

# 共有ミッションカウンタは task 自身の予算超過判定より先に、かつ独立にインクリメントする:
# 1 回の呼び出し = 1 回の実際の消費(トークン・時間)であり、task 側が自身の上限を超えていても
# 共有予算は既に消費されているため。read-modify-write は flock で直列化し、並行呼び出しでの
# インクリメント消失(レースコンディション)を防ぐ。
mission_exceeded=false
mn=0
if [ -n "$mission" ]; then
  slug="$(sanitize_slug "$mission")"
  mf="$dir/_mission-total-$slug"
  lockfile="$dir/.lock-mission-$slug"
  {
    flock -x 200
    mn=$(cat "$mf" 2>/dev/null || echo 0)
    mn=$((mn + 1))
    printf '%s\n' "$mn" >"$mf"
  } 200>"$lockfile"
  if [ "$mn" -gt "$mission_max" ]; then
    mission_exceeded=true
  fi
fi

n=$(cat "$f" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s\n' "$n" >"$f"

if $mission_exceeded; then
  echo "MISSION_BUDGET_EXCEEDED: mission=$mission attempts=$mn max=$mission_max (task=$task) — ツリー全体の共有予算超過。即座に停止し、@fix_plan.md に軌跡を書き出して人間に報告せよ" >&2
  exit 1
fi

if [ "$n" -gt "$max" ]; then
  echo "BUDGET_EXCEEDED: task=$task attempts=$n max=$max — 即座に停止し、@fix_plan.md に軌跡を書き出して人間に報告せよ" >&2
  exit 1
fi

echo "attempt $n/$max (task=$task)"
