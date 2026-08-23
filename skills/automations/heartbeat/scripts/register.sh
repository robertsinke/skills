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
Scheduled automations live in automations/ (overview: DASHBOARD.md, local agent choices: AGENT-OPTIONS.md, history: RUNS.md; runtime: _heartbeat/)."
if [ -f "$AGENTS_MD" ]; then
  if grep -qF "Scheduled checks live under automations/. Current: automations/heartbeat/" "$AGENTS_MD"; then
    sed -i.bak 's#Scheduled checks live under automations/. Current: automations/heartbeat/ (checklist: HEARTBEAT.md, history: RUNS.md).#Scheduled automations live in automations/ (overview: DASHBOARD.md, local agent choices: AGENT-OPTIONS.md, history: RUNS.md; runtime: _heartbeat/).#' "$AGENTS_MD"
    rm -f "$AGENTS_MD.bak"
  elif grep -qF "Scheduled checks live in automations/ (checklist: HEARTBEAT.md" "$AGENTS_MD"; then
    sed -i.bak 's#Scheduled checks live in automations/ (checklist: HEARTBEAT.md, history: RUNS.md; runtime: _heartbeat/).#Scheduled automations live in automations/ (overview: DASHBOARD.md, local agent choices: AGENT-OPTIONS.md, history: RUNS.md; runtime: _heartbeat/).#' "$AGENTS_MD"
    rm -f "$AGENTS_MD.bak"
  elif ! grep -qF "Scheduled automations live in automations/" "$AGENTS_MD"; then
    printf "\n%s\n" "$POINTER" >> "$AGENTS_MD"
  fi
else
  printf "%s\n" "$POINTER" > "$AGENTS_MD"
fi
echo "AGENTS.md points at automations/ ($AGENTS_MD)"
