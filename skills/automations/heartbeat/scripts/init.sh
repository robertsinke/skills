#!/usr/bin/env bash
# init.sh - scaffold the human/runtime split under automations/.
# Canonical implementation; `heartbeat init` just calls this.
#
# This step ONLY creates files - it does not register the project in the
# global registry, does not touch AGENTS.md, and does not schedule cron.
# Run `heartbeat register` and `heartbeat schedule enable` after (or just
# run `heartbeat automations create`, which composes all three).
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$(pwd)"
AUTOMATIONS_DIR="$PROJECT_DIR/automations"
RUNTIME_DIR="$AUTOMATIONS_DIR/_heartbeat"
LEGACY_DIR="$AUTOMATIONS_DIR/heartbeat"

if [ -d "$LEGACY_DIR" ]; then
  "$SKILL_DIR/scripts/migrate-layout.sh" "$PROJECT_DIR"
fi

OPENKNOWLEDGE_TEMPLATES="$(
  find "$PROJECT_DIR" \
    \( -path "$PROJECT_DIR/.git" -o -name node_modules \) -prune -o \
    -type d -path '*/.ok/templates' -print -quit 2>/dev/null || true
)"
if [ -n "$OPENKNOWLEDGE_TEMPLATES" ]; then
  TEMPLATE_DIR="$AUTOMATIONS_DIR/.ok/templates"
else
  TEMPLATE_DIR="$AUTOMATIONS_DIR/.templates"
fi

mkdir -p "$AUTOMATIONS_DIR" "$RUNTIME_DIR" "$TEMPLATE_DIR"

[ -f "$TEMPLATE_DIR/heartbeat.md" ] || cp "$SKILL_DIR/templates/HEARTBEAT.md.template" "$TEMPLATE_DIR/heartbeat.md"

[ -f "$AUTOMATIONS_DIR/CONTEXT.md" ] || cp "$SKILL_DIR/templates/CONTEXT.md.template" "$AUTOMATIONS_DIR/CONTEXT.md"
[ -f "$AUTOMATIONS_DIR/HEARTBEAT.md" ] || cp "$TEMPLATE_DIR/heartbeat.md" "$AUTOMATIONS_DIR/HEARTBEAT.md"
[ -f "$AUTOMATIONS_DIR/RUNS.md" ] || cp "$SKILL_DIR/templates/RUNS.md.template" "$AUTOMATIONS_DIR/RUNS.md"
[ -f "$RUNTIME_DIR/.heartbeat.db" ] || sqlite3 "$RUNTIME_DIR/.heartbeat.db" < "$SKILL_DIR/scripts/schema.sql"
[ -f "$RUNTIME_DIR/.gitignore" ] || cp "$SKILL_DIR/templates/runtime.gitignore.template" "$RUNTIME_DIR/.gitignore"

cp "$SKILL_DIR/scripts/heartbeat-run.sh" "$RUNTIME_DIR/heartbeat-run.sh"
cp "$SKILL_DIR/scripts/heartbeat-report.sh" "$RUNTIME_DIR/heartbeat-report.sh"
cp "$SKILL_DIR/scripts/validate-heartbeat.py" "$RUNTIME_DIR/validate-heartbeat.py"
chmod +x "$RUNTIME_DIR/heartbeat-run.sh" "$RUNTIME_DIR/heartbeat-report.sh" "$RUNTIME_DIR/validate-heartbeat.py"

if [ "$TEMPLATE_DIR" = "$AUTOMATIONS_DIR/.ok/templates" ]; then
  [ -f "$AUTOMATIONS_DIR/.ok/frontmatter.yml" ] || cp "$SKILL_DIR/templates/frontmatter.yml" "$AUTOMATIONS_DIR/.ok/frontmatter.yml"
fi

echo "scaffolded $AUTOMATIONS_DIR (HEARTBEAT.md, RUNS.md, CONTEXT.md)"
echo "runtime: $RUNTIME_DIR (.heartbeat.db, heartbeat-run.sh, heartbeat-report.sh, validate-heartbeat.py)"
echo "templates: $TEMPLATE_DIR"
echo "not yet registered or scheduled - run: heartbeat register && heartbeat schedule enable"
