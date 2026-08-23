#!/usr/bin/env bash
# register.sh - register the current project so it shows up in `heartbeat
# automations list`, and point its AGENTS.md at automations/.
# Canonical implementation; `heartbeat register` just calls this.
#
# Deliberately separate from init.sh: init only creates files, register only
# makes the project discoverable. Run `heartbeat init` first (or this is a
# no-op with a warning if automations/_heartbeat/ does not exist yet).
set -euo pipefail

PROJECT_DIR="$(pwd)"
TARGET="$PROJECT_DIR/automations/_heartbeat"
REGISTRY="$HOME/.agents/heartbeat/registry.txt"

if [ ! -d "$TARGET" ]; then
  echo "warning: no automations/_heartbeat/ at $PROJECT_DIR yet - run 'heartbeat init' first" >&2
fi

mkdir -p "$(dirname "$REGISTRY")"
touch "$REGISTRY"
grep -qxF "$PROJECT_DIR" "$REGISTRY" 2>/dev/null || echo "$PROJECT_DIR" >> "$REGISTRY"
echo "registered $PROJECT_DIR ($REGISTRY)"

AGENTS_MD="$PROJECT_DIR/AGENTS.md"
POINTER="## Automation
Scheduled automation tasks live in automations/tasks/ (overview: automations/DASHBOARD.md, history: automations/RUNS.md; runtime and local agent choices: automations/_heartbeat/)."
if [ -f "$AGENTS_MD" ]; then
  if grep -Eq '^Scheduled (checks live (under|in)|automations live in) automations/' "$AGENTS_MD"; then
    python3 -c 'from pathlib import Path; import sys
p=Path(sys.argv[1]); replacement=sys.argv[2]
lines=[replacement if line.startswith(("Scheduled checks live under automations/", "Scheduled checks live in automations/", "Scheduled automations live in automations/")) else line for line in p.read_text().splitlines()]
p.write_text("\n".join(lines)+"\n")' "$AGENTS_MD" "${POINTER#*$'\n'}"
  elif ! grep -qF "Scheduled automation tasks live in automations/tasks/" "$AGENTS_MD"; then
    printf "\n%s\n" "$POINTER" >> "$AGENTS_MD"
  fi
else
  printf "%s\n" "$POINTER" > "$AGENTS_MD"
fi
echo "AGENTS.md points at automations/ ($AGENTS_MD)"
