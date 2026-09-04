#!/usr/bin/env bash
#
# Mantis REST API helper for the mantis_* skills.
#
# All token resolution and HTTP handling lives here so Claude Code always sees
# ONE stable command instead of an ad-hoc shell script. That makes it
# allow-listable with a single permission rule:
#
#   "Bash(~/.claude-most/bin/mantis-api.sh:*)"
#
# The token is never printed. Resolution order:
#   1. $MANTIS_API_TOKEN (injected by Claude Code from settings "env")
#   2. ./.claude/settings.local.json  -> .env.MANTIS_API_TOKEN
#   3. ./.claude/settings.json
#   4. $CLAUDE_CONFIG_DIR/settings.json
#   5. ~/.claude-most/settings.json
#   6. ~/.claude/settings.json
#
# Usage:
#   mantis-api.sh issue    <issue-number>                  # GET issue (JSON to stdout)
#   mantis-api.sh notes    <issue-number> <note.json>      # POST a note (body from file)
#   mantis-api.sh status   <issue-number> <status-id>      # PATCH issue status
#   mantis-api.sh whoami                                   # check the token works
#   mantis-api.sh download <url-or-path> <output-file>     # GET an attachment (binary) to disk
#                                                           # e.g. a "files"/"attachments" entry
#                                                           # from `issue`'s JSON. Refuses to send
#                                                           # the token to any host other than
#                                                           # $MANTIS_BASE_URL.
#
# Exit codes: 0 ok | 2 bad usage | 3 no token | 4 HTTP error (body on stdout)

set -uo pipefail

BASE_URL="${MANTIS_BASE_URL:-https://mantis.grupomost.com}"

die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

usage() {
    sed -n '19,25p' "$0" | sed 's/^# \{0,1\}//'
}

resolve_token() {
    if [ -n "${MANTIS_API_TOKEN:-}" ]; then
        printf '%s' "$MANTIS_API_TOKEN"
        return 0
    fi
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - <<'PY'
import json, os

paths = [".claude/settings.local.json", ".claude/settings.json"]
cfg = os.environ.get("CLAUDE_CONFIG_DIR")
if cfg:
    paths.append(os.path.join(cfg, "settings.json"))
paths += [os.path.expanduser("~/.claude-most/settings.json"),
          os.path.expanduser("~/.claude/settings.json")]

for path in paths:
    try:
        with open(path) as fh:
            token = json.load(fh).get("env", {}).get("MANTIS_API_TOKEN")
    except Exception:
        continue
    if token:
        print(token)
        break
PY
}

# Runs curl, splits body / status code, reports HTTP errors on stderr.
call() {
    local out code body
    out="$(curl -sS -w $'\n%{http_code}' "$@")" || die "ERROR: curl failed" 4
    code="${out##*$'\n'}"
    body="${out%$'\n'*}"
    printf '%s\n' "$body"
    case "$code" in
        2*) return 0 ;;
        401|403) die "ERROR: HTTP $code - invalid or expired MANTIS_API_TOKEN" 4 ;;
        404)     die "ERROR: HTTP $code - issue not found" 4 ;;
        *)       die "ERROR: HTTP $code" 4 ;;
    esac
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage >&2; exit 2; }
shift

case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
esac

TOKEN="$(resolve_token)"
[ -n "$TOKEN" ] || die "ERROR: MANTIS_API_TOKEN not found. Add it under \"env\" in ~/.claude-most/settings.json or .claude/settings.local.json (never commit it)." 3

case "$cmd" in
    issue)
        [ $# -eq 1 ] || die "usage: mantis-api.sh issue <issue-number>"
        call -H "Authorization: $TOKEN" "$BASE_URL/api/rest/issues/$1"
        ;;
    notes|note)
        [ $# -eq 2 ] || die "usage: mantis-api.sh notes <issue-number> <note.json>"
        [ -f "$2" ] || die "ERROR: file not found: $2"
        call -X POST \
            -H "Authorization: $TOKEN" \
            -H "Content-Type: application/json" \
            --data-binary "@$2" \
            "$BASE_URL/api/rest/issues/$1/notes"
        ;;
    status)
        [ $# -eq 2 ] || die "usage: mantis-api.sh status <issue-number> <status-id>"
        call -X PATCH \
            -H "Authorization: $TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"status\":{\"id\":$2}}" \
            "$BASE_URL/api/rest/issues/$1"
        ;;
    whoami)
        call -H "Authorization: $TOKEN" "$BASE_URL/api/rest/users/me"
        ;;
    download)
        [ $# -eq 2 ] || die "usage: mantis-api.sh download <url-or-path> <output-file>"
        url="$1"; out="$2"
        case "$url" in
            http://*|https://*)
                host="$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')"
                base_host="$(printf '%s' "$BASE_URL" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')"
                [ "$host" = "$base_host" ] || die "ERROR: refusing to send the Mantis token to $host (expected $base_host)" 2
                full_url="$url"
                ;;
            /*)
                full_url="$BASE_URL$url"
                ;;
            *)
                full_url="$BASE_URL/$url"
                ;;
        esac
        mkdir -p "$(dirname "$out")" 2>/dev/null || true
        code="$(curl -sS -H "Authorization: $TOKEN" -o "$out" -w '%{http_code}' "$full_url")" || die "ERROR: curl failed" 4
        case "$code" in
            2*) echo "Saved to $out" ;;
            401|403) rm -f "$out"; die "ERROR: HTTP $code - invalid or expired MANTIS_API_TOKEN" 4 ;;
            404)     rm -f "$out"; die "ERROR: HTTP $code - file not found" 4 ;;
            *)       rm -f "$out"; die "ERROR: HTTP $code" 4 ;;
        esac
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
