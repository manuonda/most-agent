#!/usr/bin/env bash
#
# Muestra que entornos tiene el repo actual en Jenkins y como quedo el ultimo
# build de cada uno. No dispara nada.
#
# Uso: status.sh [entorno]

set -uo pipefail
# shellcheck source=./jenkins-api.sh
source "$(dirname "${BASH_SOURCE[0]}")/jenkins-api.sh"
jenkins_init

ONLY_ENV="${1:-}"

KEY="$(detect_project_key)"
PROJ="$(project_json "$KEY")" || die "el repo '$KEY' no esta mapeado en projects.json.
Corre discover.sh para listar los jobs disponibles y agregar el bloque."

NAME="$(jq -r '.display_name' <<<"$PROJ")"
FOLDER="$(jq -r '.folder // empty' <<<"$PROJ")"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

echo "Proyecto : $NAME  ($KEY)"
echo "Rama     : $BRANCH"
echo "Entornos disponibles:"
echo

printf '%-10s %-28s %-10s %s\n' "ENTORNO" "JOB" "ULTIMO" "CUANDO / RAMA ESPERADA"
printf '%-10s %-28s %-10s %s\n' "-------" "---" "------" "----------------------"

while IFS=$'\t' read -r env job hint; do
    [ -n "$env" ] || continue
    [ -n "$ONLY_ENV" ] && [ "$env" != "$ONLY_ENV" ] && continue

    if [[ "$job" == TODO-* ]]; then
        printf '%-10s %-28s %-10s %s\n' "$env" "$job" "-" "sin configurar"
        continue
    fi

    BASE="$(job_url "$FOLDER" "$job")"
    INFO="$(curl -sS -u "$AUTH" "$BASE/lastBuild/api/json?tree=number,result,building,timestamp" 2>/dev/null)"
    if RESULT="$(jq -er '.result // (if .building then "EN CURSO" else empty end)' <<<"$INFO" 2>/dev/null)"; then
        NUM="$(jq -r '.number' <<<"$INFO")"
        TS="$(jq -r '.timestamp // 0' <<<"$INFO")"
        WHEN="$( [ "$TS" -gt 0 ] && date -d "@$((TS/1000))" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '-')"
        printf '%-10s %-28s %-10s %s\n' "$env" "$job" "#$NUM $RESULT" "$WHEN   (rama ~ ${hint:--})"
    else
        printf '%-10s %-28s %-10s %s\n' "$env" "$job" "?" "sin builds o sin acceso   (rama ~ ${hint:--})"
    fi
done < <(jq -r '.environments | to_entries[] | [.key, .value.job, (.value.branch_hint // "")] | @tsv' <<<"$PROJ")

BLOCKED="$(jq -r '.blocked // {} | to_entries[] | "  \(.key) -> \(.value)"' <<<"$PROJ")"
if [ -n "$BLOCKED" ]; then
    echo
    echo "Bloqueados (productivos, no se disparan desde aca):"
    printf '%s\n' "$BLOCKED"
fi
