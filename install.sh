#!/usr/bin/env bash
# Install the development-flow skill and its four agents into ~/.claude via symlinks,
# so `git pull` in this repo updates the live copies.
#
# Usage: ./install.sh           (symlink, default)
#        ./install.sh --copy    (copy files instead of symlinking)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CLAUDE_DIR=${CLAUDE_DIR:-$HOME/.claude}
MODE=link
[ "${1:-}" = "--copy" ] && MODE=copy

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"

place() { # src dst
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      echo "ok      $dst"; return
    fi
    local bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"; echo "backup  $dst -> $bak"
  fi
  if [ "$MODE" = link ]; then ln -s "$src" "$dst"; echo "linked  $dst"
  else cp -R "$src" "$dst"; echo "copied  $dst"; fi
}

place "$HERE/skills/development-flow" "$CLAUDE_DIR/skills/development-flow"
for f in "$HERE"/agents/df-*.md; do
  place "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done
chmod +x "$HERE/skills/development-flow/scripts/watch-pr.sh"
echo "done. Restart Claude Code (or start a new session) to pick up the skill and agents."
