#!/usr/bin/env bash
# Table-driven checks for omp-auth-dedupe.py against a throwaway agent.db.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/omp-auth-dedupe.py"
fails=0

mkdb() {
	python3 - "$1" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE auth_credentials (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT NOT NULL,
  credential_type TEXT NOT NULL, data TEXT NOT NULL, disabled_cause TEXT DEFAULT NULL,
  identity_key TEXT DEFAULT NULL, created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0);
INSERT INTO auth_credentials (provider, credential_type, data) VALUES
  ('opencode-go','api_key','{"key":"OLD"}'),
  ('opencode-go','api_key','{"key":"NEW"}'),
  ('anthropic','oauth','{"access":"x"}'),
  ('anthropic','api_key','{"key":"A"}');
""")
c.commit()
PY
}

check() {
	local name="$1" want="$2" got="$3"
	if [ "$want" != "$got" ]; then
		echo "FAIL $name: want=[$want] got=[$got]" >&2
		fails=$((fails + 1))
	else
		echo "ok   $name"
	fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/agent.db"

# dry-run must not modify
mkdb "$db"
python3 "$script" --db "$db" >/dev/null
check "dry-run leaves rows enabled" "0" \
	"$(sqlite3 "$db" "select count(*) from auth_credentials where disabled_cause is not null" 2>/dev/null || python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute('select count(*) from auth_credentials where disabled_cause is not null').fetchone()[0])" "$db")"

# apply: older api_key disabled, newest kept, oauth and other-provider untouched
python3 "$script" --db "$db" --apply >/dev/null
q() { python3 -c "import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone()[0])" "$db" "$2"; }
check "older opencode-go disabled" "1" "$(q x "select count(*) from auth_credentials where id=1 and disabled_cause is not null")"
check "newest opencode-go enabled" "1" "$(q x "select count(*) from auth_credentials where id=2 and disabled_cause is null")"
check "oauth row untouched" "1" "$(q x "select count(*) from auth_credentials where id=3 and disabled_cause is null")"
check "single api_key untouched" "1" "$(q x "select count(*) from auth_credentials where id=4 and disabled_cause is null")"
check "no rows deleted" "4" "$(q x "select count(*) from auth_credentials")"

# idempotent: second apply disables nothing new and makes no backup
before="$(ls "$tmp" | wc -l)"
python3 "$script" --db "$db" --apply >/dev/null
check "second apply is a no-op" "$before" "$(ls "$tmp" | wc -l)"

# missing db is not an error
python3 "$script" --db "$tmp/missing.db" --apply >/dev/null
check "missing db exits 0" "0" "$?"

if [ "$fails" -ne 0 ]; then
	echo "$fails check(s) failed" >&2
	exit 1
fi
echo "all omp-auth-dedupe checks passed"
