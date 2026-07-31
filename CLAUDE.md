# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repository distributes shared Claude Code skills for Grupo Most projects (GEINS YPF, GEINS Producto, and future repos). It contains no application code — only skills and installer scripts.

- `skills/` — one directory per skill, each with a single `SKILL.md` (frontmatter: `name`, `description` with explicit triggers).
  - `mantis_develop` — full workflow to work a Mantis issue: fetch issue via the Mantis REST API (`https://mantis.grupomost.com`), update the `test` base branch, create a git worktree with branch `feature/mantis_0<nro>` (issue number zero-padded to 7 digits), detect the Java version from `pom.xml`, plan, implement, review.
  - `mantis_comment` — summarize work done on a Mantis issue (from Engram topic `mantis/<nro>/develop`, local session file, or git history) and post it as a note via the REST API, with optional attachments.
- `install.sh` / `uninstall.sh` — create/remove symlinks from this repo's `skills/*` into the user's Claude Code skills directory, so skills are maintained here (git) but resolved globally or per-project. Must handle Linux/macOS (`ln -s`) and Windows (mklink/junction or copy fallback).

## Conventions

- Skills are written in English, LLM-first, with explicit trigger phrases in the frontmatter `description` (e.g. `/mantis_develop <issue>`, "trabajar el mantis X").
- `MANTIS_API_TOKEN` is per-developer, stored in each consuming project's `.claude/settings.local.json` under `env` — never committed, never echoed in chat. Skills must keep this contract.
- Editing a skill here changes behavior in every linked project — treat skill edits as breaking-change-sensitive and keep triggers/prerequisites accurate.
- The consuming GEINS repos live at `~/projects/most/geins_ypf/web` and `~/projects/most/geins_producto_ypf/web`, each with its own `CLAUDE.md`.

## Testing changes

There is no build or test suite. To validate a skill change: run `install.sh`, open a Claude Code session in a consuming repo, and trigger the skill (`/mantis_develop <issue>`); verify the symlink resolves and the frontmatter parses.
