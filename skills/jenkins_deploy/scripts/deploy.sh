#!/usr/bin/env bash
#
# Dispara un build en Jenkins para el repo donde estas parado.
#
# Uso: deploy.sh <entorno> [--wait] [--yes] [-p CLAVE=VALOR ...]
#   <entorno>  uno de los definidos para el proyecto (test | demo | release ...)
#   --wait     espera a que termine y devuelve el resultado
#   --yes      salta la confirmacion tipeada (NO usar desde el agente)
#   -p         parametro del job, repetible

set -uo pipefail
# shellcheck source=./jenkins-api.sh
source "$(dirname "${BASH_SOURCE[0]}")/jenkins-api.sh"
jenkins_init

ENV="${1:-}"
[ -n "$ENV" ] || die "uso: deploy.sh <entorno> [--wait] [--yes] [-p CLAVE=VALOR]"
shift

WAIT=false
ASSUME_YES=false
PARAMS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --wait) WAIT=true ;;
        --yes|-y) ASSUME_YES=true ;;
        -p) shift; [ $# -gt 0 ] || die "-p necesita CLAVE=VALOR"; PARAMS+=(--data-urlencode "$1") ;;
        *) die "opcion desconocida: $1" ;;
    esac
    shift
done

KEY="$(detect_project_key)"
PROJ="$(project_json "$KEY")" || die "el repo '$KEY' no esta mapeado en projects.json.
Corre discover.sh para listar los jobs y agregar el bloque correspondiente."

NAME="$(jq -r '.display_name' <<<"$PROJ")"
FOLDER="$(jq -r '.folder // empty' <<<"$PROJ")"

# Entorno declarado como bloqueado (productivo)
if jq -e --arg e "$ENV" '.blocked[$e] // empty' <<<"$PROJ" >/dev/null 2>&1; then
    die "el entorno '$ENV' es productivo y no esta habilitado para deploy automatizado.
Produccion se despliega por el proceso manual del equipo de infraestructura."
fi

ENVJSON="$(jq -e --arg e "$ENV" '.environments[$e]' <<<"$PROJ" 2>/dev/null)" || die \
    "el entorno '$ENV' no existe en $NAME. Disponibles: $(jq -r '.environments|keys|join(", ")' <<<"$PROJ")"

JOB="$(jq -r '.job' <<<"$ENVJSON")"
[[ "$JOB" == TODO-* ]] && die "el job de '$ENV' todavia no esta configurado en projects.json (corre discover.sh)"
assert_not_production "$JOB"

HINT="$(jq -r '.branch_hint // empty' <<<"$ENVJSON")"
NEEDS_CONFIRM="$(jq -r '.confirm // false' <<<"$ENVJSON")"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
DIRTY=""
if ! git diff --quiet || ! git diff --cached --quiet; then
    DIRTY="  (!) hay cambios sin commitear"
fi
UNPUSHED=""
if UP="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"; then
    AHEAD="$(git rev-list --count "$UP"..HEAD 2>/dev/null || echo 0)"
    [ "${AHEAD:-0}" -gt 0 ] && UNPUSHED="  (!) $AHEAD commit(s) sin pushear"
else
    UNPUSHED="  (!) la rama no tiene upstream"
fi

BASE="$(job_url "$FOLDER" "$JOB")"

echo "-- Deploy --------------------------"
echo "Proyecto : $NAME"
echo "Entorno  : $ENV"
echo "Job      : ${FOLDER:+$FOLDER » }$JOB"
echo "Rama     : $BRANCH$DIRTY$UNPUSHED"
if [ -n "$HINT" ] && [[ "$BRANCH" != *"$HINT"* ]]; then
    echo "(!) Se esperaba una rama tipo '$HINT'"
fi
echo "URL      : $BASE"
echo "------------------------------------"

if [ "$NEEDS_CONFIRM" = "true" ] && [ "$ASSUME_YES" != true ]; then
    read -rp "Confirmas el deploy a $ENV? (escribi '$ENV'): " ans
    [ "$ans" = "$ENV" ] || die "cancelado por el usuario"
fi

# El API token de Jenkins exime de CSRF; el crumb se pide igual por si el
# servidor lo requiere, y si falla se sigue sin el.
CRUMB="$(curl -sS -u "$AUTH" "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null | jq -r '.crumb // empty' 2>/dev/null || true)"
HDR=()
[ -n "$CRUMB" ] && HDR=(-H "Jenkins-Crumb: $CRUMB")

# Job parametrizado -> buildWithParameters
JOBINFO="$(jget "$BASE/api/json?tree=property[parameterDefinitions[name,type,defaultParameterValue[value]]]")"
NPARAMS="$(jq '[.property[]? | select(.parameterDefinitions) | .parameterDefinitions[]] | length' <<<"$JOBINFO")"
ENDPOINT="build"
if [ "${NPARAMS:-0}" -gt 0 ]; then
    ENDPOINT="buildWithParameters"
    if [ ${#PARAMS[@]} -eq 0 ]; then
        echo "Parametros del job (se usan los valores por defecto):"
        jq -r '[.property[]? | select(.parameterDefinitions) | .parameterDefinitions[]][]
               | "  - \(.name) = \(.defaultParameterValue.value // "(sin default)")"' <<<"$JOBINFO"
    fi
fi

HTTP="$(curl -sS -o /dev/null -D - -w $'\n%{http_code}' -X POST -u "$AUTH" "${HDR[@]}" \
        ${PARAMS[@]+"${PARAMS[@]}"} "$BASE/$ENDPOINT")" || die "no se pudo contactar a Jenkins" 4
CODE="${HTTP##*$'\n'}"
QUEUE="$(printf '%s' "$HTTP" | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')"

case "$CODE" in
    2*) : ;;
    401) die "HTTP 401 - usuario o token invalido/vencido. Regeneralo en $JENKINS_URL/user/$JENKINS_USER/security/" 4 ;;
    403) die "HTTP 403 - tu usuario no tiene permiso de Build sobre $JOB" 4 ;;
    404) die "HTTP 404 - el job no existe: $BASE (revisa folder/job en projects.json)" 4 ;;
    *)   die "HTTP $CODE al encolar el build" 4 ;;
esac
[ -n "$QUEUE" ] || die "Jenkins no devolvio la URL de cola" 4

echo "OK Encolado: $QUEUE"

BUILD=""
for _ in $(seq 1 40); do
    BUILD="$(curl -sS -u "$AUTH" "${QUEUE}api/json" 2>/dev/null | jq -r '.executable.number // empty' 2>/dev/null || true)"
    [ -n "$BUILD" ] && break
    sleep 3
done
if [ -z "$BUILD" ]; then
    echo "Sigue en cola (ejecutor ocupado). Segui el avance en: $BASE"
    exit 0
fi

echo "Build #$BUILD -> $BASE/$BUILD/console"
[ "$WAIT" != true ] && exit 0

echo "Esperando a que termine..."
RESULT=""
while :; do
    RESULT="$(curl -sS -u "$AUTH" "$BASE/$BUILD/api/json?tree=result" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)"
    [ -n "$RESULT" ] && break
    sleep 10
done
echo "Resultado: $RESULT"
echo "Consola  : $BASE/$BUILD/console"
[ "$RESULT" = "SUCCESS" ]
