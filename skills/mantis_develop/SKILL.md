---
name: mantis_develop
description: "Start working on a Mantis issue: fetches the issue from Mantis via REST API, updates the test branch, creates a git worktree with branch feature/mantis_<nro>, detects the project's Java version from the pom.xml files, plans with the developer, implements, and runs a code review before handing the result back. Trigger: /mantis_develop <issue-number>, 'trabajar el mantis X', 'resolver mantis X'."
---

# Mantis Issue Workflow

Given a Mantis issue number: fetch its details, update the base branch, create an isolated git worktree, agree on a plan with the developer, implement using the project's Java version, and review the result before handing it back.

## Prerequisites

- Environment variable `MANTIS_API_TOKEN` must be set with a Mantis API token
  (Mantis: My Account -> API Tokens -> Create). Each developer uses their own token.
  Recommended: add it under `env` in the Claude config dir settings
  (`$CLAUDE_CONFIG_DIR/settings.json`, e.g. `~/.claude-most/settings.json`) so it
  applies to all projects, or per project in `.claude/settings.local.json` (NOT committed).
- Mantis base URL: `https://mantis.grupomost.com`
- If the variable is NOT in the environment (e.g. the session started before it was
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

If the token is not available in any of these places, stop and tell the user how to configure it. Never ask the user to paste the token in chat.

## Steps

### 1. Fetch the issue

```bash
curl -s -H "Authorization: $MANTIS_API_TOKEN" \
  "https://mantis.grupomost.com/api/rest/issues/<ISSUE_NUMBER>"
```

From the JSON response extract: `issues[0].summary`, `issues[0].description`,
`issues[0].status.label`, `issues[0].project.name`, and any notes in `issues[0].notes[].text`.

If the request fails (401/403 = bad token, 404 = issue not found), report the exact problem and stop.

Present the user a short summary of the issue (number, title, status, description, relevant notes) BEFORE creating any branch or worktree.

### 2. Update the base branch and create the worktree

Branch naming convention in this repo: `feature/mantis_0<ISSUE_NUMBER>` (zero-padded to 7 digits, e.g. issue 200759 -> `feature/mantis_0200759`). Base branch: `test`.

First update `test` so the feature branch starts from the latest code:

```bash
git -C <repo-root> fetch origin test
# If the local test branch exists and is not checked out elsewhere, fast-forward it:
git -C <repo-root> branch -f test origin/test 2>/dev/null || true
```

Then create the worktree with the new branch from the UPDATED test:

```bash
git -C <repo-root> worktree add ../worktrees/mantis_0<ISSUE_NUMBER> -b feature/mantis_0<ISSUE_NUMBER> origin/test
```

- If the branch already exists, add the worktree without `-b` (reuse the branch) and offer the user to rebase it on the updated `origin/test`.
- If the worktree directory already exists, just switch to it — do not recreate.

### 3. Detect the project's Java version (MANDATORY before writing code)

Do NOT trust documentation (CLAUDE.md may be outdated). Read it from the pom.xml files:

```bash
rg -n "<release>|<maven.compiler|<java.version|<source>" <worktree-root> -g 'pom.xml'
```

- Use the detected version (e.g. `<release>17</release>` -> Java 17) as the ceiling for language features.
- Write code idiomatic FOR THAT VERSION: e.g. on Java 17 prefer streams, `var` where it improves readability, switch expressions, text blocks, records for internal DTOs where the codebase style allows — but always match the surrounding code's style first; do not modernize unrelated code.
- Also set the build JVM accordingly, e.g.:
  `export JAVA_HOME=$(ls -d ~/.sdkman/candidates/java/<version>* | head -1)`
- If a dedicated Java-version/modernization skill is available in this session, load it before implementing.

### 4. Build the plan WITH the developer

1. Analyze the issue description against the codebase (search the affected screens, services, DAOs, reports).
2. If ANYTHING in the issue is ambiguous or under-specified — expected behavior, affected screens/environments, business rules, edge cases — ASK the developer for the missing information BEFORE planning. Do not fill gaps with assumptions.
3. Propose a concrete plan: files to touch, approach, risks, how it will be tested. Wait for the developer's OK before editing code.

### 5. Implement (delegate to a Sonnet sub-agent)

Once the plan is approved, delegate the implementation to a sub-agent via the
Agent tool with `model: "sonnet"`. Planning and code review stay in the main
session (most capable model); execution of an already-decided plan is mechanical
and Sonnet is faster and cheaper for it, while keeping file reads/edits out of
the main conversation's context.

The sub-agent prompt MUST include:

- The approved plan, verbatim (files to touch, approach, edge cases decided).
- The worktree path (it must work ONLY inside the worktree) and the detected
  Java version, including the `JAVA_HOME` export.
- Repo conventions: commit message format, build command
  (`mvn clean compile` from `GEINS_Jars`), match surrounding code style.
- Explicit limits: do NOT commit or push; if it hits an ambiguity not covered
  by the plan, stop and return the question instead of deciding on its own.
- Return format: summary of changes per file, build result, and any doubts.

When the sub-agent returns, verify the build result and continue with step 6
in the main session. Do not delegate if the change is trivial (one small file)
— in that case implement inline.

Repo conventions for the implementation:

- Commit messages: `Mantis: <ISSUE_NUMBER> : <short description>` (see git log for style).
- Build from `GEINS_Jars` with the detected JDK: `mvn clean compile` (use `clean` — incremental builds under a wrong JVM can silently no-op).
- Never commit or push without the user's confirmation.

### 6. Code review before handoff (MANDATORY)

Once the code compiles and the change is complete:

1. Run a code review over the diff (use the `/code-review` skill if available in the session; otherwise perform a critical self-review pass over `git diff` focusing on correctness, null-safety, and consistency with the surrounding code).
2. Fix anything the review finds before presenting the result.
3. Present the developer: what changed (per file), why, how it was verified, and any pending doubts. The developer reviews the generated code — if they raise questions, answer them against the actual diff, not from memory.

### 7. Close the work session

When the user says the work is done (or pauses it), persist a session record so the work
can later be summarized and posted to Mantis with the `mantis_comment` skill:

- If Engram (mem_save) is available, save an observation with:
  - `title`: "Mantis <ISSUE_NUMBER>: <short summary of work>"
  - `type`: according to the work done (bugfix, feature -> discovery/decision as fits)
  - `topic_key`: `mantis/<ISSUE_NUMBER>/develop`
  - `content`: What was done, Why, Files changed (paths), pending items, and how it was tested.
- If Engram is NOT available, write the same content to `.claude/mantis-sessions/<ISSUE_NUMBER>.md`
  inside the worktree (not committed unless the user asks).

### 8. Notes

- Never commit or push without the user's confirmation.
- If the issue text is in Spanish, keep code and comments in the project's existing style.
