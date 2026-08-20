#!/usr/bin/env bash
#
# Install Most shared Claude Code skills by symlinking skills/* into a
# Claude Code config directory.
#
# Usage:
#   ./install.sh                     # installs into $CLAUDE_CONFIG_DIR/skills or ~/.claude-most/skills
#   ./install.sh /path/to/config     # installs into /path/to/config/skills
#   CLAUDE_CONFIG_DIR=~/.claude ./install.sh
#
# Precedence for the target config dir:
#   1. First argument
#   2. $CLAUDE_CONFIG_DIR
#   3. ~/.claude-most (default: company account)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"

CONFIG_DIR="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude-most}}"
# Expand a leading ~ if passed literally
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
TARGET_DIR="$CONFIG_DIR/skills"

if [ ! -d "$SKILLS_SRC" ]; then
    echo "ERROR: skills directory not found at $SKILLS_SRC" >&2
    exit 1
fi

mkdir -p "$TARGET_DIR"

# Detect platform: on native Windows (Git Bash/MSYS), symlinks need admin or
# developer mode, so fall back to copying.
case "$(uname -s)" in
    Linux*|Darwin*) LINK_MODE="symlink" ;;
    MINGW*|MSYS*|CYGWIN*) LINK_MODE="copy" ;;
    *) LINK_MODE="copy" ;;
esac

echo "Installing skills from: $SKILLS_SRC"
echo "Target config dir:      $CONFIG_DIR"
echo "Mode:                   $LINK_MODE"
echo

installed=0
for skill_dir in "$SKILLS_SRC"/*/; do
    skill_name="$(basename "$skill_dir")"
    dest="$TARGET_DIR/$skill_name"

    # Remove a previous link/copy so reinstall is idempotent
    if [ -L "$dest" ] || [ -e "$dest" ]; then
        rm -rf "$dest"
    fi

    if [ "$LINK_MODE" = "symlink" ]; then
        ln -s "${skill_dir%/}" "$dest"
    else
        cp -r "${skill_dir%/}" "$dest"
    fi

    # Skills that ship their own scripts (mantis_deploy) need them executable;
    # git does not always preserve the bit on fresh clones under Windows.
    if [ -d "${skill_dir%/}/scripts" ]; then
        chmod +x "${skill_dir%/}"/scripts/*.sh 2>/dev/null || true
    fi

    echo "  + $skill_name -> $dest"
    installed=$((installed + 1))
done

echo
echo "Done. Installed $installed skill(s) into $TARGET_DIR"
if [ "$LINK_MODE" = "copy" ]; then
    echo "NOTE: files were copied (Windows). Re-run install.sh after updating this repo."
fi

# --- Helper scripts ----------------------------------------------------------
# The mantis_* skills call bin/mantis-api.sh instead of raw curl so the command
# is stable and can be allow-listed once (no permission prompt per API call).

BIN_SRC="$REPO_DIR/bin"
# The skills reference the canonical path ~/.claude-most/bin/... (it must match
# the permission rule literally), so always install there; also install into
# $CONFIG_DIR/bin when a different config dir was chosen.
BIN_DIRS="$HOME/.claude-most/bin"
if [ "$CONFIG_DIR" != "$HOME/.claude-most" ]; then
    BIN_DIRS="$BIN_DIRS $CONFIG_DIR/bin"
fi

if [ -d "$BIN_SRC" ]; then
    for bin_dir in $BIN_DIRS; do
        mkdir -p "$bin_dir"
        for script in "$BIN_SRC"/*; do
            [ -f "$script" ] || continue
            chmod +x "$script" 2>/dev/null || true
            dest="$bin_dir/$(basename "$script")"
            rm -rf "$dest"
            if [ "$LINK_MODE" = "symlink" ]; then
                ln -s "$script" "$dest"
            else
                cp "$script" "$dest"
            fi
            echo "  + $(basename "$script") -> $dest"
        done
    done
fi

# --- Hooks -------------------------------------------------------------------
# git-readonly-allow.py auto-approves read-only git inspection so mantis_develop
# stops asking on every `cd <other-repo> && git show ...`. Same canonical-path
# rule as bin/: the settings entry references ~/.claude-most/hooks/... literally.

HOOKS_SRC="$REPO_DIR/hooks"
HOOK_DIRS="$HOME/.claude-most/hooks"
if [ "$CONFIG_DIR" != "$HOME/.claude-most" ]; then
    HOOK_DIRS="$HOOK_DIRS $CONFIG_DIR/hooks"
fi

if [ -d "$HOOKS_SRC" ]; then
    for hook_dir in $HOOK_DIRS; do
        mkdir -p "$hook_dir"
        for script in "$HOOKS_SRC"/*; do
            [ -f "$script" ] || continue
            chmod +x "$script" 2>/dev/null || true
            dest="$hook_dir/$(basename "$script")"
            rm -rf "$dest"
            if [ "$LINK_MODE" = "symlink" ]; then
                ln -s "$script" "$dest"
            else
                cp "$script" "$dest"
            fi
            echo "  + $(basename "$script") -> $dest"
        done
    done
fi

# --- Permission rules, extra dirs and hook registration ----------------------
# Allow the helpers without prompting. Idempotent; leaves the rest of the file
# (theme, env with the personal MANTIS_API_TOKEN, other rules) untouched.

SETTINGS_FILE="$CONFIG_DIR/settings.json"

# Raiz de los repos de Most, para additionalDirectories. El prompt interactivo
# que escribe most-projects-dir corre mas abajo, asi que aca reusamos el valor
# ya guardado; si no hay, el padre de este repo es la respuesta correcta por
# construccion (most-agent vive dentro de ~/projects/most).
PROJECTS_DIR_HINT="${MOST_PROJECTS_DIR:-}"
if [ -z "$PROJECTS_DIR_HINT" ] && [ -f "$CONFIG_DIR/most-projects-dir" ]; then
    PROJECTS_DIR_HINT="$(cat "$CONFIG_DIR/most-projects-dir" 2>/dev/null)"
fi
[ -n "$PROJECTS_DIR_HINT" ] || PROJECTS_DIR_HINT="$(dirname "$REPO_DIR")"

if command -v python3 >/dev/null 2>&1; then
    python3 - "$SETTINGS_FILE" "$PROJECTS_DIR_HINT" <<'PY'
import json, os, sys

path = sys.argv[1]
projects_dir = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else os.path.expanduser("~/projects/most")
rules = [
    "Bash(~/.claude-most/bin/mantis-api.sh:*)",
    # mantis_deploy: solo estos tres scripts, nunca `curl` libre, para que el
    # JENKINS_API_TOKEN no pueda usarse contra cualquier endpoint de Jenkins.
    "Bash(~/.claude-most/skills/mantis_deploy/scripts/deploy.sh:*)",
    "Bash(~/.claude-most/skills/mantis_deploy/scripts/status.sh:*)",
    "Bash(~/.claude-most/skills/mantis_deploy/scripts/discover.sh:*)",
]
# `|| true` a proposito: si el hook falta o revienta, exit 2 bloquearia el
# comando. Asi el peor caso es volver a preguntar, nunca bloquear.
hook_cmd = 'python3 "$HOME/.claude-most/hooks/git-readonly-allow.py" 2>/dev/null || true'
try:
    with open(path) as fh:
        data = json.load(fh)
except FileNotFoundError:
    data = {}
except Exception as exc:
    print(f"WARNING: could not parse {path} ({exc}); add these rules manually:")
    for rule in rules:
        print(f"  {rule}")
    print(f'  permissions.additionalDirectories += "{projects_dir}"')
    print(f'  hooks.PreToolUse += Bash -> {hook_cmd}')
    sys.exit(0)

changes = []

allow = data.setdefault("permissions", {}).setdefault("allow", [])
for rule in rules:
    if rule not in allow:
        allow.append(rule)
        changes.append(f"permission rule: {rule}")

# mantis_develop cruza entre repos (geins_ypf <-> geins_producto_ypf) y crea
# worktrees en <proyecto>/worktrees/: sin esto, cada lectura fuera del cwd pide
# permiso. Es el equivalente permanente de /add-dir.
extra = data["permissions"].setdefault("additionalDirectories", [])
if projects_dir not in extra:
    extra.append(projects_dir)
    changes.append(f"additionalDirectories: {projects_dir}")

# El hook cubre lo que additionalDirectories no puede: los permisos de Bash se
# evaluan por string de comando, no por directorio, asi que `cd <otro-repo> &&
# git show ...` seguiria preguntando.
entries = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
if not any(h.get("command") == hook_cmd for e in entries for h in e.get("hooks", [])):
    entries.append({"matcher": "Bash", "hooks": [
        {"type": "command", "command": hook_cmd, "timeout": 10}]})
    changes.append("PreToolUse/Bash hook: git-readonly-allow.py")

if not changes:
    print(f"Settings already up to date in {path}")
    sys.exit(0)

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
for change in changes:
    print(f"Added to {path}: {change}")
PY
else
    echo "NOTE: python3 not found. Add these to $SETTINGS_FILE permissions.allow:"
    echo "  Bash(~/.claude-most/bin/mantis-api.sh:*)"
    echo "  Bash(~/.claude-most/skills/mantis_deploy/scripts/deploy.sh:*)"
    echo "  Bash(~/.claude-most/skills/mantis_deploy/scripts/status.sh:*)"
    echo "  Bash(~/.claude-most/skills/mantis_deploy/scripts/discover.sh:*)"
    echo "And these keys:"
    echo "  permissions.additionalDirectories += \"$PROJECTS_DIR_HINT\""
    echo "  hooks.PreToolUse += { matcher: Bash, command: python3 \"\$HOME/.claude-most/hooks/git-readonly-allow.py\" }"
fi

# --- Set up shell integration ------------------------------------------------
# Installs a wrapper so `claude` automatically uses the company config dir when
# run inside $MOST_PROJECTS_DIR (default: ~/projects/most), and the personal
# default config everywhere else. Also keeps `claude-most` to force the
# company profile from any location.

# The Most projects root directory: everything under it uses the company
# profile. Asked interactively (default: the parent of this repo, since
# most-agent is normally cloned next to the other company repos) and stored
# in an editable config file — change the path later by editing that file,
# no reinstall needed.

PROJECTS_CONF="$CONFIG_DIR/most-projects-dir"
DEFAULT_PROJECTS_DIR="${MOST_PROJECTS_DIR:-$(dirname "$REPO_DIR")}"
if [ -f "$PROJECTS_CONF" ]; then
    DEFAULT_PROJECTS_DIR="$(cat "$PROJECTS_CONF")"
fi

if [ -t 0 ]; then
    read -r -p "Most projects root directory [$DEFAULT_PROJECTS_DIR]: " answer
    PROJECTS_DIR="${answer:-$DEFAULT_PROJECTS_DIR}"
else
    PROJECTS_DIR="$DEFAULT_PROJECTS_DIR"
fi
PROJECTS_DIR="${PROJECTS_DIR/#\~/$HOME}"

printf '%s\n' "$PROJECTS_DIR" > "$PROJECTS_CONF"
echo "Most projects root: $PROJECTS_DIR"
echo "  (stored in $PROJECTS_CONF - edit that file to change it later)"

SHELL_BLOCK="$(cat <<EOF

# >>> most-agent claude profile switcher >>>
# Added by most-agent/install.sh - do not edit inside the markers.
# The Most projects root is read from $PROJECTS_CONF at runtime;
# edit that file to change which directory uses the company profile.
alias claude-most='CLAUDE_CONFIG_DIR=$CONFIG_DIR claude'
claude() {
    local most_root=""
    [ -f "$PROJECTS_CONF" ] && most_root="\$(cat "$PROJECTS_CONF")"
    if [ -n "\$most_root" ] && [[ "\$PWD" == "\$most_root"* ]]; then
        CLAUDE_CONFIG_DIR="$CONFIG_DIR" command claude "\$@"
    else
        command claude "\$@"
    fi
}
# <<< most-agent claude profile switcher <<<
EOF
)"

setup_alias() {
    local rc_file="$1"
    if [ -f "$rc_file" ] && grep -q "most-agent claude profile switcher" "$rc_file"; then
        echo "Profile switcher already present in $rc_file"
        return
    fi
    printf '%s\n' "$SHELL_BLOCK" >> "$rc_file"
    echo "Profile switcher added to $rc_file"
    echo "Run 'source $rc_file' or open a new terminal to use it."
}

echo
case "$(uname -s)" in
    Linux*)
        setup_alias "$HOME/.bashrc"
        if [ -f "$HOME/.zshrc" ]; then setup_alias "$HOME/.zshrc"; fi
        ;;
    Darwin*)
        # macOS default shell is zsh
        setup_alias "$HOME/.zshrc"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        # Git Bash on Windows
        setup_alias "$HOME/.bashrc"
        echo
        echo "If you also use PowerShell, add this function to your \$PROFILE:"
        echo "  function claude-most { \$env:CLAUDE_CONFIG_DIR = \"\$HOME\\.claude-most\"; claude @args }"
        ;;
esac
