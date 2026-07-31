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

    echo "  + $skill_name -> $dest"
    installed=$((installed + 1))
done

echo
echo "Done. Installed $installed skill(s) into $TARGET_DIR"
if [ "$LINK_MODE" = "copy" ]; then
    echo "NOTE: files were copied (Windows). Re-run install.sh after updating this repo."
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
