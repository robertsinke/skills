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

[ -f "$TEMPLATE_DIR/automation.md" ] || cp "$SKILL_DIR/templates/AUTOMATION.md.template" "$TEMPLATE_DIR/automation.md"

[ -f "$AUTOMATIONS_DIR/CONTEXT.md" ] || cp "$SKILL_DIR/templates/CONTEXT.md.template" "$AUTOMATIONS_DIR/CONTEXT.md"
[ -f "$RUNTIME_DIR/.gitignore" ] || cp "$SKILL_DIR/templates/runtime.gitignore.template" "$RUNTIME_DIR/.gitignore"

GENERATED_IGNORE="$AUTOMATIONS_DIR/.gitignore"
touch "$GENERATED_IGNORE"
for generated in DASHBOARD.md AGENT-OPTIONS.md RUNS.md; do
  grep -qxF "$generated" "$GENERATED_IGNORE" || echo "$generated" >> "$GENERATED_IGNORE"
done

cp "$SKILL_DIR/scripts/heartbeat-run.sh" "$RUNTIME_DIR/heartbeat-run.sh"
cp "$SKILL_DIR/scripts/heartbeat-report.sh" "$RUNTIME_DIR/heartbeat-report.sh"
cp "$SKILL_DIR/scripts/validate-heartbeat.py" "$RUNTIME_DIR/validate-heartbeat.py"
cp "$SKILL_DIR/scripts/heartbeat_engine.py" "$RUNTIME_DIR/heartbeat_engine.py"
chmod +x "$RUNTIME_DIR/heartbeat-run.sh" "$RUNTIME_DIR/heartbeat-report.sh" "$RUNTIME_DIR/validate-heartbeat.py" "$RUNTIME_DIR/heartbeat_engine.py"

if [ -f "$AUTOMATIONS_DIR/HEARTBEAT.md" ]; then
  python3 "$RUNTIME_DIR/heartbeat_engine.py" migrate "$AUTOMATIONS_DIR"
fi

if ! grep -l '^type:[[:space:]]*automation[[:space:]]*$' "$AUTOMATIONS_DIR"/*.md >/dev/null 2>&1; then
  cp "$TEMPLATE_DIR/automation.md" "$AUTOMATIONS_DIR/example-automation.md"
fi

python3 "$RUNTIME_DIR/heartbeat_engine.py" scan "$AUTOMATIONS_DIR"
python3 "$RUNTIME_DIR/heartbeat_engine.py" report "$AUTOMATIONS_DIR"

if [ "$TEMPLATE_DIR" = "$AUTOMATIONS_DIR/.ok/templates" ]; then
  [ -f "$AUTOMATIONS_DIR/.ok/frontmatter.yml" ] || cp "$SKILL_DIR/templates/frontmatter.yml" "$AUTOMATIONS_DIR/.ok/frontmatter.yml"
fi

echo "scaffolded $AUTOMATIONS_DIR (automation files, DASHBOARD.md, AGENT-OPTIONS.md, RUNS.md, CONTEXT.md)"
echo "runtime: $RUNTIME_DIR (.heartbeat.db, heartbeat_engine.py, runner, reporter, validator)"
echo "templates: $TEMPLATE_DIR"
echo "not yet registered or scheduled - run: heartbeat register && heartbeat schedule enable"
