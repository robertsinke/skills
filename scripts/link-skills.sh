#!/usr/bin/env bash
set -euo pipefail

# Links all skills in this repository into the local skill directories used
# by each agent harness:
#   - ~/.claude/skills: Claude Code
#   - ~/.agents/skills: Codex and other Agent Skills-compatible harnesses
# Also symlinks the heartbeat CLI onto PATH via ~/.agents/bin.
# Each entry is a symlink into this repo, so a `git pull` keeps it up to date.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DESTS=("$HOME/.claude/skills" "$HOME/.agents/skills")

names=()
srcs=()
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  names+=("$(basename "$src")")
  srcs+=("$src")
done < <(find "$REPO/skills" -name SKILL.md -print0)

for DEST in "${DESTS[@]}"; do
  mkdir -p "$DEST"
  for i in "${!names[@]}"; do
    name="${names[$i]}"
    src="${srcs[$i]}"
    target="$DEST/$name"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      rm -rf "$target"
    fi
    ln -sfn "$src" "$target"
    echo "linked $name -> $src ($DEST)"
  done
done

# CLI: symlink the heartbeat entrypoint onto PATH via ~/.agents/bin.
BIN_DEST="$HOME/.agents/bin"
mkdir -p "$BIN_DEST"
if [ -f "$REPO/skills/automations/heartbeat/scripts/heartbeat" ]; then
  chmod +x "$REPO/skills/automations/heartbeat/scripts/heartbeat"
  ln -sfn "$REPO/skills/automations/heartbeat/scripts/heartbeat" "$BIN_DEST/heartbeat"
  echo "linked heartbeat -> $REPO/skills/automations/heartbeat/scripts/heartbeat ($BIN_DEST)"
fi

case ":$PATH:" in
  *":$BIN_DEST:"*) : ;;
  *) echo "Note: add $BIN_DEST to your PATH manually, e.g. in ~/.zshrc: export PATH=$BIN_DEST:\$PATH" ;;
esac










































