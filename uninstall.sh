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
