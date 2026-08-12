#!/usr/bin/env bash
#
# Remove Most shared Claude Code skills installed by install.sh.
#
# Usage:
#   ./uninstall.sh                   # removes from $CLAUDE_CONFIG_DIR/skills or ~/.claude-most/skills
#   ./uninstall.sh /path/to/config

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"

CONFIG_DIR="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude-most}}"
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"
TARGET_DIR="$CONFIG_DIR/skills"

removed=0
for skill_dir in "$SKILLS_SRC"/*/; do
    skill_name="$(basename "$skill_dir")"
    dest="$TARGET_DIR/$skill_name"
    if [ -L "$dest" ] || [ -e "$dest" ]; then
        rm -rf "$dest"
        echo "  - removed $dest"
        removed=$((removed + 1))
    fi
done

echo "Done. Removed $removed skill(s) from $TARGET_DIR"

# Helper scripts installed by install.sh
if [ -d "$REPO_DIR/bin" ]; then
    for bin_dir in "$HOME/.claude-most/bin" "$CONFIG_DIR/bin"; do
        [ -d "$bin_dir" ] || continue
        for script in "$REPO_DIR"/bin/*; do
            [ -f "$script" ] || continue
            dest="$bin_dir/$(basename "$script")"
            if [ -L "$dest" ] || [ -e "$dest" ]; then
                rm -f "$dest"
                echo "  - removed $dest"
            fi
        done
        rmdir "$bin_dir" 2>/dev/null || true
    done
fi

echo
echo "NOTE: the permission rule Bash(~/.claude-most/bin/mantis-api.sh:*) was left"
echo "      in $CONFIG_DIR/settings.json - remove it manually if you want it gone."
