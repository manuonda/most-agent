---
name: company_brain
description: "Read and write the team's shared knowledge base of Mantis work (the 'company brain'): what was done, tested, and decided per issue, kept at ~/.claude-most/brain/mantis/<project>/<issue>.md. Trigger: /company_brain <issue-number>, /company_brain publicar <issue-number>, 'estado del mantis X', 'que paso con el mantis X', 'que se hizo en el mantis X', 'subi la nota del mantis X al brain'."
---

# Company Brain

Shared, cross-machine notes about Mantis work. The data lives in the `most-agent` repo (`brain/`) but is always reachable at the same local path, `~/.claude-most/brain/`, via the symlink `install.sh` creates — so it works the same regardless of which Most project/repo is currently active.

## Prerequisites

- `~/.claude-most/brain` must exist (a symlink into `most-agent/brain`, created by `install.sh`). If it's missing (`No such file or directory`), tell the user to run `git pull && ./install.sh` from their `most-agent` clone, then retry.
- Mantis API calls go through `~/.claude-most/bin/mantis-api.sh` (same helper `mantis_develop`/`mantis_comment` use). Never hand-roll `curl`.
- Project folder slug: `issues[0].project.name` from the Mantis API, lowercased, spaces replaced with `-` (e.g. "GEINS YPF" -> `geins-ypf`).
- Note path for issue `<N>`: `~/.claude-most/brain/mantis/<project-slug>/<N>.md`. If the project slug isn't known yet (e.g. querying without context), glob instead: `~/.claude-most/brain/mantis/*/<N>.md`.

## Operations

### 1. Save/update a note (used by `mantis_develop` and `mantis_comment`, or on request)

Create the file if missing, otherwise merge into it (don't blindly overwrite sections the caller isn't updating). Frontmatter:

```yaml
---
mantis: <N>
proyecto: <issues[0].project.name>
estado: <en_progreso | resuelto | cerrado>
fecha_actualizacion: <YYYY-MM-DD>
---
```

Body sections (create empty ones if content isn't available yet): `## Qué se hizo`, `## Notas de testing / pendientes`, `## Resumen enviado a Mantis`.

This step only writes to the local working tree under `~/.claude-most/brain/`. **Never** run `git commit` or `git push` here — that only happens in the "Publish" operation below, on explicit request.

### 2. Query — trigger: `/company_brain <N>`, "estado del mantis X", "que paso con el mantis X"

1. `git -C ~/.claude-most/brain pull` first (read-only, safe) so the answer reflects whatever teammates already published — if it fails (no remote configured, offline, merge conflict), tell the user and continue with what's on disk rather than blocking.
2. Find the note: `~/.claude-most/brain/mantis/*/<N>.md` (glob — don't require knowing the project up front).
3. If no note exists, say so plainly (don't guess); optionally still fetch live status per step 4.
4. Fetch the live status to avoid answering with something stale: `~/.claude-most/bin/mantis-api.sh issue <N>`.
5. Answer combining both: the curated note (what was done/tested/pending) plus the current real status from Mantis. If they disagree (e.g. note says "en_progreso" but Mantis shows "resuelta"), point out the mismatch instead of silently picking one.

### 3. Publish — trigger: `/company_brain publicar <N>`, "subi la nota del mantis X al brain", "publica el brain del mantis X"

Only runs when the user asks for it explicitly by name — never automatically from `mantis_develop`/`mantis_comment` or from the Query operation.

1. `git -C ~/.claude-most/brain status --short` to show the user exactly what would be committed. If there's nothing to publish for this issue, say so.
2. `git -C ~/.claude-most/brain pull --rebase` first, to avoid a needless merge commit / conflict with something a teammate already pushed.
3. Show the diff for the note in question and ask for confirmation before committing.
4. On confirmation: `git -C ~/.claude-most/brain add mantis/<project-slug>/<N>.md && git -C ~/.claude-most/brain commit -m "brain: mantis <N>" && git -C ~/.claude-most/brain push`.
5. Report the result (success, or the exact git error — do not retry blindly on a push rejection; re-`pull --rebase` and ask before retrying).

## Notes

- This skill never decides on behalf of the developer whether to publish — silence means "keep it local for now."
- Keep notes in neutral, professional Spanish — they may be read by other developers, analysts, and project leads.
