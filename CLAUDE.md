# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repository distributes shared Claude Code skills for Grupo Most projects (GEINS YPF, GEINS Producto, and future repos). It contains no application code — only skills and installer scripts.

- `skills/` — one directory per skill, each with a single `SKILL.md` (frontmatter: `name`, `description` with explicit triggers).
  - `mantis_develop` — full workflow to work a Mantis issue: fetch issue via the Mantis REST API (`https://mantis.grupomost.com`), update the `test` base branch, create a git worktree with branch `feature/mantis_0<nro>` (issue number zero-padded to 7 digits), detect the Java version from `pom.xml`, plan, implement, review.
  - `mantis_comment` — summarize work done on a Mantis issue (from Engram topic `mantis/<nro>/develop`, local session file, or git history) and post it as a note via the REST API, with optional attachments.
  - `jenkins_deploy` — trigger/monitor Jenkins deploys (`https://jenkins.grupomost.com`). Unlike the mantis skills it ships its own `scripts/` and `config/` inside the skill dir, so `install.sh`'s existing per-skill symlink carries them along. `scripts/jenkins-api.sh` is a sourced helper (creds + HTTP + project lookup); `deploy.sh`, `status.sh` and `discover.sh` are the three allow-listed entry points.
    - The project is resolved from `git remote get-url origin` (path without host/`.git`, e.g. `producto/geins-ypf/web`), **never** from the local path — every developer clones wherever they want. That key indexes `config/projects.json`, the shared source of truth for folder/job names; each project declares only the environments its Jenkins actually has.
    - Deliberately **no** `Bash(curl:*)` allow rule: with `$JENKINS_API_TOKEN` in the env, arbitrary curl would reach any Jenkins endpoint including the script console. Only the three scripts are allow-listed, so the surface is what's written here.
    - Production is never deployed from here. `PROD-*` jobs are declared under each project's `blocked` block (documented but rejected), and `assert_not_production` in `jenkins-api.sh` rejects production-looking job names even if they are never declared.
- `bin/mantis-api.sh` — single entry point for every Mantis REST call (`issue`, `notes`, `status`, `whoami`). It resolves `MANTIS_API_TOKEN` (env first, then settings files) so the skills never inline `curl`/`python3`. `install.sh` links it into `~/.claude-most/bin/` and adds the allow rule `Bash(~/.claude-most/bin/mantis-api.sh:*)`, which is what keeps the skills prompt-free — the skills must invoke it with exactly that `~/.claude-most/bin/mantis-api.sh` prefix or the permission match breaks.
- `install.sh` / `uninstall.sh` — create/remove symlinks from this repo's `skills/*` into the user's Claude Code skills directory, so skills are maintained here (git) but resolved globally or per-project. Must handle Linux/macOS (`ln -s`) and Windows (mklink/junction or copy fallback).

## Conventions

- Skills are written in English, LLM-first, with explicit trigger phrases in the frontmatter `description` (e.g. `/mantis_develop <issue>`, "trabajar el mantis X").
- `MANTIS_API_TOKEN` is per-developer, stored in each consuming project's `.claude/settings.local.json` under `env` — never committed, never echoed in chat. Skills must keep this contract. Same for `JENKINS_USER` / `JENKINS_API_TOKEN` (generated at `<jenkins>/user/<id>/security/`): per-developer on purpose, so the Jenkins build log records who triggered what.
- Editing a skill here changes behavior in every linked project — treat skill edits as breaking-change-sensitive and keep triggers/prerequisites accurate.
- The consuming GEINS repos live at `~/projects/most/geins_ypf/web` and `~/projects/most/geins_producto_ypf/web`, each with its own `CLAUDE.md`. Careful: on this machine the local directory names do not match the remotes — `geins_ypf/web` is actually `producto/geins-ypflogistica/web`, and GEINS YPF proper is `geins_producto_ypf/web` → `producto/geins-ypf/web`. This is exactly why `jenkins_deploy` keys off the remote.

## Testing changes

There is no build or test suite. To validate a skill change: run `install.sh`, open a Claude Code session in a consuming repo, and trigger the skill (`/mantis_develop <issue>`); verify the symlink resolves and the frontmatter parses.
