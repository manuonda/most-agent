#!/usr/bin/env bash
#
# Git credential helper for git.grupomost.com, backed by env vars instead of
# an on-disk store (~/.git-credentials) or an interactive prompt. This is what
# lets mantis_develop run `git fetch origin test` non-interactively when
# updating the base branch before creating a worktree.
#
# Wire it up ONCE, scoped to that host only (never touches credentials for any
# other remote):
#
#   git config --global credential."https://git.grupomost.com".helper \
#     "!~/.claude-most/bin/git-credential-env.sh"
#
# (install.sh does this automatically and is idempotent.)
#
# Then set, per developer, in .claude/settings.local.json under "env" (never
# committed) or in the shell profile:
#
#   GIT_GRUPOMOST_USER   the grupomost git username
#   GIT_GRUPOMOST_TOKEN  a personal access token (git.grupomost.com -> user
#                        settings -> access tokens), NOT the account password
#
# Implements only the `get` operation of the git-credential protocol. `store`
# and `erase` are no-ops on purpose: the source of truth is the env var, there
# is nothing on disk to update, and this helper must never write the token
# anywhere.

set -uo pipefail

op="${1:-get}"

# git always sends protocol=/host=/... on stdin, even for store/erase; drain
# it in every case so git never blocks on a full pipe.
cat >/dev/null

case "$op" in
    get)
        [ -n "${GIT_GRUPOMOST_USER:-}" ] || exit 0
        [ -n "${GIT_GRUPOMOST_TOKEN:-}" ] || exit 0
        printf 'username=%s\n' "$GIT_GRUPOMOST_USER"
        printf 'password=%s\n' "$GIT_GRUPOMOST_TOKEN"
        ;;
    *)
        exit 0
        ;;
esac
