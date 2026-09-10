#!/usr/bin/env bash
# Shared supermemory client for bash consumers (claude/agy session-start hooks and
# the swarm-memory-sync write pipeline). Replaces the decide.py `memory_context`
# markdown-dump read path with RAG retrieval, and provides an ingest path for the
# knowledge-base write side.
#
# supermemory runs locally (default http://localhost:6767, embeddings local/offline;
# LLM extraction via the OpenCode Go proxy). Config (endpoint + local API key) is read
# from ~/.supermemory/env (parsed with sed, never sourced). Only the loopback endpoint
# is trusted: this client refuses any non-local endpoint outright rather than silently
# falling back to the default, and never follows redirects or leaks partial response
# bodies from a failed transfer.
#
# sm_inject is the only function that masks failures (fail-open, as consumed by
# session-start hooks that must never break on a memory-subsystem hiccup). sm_search,
# sm_ingest and sm_document all return non-zero and print nothing on any failure
# (invalid config, missing tools, transport error, HTTP error, malformed/invalid
# response) so callers that need to know about failures can detect them.
#
# Usage (source this file):
#   . "$ROOT/agent/scripts/hooks/supermemory.sh"
#   ctx="$(sm_inject "$(pwd)" claude-memory)"     # -> plain-text context block (may be empty)
#   sm_ingest <file> <containerTag>               # -> {"id":...,"status":...} JSON, or nothing on failure
#   sm_document <id>                              # -> {"id":...,"status":...,"memories":N} JSON, or nothing on failure
#
# Requires: curl, jq, sha256sum.

# sm__validate_endpoint URL -> exit0 if URL is exactly
#   http://(localhost|127.0.0.1|[::1])(:PORT)?(/)?
# with PORT in 1..65535. Rejects userinfo, path, query, fragment, non-loopback
# hosts, and any other scheme. No normalization/repair is attempted here.
sm__validate_endpoint() {
  local raw="$1"
  local re='^http://(localhost|127\.0\.0\.1|\[::1\])(:([0-9]+))?/?$'
  [[ "$raw" =~ $re ]] || return 1
  local port="${BASH_REMATCH[3]}"
  if [ -n "$port" ]; then
    [ "$port" -ge 1 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null || return 1
  fi
  return 0
}

# sm_endpoint -> validated base URL (no trailing slash), non-zero + no output on
# any invalid configuration. Never silently substitutes the default for a
# configured-but-invalid value.
sm_endpoint() {
  local ep="${SUPERMEMORY_API_URL:-}"
  if [ -z "$ep" ] && [ -f "$HOME/.supermemory/env" ]; then
    ep="$(sed -n 's/^SUPERMEMORY_API_URL=//p' "$HOME/.supermemory/env" | head -1)"
  fi
  [ -z "$ep" ] && ep="http://localhost:6767"
  sm__validate_endpoint "$ep" || return 1
  printf '%s' "${ep%/}"
}

# sm_apikey -> local API key, or empty (optional; supermemory runs unauthenticated
# locally by default). Parsed with sed, the file is never sourced.
sm_apikey() {
  local k="${SUPERMEMORY_API_KEY:-}"
  if [ -z "$k" ] && [ -f "$HOME/.supermemory/env" ]; then
    k="$(sed -n 's/^SUPERMEMORY_API_KEY=//p' "$HOME/.supermemory/env" | head -1)"
  fi
  printf '%s' "$k"
}

# sm__curl METHOD URL TIMEOUT DATA [EXTRA_CURL_ARGS...] -> response body on stdout
# only for an explicit 2xx status (checked via -w, never inferred from curl's own
# exit code alone), non-zero otherwise. -q must stay the first argument to disable
# ~/.curlrc. --noproxy '*' ignores http_proxy/https_proxy/no_proxy. Redirects are
# never followed (no -L), so a 302 with a plausible-looking body is rejected, not
# fetched further. POST data is streamed via stdin (--data-binary @-) rather than
# passed as a curl argv argument, so normal-sized (~200KiB+) documents don't hit
# the OS execve() argv-length limit.
sm__curl() {
  local method="$1" url="$2" timeout="$3" data="$4"
  shift 4
  local -a args=(-q -sS --max-time "$timeout" --noproxy '*' "$@")
  local body_file code rc
  body_file="$(mktemp /tmp/sm-curl-body.XXXXXX)" || return 1
  if [ "$method" = "POST" ]; then
    code="$(printf '%s' "$data" | curl "${args[@]}" -H 'content-type: application/json' -X POST --data-binary @- -o "$body_file" -w '%{http_code}' "$url" 2>/dev/null)"
  else
    code="$(curl "${args[@]}" -o "$body_file" -w '%{http_code}' "$url" 2>/dev/null)"
  fi
  rc=$?
  if [ "$rc" -ne 0 ] || [[ ! "$code" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "$body_file"
    return 1
  fi
  cat "$body_file"
  rm -f "$body_file"
}

# sm__strict_object -> reads a response body on stdin, prints it back compact on
# stdout only if it is *exactly one* JSON object (jq slurp length==1 + type
# check), non-zero otherwise. Rejects malformed JSON and concatenated multi-
# object bodies (e.g. "{...}{...}") that a plain `jq -e` would let through since
# it only inspects the last streamed value.
sm__strict_object() {
  jq -c -s -e 'if (length==1) and (.[0]|type)=="object" then .[0] else empty end' 2>/dev/null
}

# sm__hash_id TAG FILE -> stable full sha256 hex digest derived from tag+file
# content only (independent of the file's name/path), for use as supermemory's
# customId. A NUL byte (never a legal char in either operand here) separates
# tag from content so a newline embedded in either side can't make two distinct
# (tag, content) pairs serialize to the same byte stream.
sm__hash_id() {
  local tag="$1" file="$2"
  { printf '%s\0' "$tag"; cat "$file"; } | sha256sum | awk '{print $1}'
}

# sm_search <query> <tag> <limit> -> validated JSON with a `.results` array on
# stdout; non-zero and no output on any failure (missing tools, invalid config,
# transport/HTTP error, malformed JSON, or a `.results` field that isn't an array).
sm_search() {
  local q="$1" tag="${2:-claude-memory}" limit="${3:-10}"
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local ep key auth=()
  ep="$(sm_endpoint)" || return 1
  key="$(sm_apikey)"
  [ -n "$key" ] && auth=(-H "Authorization: Bearer $key")
  local body
  body="$(jq -nc --arg q "$q" --arg t "$tag" --argjson n "$limit" '{q:$q,containerTags:[$t],limit:$n}' 2>/dev/null)" || return 1
  local resp obj
  resp="$(sm__curl POST "$ep/v4/search" 5 "$body" "${auth[@]}")" || return 1
  obj="$(printf '%s' "$resp" | sm__strict_object)" || return 1
  printf '%s' "$obj" | jq -e '(.results | type) == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$obj"
}

# sm_inject <cwd> <tag> -> plain-text context block for session injection.
# Fail-open by design: any read failure (missing tools, invalid config, transport,
# HTTP error, malformed or partial response) is masked as an exit0 empty string.
sm_inject() {
  local cwd="${1:-$(pwd)}" tag="${2:-claude-memory}"
  command -v jq >/dev/null 2>&1 || return 0
  local project query resp block
  project="$(basename "$cwd" | tr -c 'A-Za-z0-9._-' ' ')"
  query="$project conventions decisions architecture pitfalls preferences"
  resp="$(sm_search "$query" "$tag" 10 2>/dev/null)" || return 0
  [ -z "$resp" ] && return 0
  block="$(printf '%s' "$resp" | jq -r '
    (.results // [])
    | map(.memory // .content // "" | select(length>0))
    | unique
    | if length>0 then "[Relevant Memory (supermemory)]:\n" + (map("- " + .) | join("\n")) else "" end
  ' 2>/dev/null)" || return 0
  printf '%s' "$block"
  return 0
}

# sm_ingest <file> <tag> -> POST the file content to /v3/documents. On acceptance
# (non-empty id + a known non-terminal-or-done status), prints a compact
# {"id":...,"status":...} and returns 0. On any failure (missing file/tools,
# invalid config, transport/HTTP error, malformed response, empty id, or a
# failed/unknown status) prints nothing and returns non-zero. Acceptance never
# implies completion: "queued" (and the other non-terminal statuses) is a valid
# acceptance result, not a claim that ingestion has finished.
sm_ingest() {
  local f="$1" tag="${2:-claude-memory}"
  [ -n "$f" ] && [ -s "$f" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  command -v sha256sum >/dev/null 2>&1 || return 1
  local ep key auth=()
  ep="$(sm_endpoint)" || return 1
  key="$(sm_apikey)"
  [ -n "$key" ] && auth=(-H "Authorization: Bearer $key")
  local title cid body
  title="$(basename "$f")"
  cid="$(sm__hash_id "$tag" "$f")" || return 1
  body="$(jq -nc --rawfile c "$f" --arg t "$tag" --arg title "$title" --arg cid "$cid" \
    '{content:$c, customId:$cid, metadata:{title:$title}, containerTags:[$t]}' 2>/dev/null)" || return 1
  local resp obj
  resp="$(sm__curl POST "$ep/v3/documents" 30 "$body" "${auth[@]}")" || return 1
  obj="$(printf '%s' "$resp" | sm__strict_object)" || return 1
  local id status
  id="$(printf '%s' "$obj" | jq -r '.id? as $v | if ($v|type)=="string" and ($v|length)>0 then $v else empty end' 2>/dev/null)" || return 1
  [ -n "$id" ] || return 1
  status="$(printf '%s' "$obj" | jq -r '.status? // empty' 2>/dev/null)"
  case "$status" in
    queued | extracting | chunking | embedding | indexing | processing | done) ;;
    *) return 1 ;;
  esac
  jq -nc --arg id "$id" --arg st "$status" '{id:$id, status:$st}'
}

# sm_document <id> -> GET /v3/documents/<id>, printing a compact
# {"id":...,"status":...,"memories":N} on stdout, where N is the length of the
# `memories` array (the real API returns an array here, not a count; any other
# type is rejected). A "failed" status is a valid result here (the caller
# inspects it); malformed/concatenated responses, unsafe ids, a response id
# that doesn't match the requested id, and transport/HTTP errors are all
# rejected (non-zero, no output).
sm_document() {
  local id="$1"
  [ -n "$id" ] || return 1
  [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local ep key auth=()
  ep="$(sm_endpoint)" || return 1
  key="$(sm_apikey)"
  [ -n "$key" ] && auth=(-H "Authorization: Bearer $key")
  local resp obj
  resp="$(sm__curl GET "$ep/v3/documents/$id" 10 "" "${auth[@]}")" || return 1
  obj="$(printf '%s' "$resp" | sm__strict_object)" || return 1
  local doc_id status memories
  doc_id="$(printf '%s' "$obj" | jq -r '.id? as $v | if ($v|type)=="string" and ($v|length)>0 then $v else empty end' 2>/dev/null)"
  [ -n "$doc_id" ] && [ "$doc_id" = "$id" ] || return 1
  status="$(printf '%s' "$obj" | jq -r '.status? as $v | if ($v|type)=="string" and ($v|length)>0 then $v else empty end' 2>/dev/null)"
  case "$status" in
    queued | extracting | chunking | embedding | indexing | processing | done | failed) ;;
    *) return 1 ;;
  esac
  # .memories is legitimately absent (null) on many real responses (observed on both
  # "failed" docs with 0 extracted memories AND some "failed" docs that did extract a
  # few before being marked failed overall) -- treat an absent/null field as 0, not as a
  # parse failure. A field that IS present but the wrong type (number/object/string) is
  # still rejected below (falls through to `empty`, which fails the regex).
  memories="$(printf '%s' "$obj" | jq -r '
    if (.memories? | type) == "array" then (.memories | length)
    elif (.memories? | type) == "null" then 0
    else empty end' 2>/dev/null)"
  [[ "$memories" =~ ^[0-9]+$ ]] || return 1
  jq -nc --arg id "$doc_id" --arg st "$status" --argjson mem "$memories" '{id:$id, status:$st, memories:$mem}'
}
