#!/usr/bin/env bash
#
# Devuelve la URL de test del proyecto actual, leyendo la "description" del
# job TEST-* en Jenkins (el equipo la deja publicada ahi, ej.
# https://test-geins-ypf.grupomost.com/most-geins). No dispara builds ni
# escribe nada en Jenkins.
#
# Uso: preview-url.sh
#
# Reusa la config y las credenciales de mantis_deploy (mismo Jenkins, mismo
# mapeo proyecto->job) para no duplicar ese estado.

set -uo pipefail

DEPLOY_HELPERS="$HOME/.claude-most/skills/mantis_deploy/scripts/jenkins-api.sh"
if [ ! -f "$DEPLOY_HELPERS" ]; then
    echo "ERROR: no se encontro $DEPLOY_HELPERS (falta instalar mantis_deploy). Corre: git pull && ./install.sh" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$DEPLOY_HELPERS"
jenkins_init

KEY="$(detect_project_key)"
PROJ="$(project_json "$KEY")" || die "el repo '$KEY' no esta mapeado en config/projects.json de mantis_deploy.
Corre ~/.claude-most/skills/mantis_deploy/scripts/discover.sh para completarlo."

NAME="$(jq -r '.display_name' <<<"$PROJ")"
FOLDER="$(jq -r '.folder // empty' <<<"$PROJ")"
JOB="$(jq -r '.environments.test.job // empty' <<<"$PROJ")"
[ -n "$JOB" ] && [[ "$JOB" != TODO-* ]] || die "el entorno 'test' de $NAME todavia no esta configurado en projects.json (corre discover.sh)."

BASE="$(job_url "$FOLDER" "$JOB")"
DESC="$(jget "$BASE/api/json?tree=description" | jq -r '.description // empty')"

URL="$(printf '%s' "$DESC" | grep -oE 'https?://[A-Za-z0-9._~%-]+(/[A-Za-z0-9._~%/?#=&+-]*)?' | head -n1)"
[ -n "$URL" ] || die "el job $JOB no tiene una URL publicada en su descripcion de Jenkins ($BASE). Pedile al equipo que la agregue (Configure > Description)."

echo "Proyecto : $NAME"
echo "Entorno  : test"
echo "URL      : $URL"
