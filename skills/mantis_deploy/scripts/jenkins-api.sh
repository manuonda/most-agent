#!/usr/bin/env bash
#
# Helpers compartidos por deploy.sh / status.sh / discover.sh.
# Se usa con `source`, no se ejecuta directo.
#
# Credenciales (nunca se imprimen). Orden de resolucion:
#   1. $JENKINS_USER / $JENKINS_API_TOKEN (inyectados por Claude Code desde "env")
#   2. ./.claude/settings.local.json  -> .env.JENKINS_*
#   3. ./.claude/settings.json
#   4. $CLAUDE_CONFIG_DIR/settings.json
#   5. ~/.claude-most/settings.json
#   6. ~/.claude/settings.json

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${JENKINS_DEPLOY_CONFIG:-$SCRIPT_DIR/../config/projects.json}"

die() { printf '%s\n' "ERROR: $1" >&2; exit "${2:-1}"; }

# --- credenciales ------------------------------------------------------------

resolve_setting() {
    # $1 = nombre de la variable en el bloque "env" de los settings
    local name="$1"
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$name" <<'PY'
import json, os, sys

name = sys.argv[1]
paths = [".claude/settings.local.json", ".claude/settings.json"]
cfg = os.environ.get("CLAUDE_CONFIG_DIR")
if cfg:
    paths.append(os.path.join(cfg, "settings.json"))
paths += [os.path.expanduser("~/.claude-most/settings.json"),
          os.path.expanduser("~/.claude/settings.json")]

for path in paths:
    try:
        with open(path) as fh:
            value = json.load(fh).get("env", {}).get(name)
    except Exception:
        continue
    if value:
        print(value)
        break
PY
}

jenkins_init() {
    command -v jq >/dev/null 2>&1 || die "jq no esta instalado (sudo apt install jq)"
    [ -f "$CONFIG_FILE" ] || die "no se encontro la config: $CONFIG_FILE"

    JENKINS_USER="${JENKINS_USER:-$(resolve_setting JENKINS_USER)}"
    JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-$(resolve_setting JENKINS_API_TOKEN)}"

    if [ -z "${JENKINS_USER:-}" ] || [ -z "${JENKINS_API_TOKEN:-}" ]; then
        die "faltan credenciales de Jenkins.
Agregalas bajo \"env\" en ~/.claude-most/settings.json (o .claude/settings.local.json del proyecto):
  \"JENKINS_USER\": \"tu-usuario\",
  \"JENKINS_API_TOKEN\": \"...\"
El token se genera en <jenkins>/user/<tu-usuario>/security/ . Nunca lo pegues en el chat." 3
    fi

    JENKINS_URL="$(jq -r '.jenkins_url' "$CONFIG_FILE")"
    AUTH="$JENKINS_USER:$JENKINS_API_TOKEN"
}

# --- HTTP --------------------------------------------------------------------

# GET con manejo de error legible. Uso: jget <url> [tree-query]
jget() {
    local url="$1" out code body
    out="$(curl -sS -w $'\n%{http_code}' -u "$AUTH" "$url")" || die "no se pudo contactar a Jenkins ($url)" 4
    code="${out##*$'\n'}"
    body="${out%$'\n'*}"
    case "$code" in
        2*) printf '%s\n' "$body"; return 0 ;;
        401) die "HTTP 401 - usuario o token invalido/vencido. Regeneralo en $JENKINS_URL/user/$JENKINS_USER/security/" 4 ;;
        403) die "HTTP 403 - tu usuario no tiene permiso sobre ese job" 4 ;;
        404) die "HTTP 404 - no existe: $url (revisa el anidamiento de carpetas en projects.json)" 4 ;;
        *)   die "HTTP $code al consultar $url" 4 ;;
    esac
}

# --- proyecto ----------------------------------------------------------------

# Deriva la clave del proyecto desde el remote git del cwd.
# Soporta https://git.grupomost.com/producto/geins/web[.git]
#      y git@git.grupomost.com:producto/geins/web[.git]
detect_project_key() {
    local remote
    remote="$(git remote get-url origin 2>/dev/null)" \
        || die "no estas parado en un repo git (o no tiene remote 'origin')"
    remote="${remote%.git}"
    remote="$(printf '%s' "$remote" | sed -E 's#^[a-z]+://##; s#^[^@]+@##; s#^[^/:]+[:/]##')"
    printf '%s\n' "$remote"
}

project_json() {
    local key="$1"
    jq -e --arg k "$key" '.projects[$k]' "$CONFIG_FILE" 2>/dev/null || return 1
}

# URL de una carpeta, soportando anidamiento ("A/B" -> /job/A/job/B).
# Con carpeta vacia devuelve la raiz de Jenkins.
folder_url() {
    local folder="$1" url="$JENKINS_URL" seg
    if [ -n "$folder" ] && [ "$folder" != "null" ]; then
        while IFS= read -r seg; do
            [ -n "$seg" ] && url="$url/job/$seg"
        done < <(printf '%s\n' "$folder" | tr '/' '\n')
    fi
    printf '%s\n' "$url"
}

# URL de un job dentro de una carpeta (la carpeta puede ser vacia).
job_url() {
    printf '%s/job/%s\n' "$(folder_url "$1")" "$2"
}

# Red de seguridad: ningun job productivo se dispara desde aca, este o no
# declarado en projects.json.
assert_not_production() {
    local job="$1"
    case "${job^^}" in
        PROD-*|*-PROD|*-PROD-*|PRODUCCION*|PRODUCTIVO*)
            die "'$job' es un job productivo: no esta habilitado para deploy automatizado.
Produccion se despliega por el proceso manual del equipo de infraestructura." ;;
    esac
}
