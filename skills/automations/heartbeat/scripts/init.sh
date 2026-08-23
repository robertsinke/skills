#!/usr/bin/env bash
# init.sh - scaffold automations/heartbeat/ in the current project.
# Canonical implementation; `heartbeat init` just calls this.
#
# This step ONLY creates files - it does not register the project in the
# global registry, does not touch AGENTS.md, and does not schedule cron.
# Run `heartbeat register` and `heartbeat schedule enable` after (or just
# run `heartbeat automations create`, which composes all three).
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(pwd)"
TARGET="$PROJECT_DIR/automations/heartbeat"

OPENKNOWLEDGE_TEMPLATES="$(
  find "$PROJECT_DIR" \
    \( -path "$PROJECT_DIR/.git" -o -name node_modules \) -prune -o \
    -type d -path '*/.ok/templates' -print -quit 2>/dev/null || true
)"
if [ -n "$OPENKNOWLEDGE_TEMPLATES" ]; then
  TEMPLATE_DIR="$TARGET/.ok/templates"
else
  TEMPLATE_DIR="$TARGET/.templates"
fi

mkdir -p "$TARGET" "$TEMPLATE_DIR"

[ -f "$TEMPLATE_DIR/heartbeat.md" ] || cp "$SKILL_DIR/templates/HEARTBEAT.md.template" "$TEMPLATE_DIR/heartbeat.md"
[ -f "$TEMPLATE_DIR/runs.md" ] || cp "$SKILL_DIR/templates/RUNS.md.template" "$TEMPLATE_DIR/runs.md"

[ -f "$TARGET/HEARTBEAT.md" ] || cp "$TEMPLATE_DIR/heartbeat.md" "$TARGET/HEARTBEAT.md"
[ -f "$TARGET/RUNS.md" ] || cp "$TEMPLATE_DIR/runs.md" "$TARGET/RUNS.md"
[ -f "$TARGET/.heartbeat.db" ] || sqlite3 "$TARGET/.heartbeat.db" < "$SKILL_DIR/scripts/schema.sql"

cp -n "$SKILL_DIR/scripts/heartbeat-run.sh" "$TARGET/heartbeat-run.sh" 2>/dev/null || true
cp -n "$SKILL_DIR/scripts/heartbeat-report.sh" "$TARGET/heartbeat-report.sh" 2>/dev/null || true
cp -n "$SKILL_DIR/scripts/validate-heartbeat.py" "$TARGET/validate-heartbeat.py" 2>/dev/null || true
chmod +x "$TARGET/heartbeat-run.sh" "$TARGET/heartbeat-report.sh" "$TARGET/validate-heartbeat.py"

echo "scaffolded $TARGET (HEARTBEAT.md, RUNS.md, .heartbeat.db, heartbeat-run.sh, heartbeat-report.sh, validate-heartbeat.py)"
echo "templates: $TEMPLATE_DIR"
echo "not yet registered or scheduled - run: heartbeat register && heartbeat schedule enable"
