---
name: mantis_comment
description: "Summarize the work done on a Mantis issue and post it as a note to Mantis via REST API, optionally attaching files. Reads the work session saved by mantis_develop (Engram or local session file). Trigger: /mantis_comment <issue-number> [files...], 'comentar el mantis X', 'agregar nota al mantis X'."
---

# Mantis Comment Workflow

Build a summary of the work done on a Mantis issue, get the user's approval, then post it as a note on the issue — optionally with file attachments.

## Prerequisites

- Environment variable `MANTIS_API_TOKEN` must be set (same as `mantis_develop`).
  It is configured per developer under `env`, either in the Claude config dir settings
  (`$CLAUDE_CONFIG_DIR/settings.json`, e.g. `~/.claude-most/settings.json` — applies to
  all projects) or in the project's `.claude/settings.local.json` (NOT committed):

  ```json
  {
    "env": {
      "MANTIS_API_TOKEN": "<token>"
    }
  }
  ```

  Claude Code injects it into the session environment; read it from `$MANTIS_API_TOKEN`.
  If the variable is NOT in the environment (e.g. the session started before it was
  configured), read it from the settings files — project-local first, then the config
  dir — the developer has explicitly authorized this; do NOT ask for permission and
  do NOT echo the token value in the conversation:

  ```bash
  TOKEN=$(python3 - <<'EOF'
import json, os
for path in [".claude/settings.local.json",
             os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude")), "settings.json")]:
    try:
        token = json.load(open(path)).get("env", {}).get("MANTIS_API_TOKEN")
        if token:
            print(token)
            break
    except OSError:
        pass
EOF
)
  ```
- Mantis base URL: `https://mantis.grupomost.com`

If the token is not available in any of these places, stop and tell the user how to configure it. Never ask for the token in chat.

## Steps

### 1. Gather the work context

Collect what was worked on for the issue, in this order:

1. Engram (if available): `mem_search` for topic `mantis/<ISSUE_NUMBER>/develop` and read the full observation.
2. Local session file: `.claude/mantis-sessions/<ISSUE_NUMBER>.md` in the repo/worktree.
3. Git history: `git log --oneline` and `git diff --stat` of branch `feature/mantis_0<ISSUE_NUMBER>` against its base.
4. The current conversation, if the work happened in this session.

### 2. Draft the note

Write the note in neutral, professional Spanish (it is read by the team and the client).

The note is a WORK summary, not a technical changelog: describe what was worked on
in functional terms (what the user/client gains, what behavior changed), NOT files,
classes, or implementation details. Do NOT include a "modified files" section.

Structure:

```
Resumen del trabajo:

- <qué se trabajó, en términos funcionales, punto por punto>

Scripts adjuntos (si aplica):
- <nombre del script> — <para qué sirve y dónde se ejecuta (test / producción)>

Pendiente (si aplica):
- <items pendientes>
```

### 2b. Detect scripts in the commit(s)

If the user passed a commit (or the branch has commits), list its files
(`git show --stat <commit>`). Any SQL/config/deploy script found (e.g. under
`GEINS_DBScripts/` or `*.sql`) MUST be attached to the note. Extract each script
from the commit (`git show <commit>:<path>`) into the scratchpad directory, and
describe in the note what each one is for and where it should be run.

### 2c. Ask for hours worked (MANDATORY)

Ask the user how many hours were worked on the issue (if they did not already say).
Include them in the note payload via Mantis time tracking:

```json
{
  "text": "...",
  "time_tracking": { "duration": "HH:MM" }
}
```

Also mention the hours at the end of the note text (e.g. `Horas trabajadas: 4:00`).

### 3. Ask for approval (MANDATORY)

Show the full draft to the user and ask whether to post it as-is, edit it, or cancel.
Do NOT post anything to Mantis without an explicit OK. List the files that will be attached, if any.

### 4. Post the note

```bash
curl -s -X POST -H "Authorization: $MANTIS_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://mantis.grupomost.com/api/rest/issues/<ISSUE_NUMBER>/notes" \
  -d @note.json
```

`note.json` (build it in the scratchpad directory, never in the repo):

```json
{
  "text": "<the approved note text>"
}
```

With attachments, add a `files` array — each file base64-encoded:

```json
{
  "text": "<the approved note text>",
  "files": [
    { "name": "<filename>", "content": "<base64 of the file>" }
  ]
}
```

Generate the base64 with `base64 -w0 <file>`. Verify each file exists and show its size to the user before attaching; warn if a file is larger than ~5 MB (Mantis upload limits).

### 4b. Change the issue status to "resuelta" when applicable

If the note states that the work is resolved / ready for testing ("resuelto",
"disponible para testear", "listo para prueba"), ALSO change the issue status
to **resuelta** (id 80) right after posting the note:

```bash
curl -s -X PATCH -H "Authorization: $MANTIS_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://mantis.grupomost.com/api/rest/issues/<ISSUE_NUMBER>" \
  -d '{"status":{"id":80}}'
```

Status ids in this Mantis: 10 nueva, 20 se necesitan más datos, 30 aceptada,
40 confirmada, 60 tested, 80 resuelta, 90 cerrada.

Report the resulting status to the user. If the note is informative only (not a
resolution), do NOT change the status.

### 5. Confirm the result

- On HTTP 201: report success and show the note id from the response.
- On error (401/403 token, 404 issue, 413 attachment too large): report the exact cause and do not retry blindly.
- If Engram is available, save an observation under topic `mantis/<ISSUE_NUMBER>/comment` recording that the note was posted and its content.
