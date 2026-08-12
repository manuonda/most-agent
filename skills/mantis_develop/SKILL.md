---
name: mantis_develop
description: "Start working on a Mantis issue: fetches the issue from Mantis via REST API, updates the test branch, creates a git worktree with branch feature/mantis_<nro>, detects the project's Java version from the pom.xml files, plans with the developer, implements, and runs a code review before handing the result back. Trigger: /mantis_develop <issue-number>, 'trabajar el mantis X', 'resolver mantis X'."
---

# Mantis Issue Workflow

Given a Mantis issue number: fetch its details, update the base branch, create an isolated git worktree, agree on a plan with the developer, implement using the project's Java version, and review the result before handing it back.

## Prerequisites

- ALL Mantis API calls go through the helper `~/.claude-most/bin/mantis-api.sh`
  (installed by `install.sh`). Never hand-roll `curl`, `python3` or token-reading
  shell blocks: the helper already resolves the token and is allow-listed as
  `Bash(~/.claude-most/bin/mantis-api.sh:*)`, so it runs without a permission prompt.
  Write the command exactly with that `~/.claude-most/bin/mantis-api.sh` prefix —
  any other form (absolute path, `bash <path>`, extra `env` prefix) breaks the
  allow-list match and makes Claude Code ask again.
- The Mantis API token (Mantis: My Account -> API Tokens -> Create) is per developer,
  configured under `env` as `MANTIS_API_TOKEN` in the Claude config dir settings
  (`$CLAUDE_CONFIG_DIR/settings.json`, e.g. `~/.claude-most/settings.json`) or per
  project in `.claude/settings.local.json` (NOT committed). The helper reads it from
  the environment first and falls back to those files on its own — do NOT read them
  yourself and never echo the token in the conversation.
- Mantis base URL: `https://mantis.grupomost.com` (override with `MANTIS_BASE_URL`).

Error handling for the helper — do NOT work around it with inline `curl`:

- Exit code 3 (`MANTIS_API_TOKEN not found`): stop and tell the user how to configure the token. Never ask the user to paste the token in chat.
- `No such file or directory` (the helper is not installed on this machine): the machine
  is missing the install step. Tell the user to run, from their clone of the `most-agent`
  repo (`https://github.com/manuonda/most-agent`), `git pull && ./install.sh` — that
  links the helper and adds its permission rule. Then retry.

## Steps

### 1. Fetch the issue

```bash
~/.claude-most/bin/mantis-api.sh issue <ISSUE_NUMBER>
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
