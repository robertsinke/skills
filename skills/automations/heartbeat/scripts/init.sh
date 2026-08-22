#!/usr/bin/env bash
# init.sh - scaffold automations/heartbeat/ in the current project.
# This is the canonical implementation. `heartbeat automations create` just calls this.
# Run from inside the target project, e.g.:
#   ~/.claude/skills/heartbeat/scripts/init.sh
#   (or simply: heartbeat automations create, once the CLI is on PATH)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(pwd)"
TARGET="$PROJECT_DIR/automations/heartbeat"
REGISTRY="$HOME/.agents/heartbeat/registry.txt"

mkdir -p "$TARGET"
mkdir -p "$(dirname "$REGISTRY")"
touch "$REGISTRY"

[ -f "$TARGET/HEARTBEAT.md" ] || cp "$SKILL_DIR/templates/HEARTBEAT.md.template" "$TARGET/HEARTBEAT.md"
[ -f "$TARGET/.heartbeat.db" ] || sqlite3 "$TARGET/.heartbeat.db" < "$SKILL_DIR/scripts/schema.sql"

cp -n "$SKILL_DIR/scripts/heartbeat-run.sh" "$TARGET/heartbeat-run.sh" 2>/dev/null || true
cp -n "$SKILL_DIR/scripts/heartbeat-report.sh" "$TARGET/heartbeat-report.sh" 2>/dev/null || true
chmod +x "$TARGET/heartbeat-run.sh" "$TARGET/heartbeat-report.sh"

CRON_CMD="cd $TARGET && ./heartbeat-run.sh && ./heartbeat-report.sh"
CRON_LINE="*/30 * * * * $CRON_CMD"
( crontab -l 2>/dev/null | grep -vF "$TARGET" ; echo "$CRON_LINE" ) | crontab -

AGENTS_MD="$PROJECT_DIR/AGENTS.md"
POINTER="## Automation
Scheduled checks live under automations/. Current: automations/heartbeat/ (checklist: HEARTBEAT.md, history: RUNS.md)."
if [ -f "$AGENTS_MD" ]; then
  grep -qF "automations/heartbeat" "$AGENTS_MD" || printf "\n%s\n" "$POINTER" >> "$AGENTS_MD"
else
  printf "%s\n" "$POINTER" > "$AGENTS_MD"
fi

grep -qxF "$PROJECT_DIR" "$REGISTRY" 2>/dev/null || echo "$PROJECT_DIR" >> "$REGISTRY"

echo "heartbeat installed in $TARGET"
































