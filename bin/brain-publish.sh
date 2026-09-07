#!/usr/bin/env bash
#
# Publishes (commit+push) ONE issue's company-brain note automatically, for
# the skills that already got their own upstream approval for this content:
#   - mantis_comment: the note text was approved by the developer before
#     posting it to Mantis (it's already team-visible there).
#   - mantis_deploy: a deploy result is a factual status, not content that
#     needs review before the team sees it.
#
# It does nothing (exit 0) when there is no local note for the issue, or the
# note has no pending changes. It never force-pushes: on a pull --rebase or
# push failure it stops and reports, leaving the note committed-or-not as it
# was, so the caller can point the developer at `/company_brain publicar <N>`.
#
# Usage: brain-publish.sh <issue-number> [commit-message]
#
# Exit codes: 0 ok (published or nothing to do) | 1 bad usage / missing brain
#             dir | 2 pull --rebase failed | 3 push failed

set -uo pipefail

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

ISSUE="${1:-}"
[ -n "$ISSUE" ] || die "uso: brain-publish.sh <issue-number> [mensaje]"
MSG="${2:-brain: mantis $ISSUE}"

BRAIN_DIR="$HOME/.claude-most/brain"
[ -d "$BRAIN_DIR" ] || die "no existe $BRAIN_DIR (falta instalar most-agent: git pull && ./install.sh)"

NOTE="$(find "$BRAIN_DIR/mantis" -mindepth 2 -maxdepth 2 -type f -name "${ISSUE}.md" 2>/dev/null | head -n1)"
if [ -z "$NOTE" ]; then
    echo "Sin nota local para el mantis $ISSUE: nada que publicar."
    exit 0
fi
RELPATH="${NOTE#"$BRAIN_DIR"/}"

if ! git -C "$BRAIN_DIR" pull --rebase; then
    die "git pull --rebase fallo en $BRAIN_DIR. La nota queda local; resolve (conflicto/red) y reintenta con /company_brain publicar $ISSUE." 2
fi

if [ -z "$(git -C "$BRAIN_DIR" status --porcelain -- "$RELPATH")" ]; then
    echo "Nota de mantis $ISSUE sin cambios pendientes: nada que publicar."
    exit 0
fi

git -C "$BRAIN_DIR" add "$RELPATH"
git -C "$BRAIN_DIR" commit -m "$MSG"
if ! git -C "$BRAIN_DIR" push; then
    die "push rechazado en $BRAIN_DIR. La nota quedo commiteada localmente; resolve (pull --rebase manual) y reintenta con /company_brain publicar $ISSUE." 3
fi

echo "OK: brain de mantis $ISSUE publicado ($RELPATH)."
