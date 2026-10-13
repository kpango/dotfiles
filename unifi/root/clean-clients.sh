#!/bin/bash
# UniFi ゴーストクライアント一括削除（Network API forget-sta / Network アプリ PostgreSQL モード用）
#
# 対象: 有線 / 名前・ホスト名・IP・メモなし / OUI 未登録 / 固定IP等の個別設定なし /
#       直近 MIN_AGE 秒以上未観測 のクライアント
#   → AP 内部 NIC のランダム MAC（UCXG の eth2/eth3）や VLAN タグ誤解析で生じた実体のないエントリ
#   ※ 現在も AP から出ている MAC は削除しても数分で再登録される。本スクリプトは
#     AP 再起動で使われなくなった古い MAC の掃除用（MIN_AGE は長めにする）
#
# 使い方:
#   /root/clean-clients.sh --dry-run          # 対象の一覧表示のみ
#   /root/clean-clients.sh                    # バックアップ → API で削除（unifi 停止なし）
#   /root/clean-clients.sh --restore FILE     # バックアップ (jsonl) から復元（既存 MAC はスキップ）
#                                             #   ※ 復元のみ DB 直接書き込みのため unifi を 1〜3 分停止
#
# 環境変数:
#   MIN_AGE  (秒, 既定 604800 = 7日)
#   API_KEY_FILE (既定 /data/clean-clients.key, UniFi OS で発行した API キーを 1 行で保存, chmod 600)
set -euo pipefail

MIN_AGE="${MIN_AGE:-604800}"
BACKUP_DIR=/data/clean-clients-backup
API_KEY_FILE="${API_KEY_FILE:-/data/clean-clients.key}"
API_BASE=https://127.0.0.1/proxy/network/api
PSQL=(runuser -u postgres -- psql -p 5434 -d unifi-network -X -q -At -v ON_ERROR_STOP=1)

api() {  # api METHOD PATH [JSON]
  curl -sk --max-time 30 -X "$1" -H "X-API-KEY: $API_KEY" -H 'Content-Type: application/json' \
    ${3:+-d "$3"} "$API_BASE$2"
}

if [ "${1:-}" = "--restore" ]; then
  FILE="$(realpath "${2:?復元するバックアップファイルを指定してください}")"
  trap 'systemctl start unifi' EXIT
  echo "unifi を停止中..."
  systemctl stop unifi
  "${PSQL[@]}" -v f="$FILE" <<'SQL'
BEGIN;
CREATE TEMP TABLE r ON COMMIT DROP AS
  SELECT l::jsonb AS j FROM regexp_split_to_table(pg_read_file(:'f'), E'\n') l WHERE l <> '';
WITH ins AS (
  INSERT INTO config.user_client
    SELECT (jsonb_populate_record(NULL::config.user_client, j->'row')).* FROM r
    WHERE j->>'table' = 'config.user_client'
  ON CONFLICT DO NOTHING RETURNING 1)
SELECT 'user_client 復元: ' || count(*) || ' 件' FROM ins;
WITH ins AS (
  INSERT INTO config.guest_authorization
    SELECT (jsonb_populate_record(NULL::config.guest_authorization, j->'row')).* FROM r
    WHERE j->>'table' = 'config.guest_authorization'
  ON CONFLICT DO NOTHING RETURNING 1)
SELECT 'guest_authorization 復元: ' || count(*) || ' 件' FROM ins;
COMMIT;
SQL
  echo "unifi を起動中..."
  systemctl start unifi
  trap - EXIT
  echo "完了"
  exit 0
fi

[[ "$MIN_AGE" =~ ^[0-9]+$ ]] || { echo "MIN_AGE は秒数で指定してください: $MIN_AGE" >&2; exit 1; }

# 対象クライアントの条件（config.user_client の別名 u）
COND="u.is_wired
  AND coalesce(u.name,'') = '' AND coalesce(u.hostname,'') = '' AND coalesce(u.note,'') = ''
  AND NOT u.noted AND NOT u.blocked AND NOT u.use_fixed_ip
  AND NOT u.local_dns_record_enabled AND NOT u.fixed_ap_enabled
  AND NOT u.virtual_network_override_enabled
  AND coalesce(u.dynamic_part->>'last_ip','') = ''
  AND coalesce(u.dynamic_part->>'oui','') = ''
  AND coalesce(u.last_seen,0) < extract(epoch from now())::bigint - ${MIN_AGE}"

COUNT=$("${PSQL[@]}" -c "SELECT count(*) FROM config.user_client u WHERE ${COND}")
echo "対象: ${COUNT} 件 (MIN_AGE=${MIN_AGE}s)"
[ "$COUNT" -eq 0 ] && exit 0
echo "MAC                first_seen                last_seen                 uplink"
"${PSQL[@]}" -F '  ' -c "
  SELECT u.mac,
         to_char(to_timestamp(u.first_seen),'YYYY-MM-DD\"T\"HH24:MI:SSOF'),
         to_char(to_timestamp(u.last_seen),'YYYY-MM-DD\"T\"HH24:MI:SSOF'),
         coalesce(u.dynamic_part->>'last_uplink_name','-')
           || coalesce(' port ' || (u.dynamic_part->>'last_uplink_remote_port'),'')
  FROM config.user_client u WHERE ${COND} ORDER BY u.first_seen"

[ "${1:-}" = "--dry-run" ] && exit 0

[ -s "$API_KEY_FILE" ] || { echo "API キーファイルがありません: $API_KEY_FILE" >&2; exit 1; }
API_KEY="$(tr -d '[:space:]' < "$API_KEY_FILE")"
[ "$(api GET /s/default/self | jq -r '.meta.rc // empty' 2>/dev/null)" = "ok" ] \
  || { echo "API 認証に失敗しました（API キーを確認してください）" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/ghost-$(date +%Y%m%d-%H%M%S).jsonl"
"${PSQL[@]}" > "$BACKUP" <<SQL
SELECT jsonb_build_object('table','config.user_client','row',to_jsonb(u))
  FROM config.user_client u WHERE ${COND};
SELECT jsonb_build_object('table','config.guest_authorization','row',to_jsonb(a))
  FROM config.guest_authorization a JOIN config.user_client u
    ON u.site_id = a.site_id AND u.mac = a.mac WHERE ${COND};
SQL
echo "バックアップ: $BACKUP ($(grep -c '"table": "config.user_client"' "$BACKUP" || true) 件)"

# サイトごとに forget-sta（管理画面の「クライアントを削除」と同じ処理）
FAILED=0
while IFS='|' read -r SITE MACS; do
  RC=$(api POST "/s/$SITE/cmd/stamgr" "{\"cmd\":\"forget-sta\",\"macs\":$MACS}" | jq -r '.meta.rc // "error"' 2>/dev/null || echo error)
  echo "site=$SITE forget-sta: $(jq length <<< "$MACS") 件 → $RC"
  [ "$RC" = "ok" ] || FAILED=1
done < <("${PSQL[@]}" -c "
  SELECT s.name, json_agg(u.mac) FROM config.user_client u JOIN config.site s ON s.id = u.site_id
  WHERE ${COND} GROUP BY s.name")

[ "$FAILED" -eq 0 ] || { echo "一部の削除に失敗しました" >&2; exit 1; }
echo "完了"
