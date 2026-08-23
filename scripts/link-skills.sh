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

if [ -f "$REPO/skills/voice/talk-to-me/scripts/talk-to-me" ]; then
  chmod +x "$REPO/skills/voice/talk-to-me/scripts/talk-to-me"
  ln -sfn "$REPO/skills/voice/talk-to-me/scripts/talk-to-me" "$BIN_DEST/talk-to-me"
  echo "linked talk-to-me -> $REPO/skills/voice/talk-to-me/scripts/talk-to-me ($BIN_DEST)"
fi

# Make sure $BIN_DEST is actually on PATH - not just for this script's shell,
# but for future terminal sessions - by appending an idempotent export line to
# the user's shell rc file. This is what makes `heartbeat` and `talk-to-me`
# work as plain commands instead of needing `bash /path/to/scripts/heartbeat`.
case ":$PATH:" in
  *":$BIN_DEST:"*)
    : # already on PATH for this shell
    ;;
  *)
    MARKER="# added by robertsinke/skills scripts/link-skills.sh"
    LINE="export PATH=\"$BIN_DEST:\$PATH\""
    case "${SHELL:-}" in
      */zsh) RC="$HOME/.zshrc" ;;
      */bash) RC="$HOME/.bashrc" ;;
      *) RC="$HOME/.profile" ;;
    esac
    if [ ! -f "$RC" ] || ! grep -qF "$MARKER" "$RC" 2>/dev/null; then
      { echo ""; echo "$MARKER"; echo "$LINE"; } >> "$RC"
      echo "Added $BIN_DEST to PATH in $RC - restart your terminal (or run: source $RC) to use 'heartbeat' and 'talk-to-me' directly."
    else
      echo "$BIN_DEST PATH line already present in $RC - restart your terminal (or run: source $RC) if commands aren't found yet."
    fi
    ;;
esac
