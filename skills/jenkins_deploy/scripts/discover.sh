#!/usr/bin/env bash
#
# Explora Jenkins para dar de alta proyectos nuevos en config/projects.json.
# Solo lee: nunca dispara un build.
#
# Uso:
#   discover.sh                      # carpetas y jobs del raiz (2 niveles)
#   discover.sh <CARPETA>            # jobs dentro de una carpeta
#   discover.sh --params <CARPETA> <JOB>   # parametros que pide ese job
#   discover.sh --suggest <CARPETA>  # bloque JSON listo para pegar, usando el
#                                    # remote del repo actual como clave

set -uo pipefail
# shellcheck source=./jenkins-api.sh
source "$(dirname "${BASH_SOURCE[0]}")/jenkins-api.sh"
jenkins_init

MODE="list"
case "${1:-}" in
    --params)  MODE="params";  shift ;;
    --suggest) MODE="suggest"; shift ;;
esac

case "$MODE" in
    list)
        FOLDER="${1:-}"
        if [ -z "$FOLDER" ]; then
            echo "Carpetas y jobs en $JENKINS_URL"
            echo
            jget "$JENKINS_URL/api/json?tree=jobs[name,_class,jobs[name,_class]]" \
                | jq -r '.jobs[]
                    | if (._class | test("Folder")) then
                        "[carpeta] \(.name)" + (
                          (.jobs // []) | map("\n            - \(.name)") | join("")
                        )
                      else "[job]     \(.name)" end'
        else
            echo "Jobs en la carpeta '$FOLDER'"
            echo
            URL="$(folder_url "$FOLDER")"
            jget "$URL/api/json?tree=jobs[name,_class]" \
                | jq -r '.jobs[] | "  - \(.name)"'
        fi
        ;;

    params)
        FOLDER="${1:?falta la carpeta}"; JOB="${2:?falta el job}"
        BASE="$(job_url "$FOLDER" "$JOB")"
        echo "Parametros de ${FOLDER:+$FOLDER » }$JOB"
        echo
        OUT="$(jget "$BASE/api/json?tree=property[parameterDefinitions[name,type,defaultParameterValue[value]]]" \
            | jq -r '[.property[]? | select(.parameterDefinitions) | .parameterDefinitions[]][]
                     | "  - \(.name)  [\(.type)]  default: \(.defaultParameterValue.value // "(ninguno)")"')"
        if [ -n "$OUT" ]; then
            printf '%s\n' "$OUT"
        else
            echo "  (el job no tiene parametros)"
        fi
        ;;

    suggest)
        FOLDER="${1:?falta la carpeta}"
        KEY="$(detect_project_key)"
        URL="$(folder_url "$FOLDER")"
        JOBS="$(jget "$URL/api/json?tree=jobs[name]" | jq -r '.jobs[].name')"

        pick() { printf '%s\n' "$JOBS" | grep -iE "$1" | grep -viE 'prod' | head -1; }
        TEST="$(pick 'test')";    TEST="${TEST:-TODO-completar}"
        DEMO="$(pick 'demo')";    DEMO="${DEMO:-TODO-completar}"
        REL="$(pick 'release')";  REL="${REL:-TODO-completar}"

        echo "Jobs encontrados en '$FOLDER':"
        printf '%s\n' "$JOBS" | sed 's/^/  - /'
        echo
        echo "Bloque sugerido para config/projects.json (revisalo antes de pegar):"
        echo
        jq -n --arg key "$KEY" --arg folder "$FOLDER" \
              --arg test "$TEST" --arg demo "$DEMO" --arg rel "$REL" \
              --argjson blocked "$(printf '%s\n' "$JOBS" | grep -iE 'prod' \
                    | jq -R . | jq -s 'map({key: (.|ascii_downcase), value: .}) | from_entries')" '
            { ($key): {
                display_name: "TODO",
                folder: $folder,
                verified: true,
                environments: {
                  test:    { job: $test, branch_hint: "develop" },
                  demo:    { job: $demo, branch_hint: "develop" },
                  release: { job: $rel,  branch_hint: "release", confirm: true }
                }
              } + (if ($blocked | length) > 0 then {blocked: $blocked} else {} end)
            }'
        ;;
esac
