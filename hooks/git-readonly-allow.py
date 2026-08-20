#!/usr/bin/env python3
"""PreToolUse/Bash hook: auto-aprueba comandos git de solo lectura.

Claude Code pregunta por cada `cd <otro-repo> && git show ...`, por cada bucle
`for` y por cada `<(...)` porque no puede matchearlos estaticamente contra una
regla de permisos. Durante /mantis_develop eso es casi toda la sesion: la skill
lee historia del *otro* repo GEINS todo el tiempo (ver CLAUDE.md: los nombres
locales no coinciden con los remotes, se cruza de repo constantemente).

El hook parsea el comando y responde "allow" SOLO si cada segmento es una
inspeccion de solo lectura dentro de $MOST_PROJECTS_DIR. Cualquier otra cosa
-- una escritura de git, un binario desconocido, una redireccion a un archivo
real -- no produce salida, asi que vuelve a aparecer el prompt normal.

Nunca responde "deny": el fallback siempre es preguntar, jamas bloquear. Ante
cualquier duda (comillas sin cerrar, backticks, token raro) devuelve silencio.
"""

import json
import os
import shlex
import sys

# --- superficie permitida -----------------------------------------------------

# Subcomandos git que no tocan el working tree ni el repo.
GIT_SAFE = {
    "log", "show", "diff", "status", "blame", "annotate", "grep",
    "rev-parse", "rev-list", "ls-files", "ls-tree", "ls-remote", "cat-file",
    "describe", "shortlog", "show-ref", "for-each-ref", "name-rev",
    "merge-base", "whatchanged", "count-objects", "symbolic-ref", "cherry",
    "diff-tree", "diff-index", "check-ignore", "verify-commit", "version",
    "help",
    # fetch solo actualiza refs de remote-tracking: no puede perder trabajo, y
    # mantis_develop lo necesita para refrescar `test` antes del worktree.
    "fetch",
}

# Subcomandos que son de lectura o de escritura segun los flags: se revisan aparte.
GIT_GUARDED = {"branch", "remote", "worktree", "tag", "config", "stash", "reflog",
               "notes", "submodule"}

BRANCH_WRITE_FLAGS = {"-d", "-D", "-m", "-M", "-c", "-C", "-f", "--delete",
                      "--move", "--copy", "--force", "--set-upstream",
                      "--set-upstream-to", "-u", "--unset-upstream",
                      "--edit-description"}

CONFIG_READ_FLAGS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch",
                     "--list", "-l"}
CONFIG_WRITE_FLAGS = {"--add", "--unset", "--unset-all", "--replace-all",
                      "--edit", "-e", "--rename-section", "--remove-section"}

# Flags de git que ejecutan binarios externos o escriben archivos, en cualquier
# subcomando. `git diff --output=f` escribe; `--ext-diff`/`--upload-pack`/`-O`
# ejecutan programas arbitrarios.
GIT_DANGEROUS_ARGS = ("--output", "--ext-diff", "--exec", "--upload-pack",
                      "--receive-pack", "--open-files-in-pager", "--index-output",
                      "--to-file")

# Filtros de solo lectura que aparecen en los pipes. Deliberadamente NO estan
# sed/awk/perl/python (escriben archivos), xargs/find (ejecutan comandos),
# ni tee/dd (escriben).
FILTERS = {"head", "tail", "cat", "tac", "wc", "sort", "uniq", "cut", "tr",
           "nl", "rev", "echo", "printf", "true", "false", "diff", "comm",
           "column", "fold", "paste", "join", "basename", "dirname", "grep",
           "egrep", "fgrep", "rg", "less", "more", "od", "xxd", "file", "stat",
           "date", "pwd", "ls"}

# Palabras de control del shell: no ejecutan nada por si mismas.
CONTROL = {"do", "done", "then", "else", "fi", "esac", "{", "}", "time", "!"}
CONTROL_PREFIX = {"if", "elif", "while", "until", "case"}

# shlex agrupa las corridas de estos caracteres en un solo token: `<(`, `&&`,
# `||`, `2>&1`... Un token compuesto SOLO por ellos es un operador del shell y
# corta el segmento; si tiene cualquier otro caracter es una palabra normal
# (p.ej. el pathspec de git `:(exclude)GEINS_E2E`, que no debe cortar nada).
OPERATOR_CHARS = set("();<>|&")
WORD_SEPARATORS = {"{", "}", "$"}
REDIR_TARGETS_OK = {"/dev/null", "1", "2", "&1", "&2"}


def is_operator(token):
    return bool(token) and all(char in OPERATOR_CHARS for char in token)


def allowed_roots():
    """Raices bajo las que se puede hacer `cd` / `git -C`."""
    roots = []
    marker = os.path.expanduser("~/.claude-most/most-projects-dir")
    try:
        with open(marker) as fh:
            value = fh.read().strip()
            if value:
                roots.append(value)
    except OSError:
        pass
    if not roots:
        roots.append(os.path.expanduser("~/projects/most"))
    roots.append(os.getcwd())
    return [os.path.realpath(os.path.expanduser(r)) for r in roots]


def under_roots(path):
    if not path or path.startswith("-"):
        return False
    candidate = os.path.realpath(os.path.expanduser(path))
    for root in allowed_roots():
        if candidate == root or candidate.startswith(root + os.sep):
            return True
    return False


def git_ok(tokens):
    index = 0
    # Opciones globales de git, antes del subcomando.
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        if option == "-C":
            if index + 1 >= len(tokens) or not under_roots(tokens[index + 1]):
                return False
            index += 2
            continue
        if option in ("--no-pager", "-P"):
            index += 1
            continue
        # -c core.pager=..., --exec-path, --git-dir: demasiado poderosas.
        return False

    if index >= len(tokens):
        return False
    sub, rest = tokens[index], tokens[index + 1:]

    for arg in rest:
        if arg == "-O" or any(bad in arg for bad in GIT_DANGEROUS_ARGS):
            return False

    if sub in GIT_SAFE:
        return True
    if sub not in GIT_GUARDED:
        return False

    if sub == "branch":
        return not any(arg in BRANCH_WRITE_FLAGS for arg in rest)
    if sub == "remote":
        return not rest or rest[0] in ("-v", "--verbose", "show", "get-url")
    if sub == "worktree":
        return bool(rest) and rest[0] == "list"
    if sub == "tag":
        return not rest or "-l" in rest or "--list" in rest
    if sub == "config":
        if any(arg in CONFIG_WRITE_FLAGS for arg in rest):
            return False
        return any(arg in CONFIG_READ_FLAGS for arg in rest)
    if sub == "stash":
        return bool(rest) and rest[0] in ("list", "show")
    if sub == "reflog":
        return not rest or rest[0] == "show"
    if sub == "notes":
        return bool(rest) and rest[0] in ("list", "show")
    if sub == "submodule":
        return bool(rest) and rest[0] == "status"
    return False


def command_ok(tokens):
    if not tokens:
        return True
    head = tokens[0]
    if head == "cd":
        return len(tokens) >= 2 and under_roots(tokens[1])
    if head in FILTERS:
        return True
    if head == "git":
        return git_ok(tokens[1:])
    # El hook de RTK reescribe `git status` -> `rtk git status`; aceptamos ambas
    # formas para que el resultado no dependa del orden de los hooks.
    if head in ("rtk", "command"):
        rest = tokens[1:]
        if rest and rest[0] == "proxy":
            rest = rest[1:]
        return bool(rest) and command_ok(rest)
    return False


def segment_ok(tokens):
    tokens = list(tokens)
    while tokens and (tokens[0] in CONTROL or tokens[0] in CONTROL_PREFIX):
        tokens = tokens[1:]
    if not tokens:
        return True
    # Cabecera de bucle (`for c in a b c`): es una lista de palabras, no ejecuta
    # nada. Cualquier $(...) adentro ya fue separado en su propio segmento.
    if tokens[0] in ("for", "select"):
        return True
    return command_ok(tokens)


def is_readonly(command):
    if not command or "`" in command:
        return False
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return False

    segments, current = [], []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if is_operator(token):
            if ">" in token:
                # Redireccion de salida: solo se tolera descartar o unir fds.
                target = tokens[index + 1] if index + 1 < len(tokens) else None
                if target not in REDIR_TARGETS_OK:
                    return False
                index += 2
                continue
            if token == "<":
                index += 2  # `< archivo`: lectura, se ignora el nombre
                continue
            # `(`, `)`, `<(`, `|`, `||`, `&&`, `;`, `&`: cortan el segmento, y el
            # interior de la sustitucion queda como segmento propio a validar.
            segments.append(current)
            current = []
            index += 1
            continue
        if token in WORD_SEPARATORS:
            segments.append(current)
            current = []
            index += 1
            continue
        current.append(token)
        index += 1
    segments.append(current)

    return all(segment_ok(segment) for segment in segments)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    command = payload.get("tool_input", {}).get("command", "")
    try:
        approved = is_readonly(command)
    except Exception:
        approved = False
    if approved:
        json.dump({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "git de solo lectura (hook most-agent)",
        }}, sys.stdout)


if __name__ == "__main__":
    main()
