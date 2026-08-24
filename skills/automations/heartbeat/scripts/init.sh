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
TASKS_DIR="$AUTOMATIONS_DIR/tasks"
RUNTIME_DIR="$AUTOMATIONS_DIR/_heartbeat"
LEGACY_DIR="$AUTOMATIONS_DIR/heartbeat"

if [ -d "$LEGACY_DIR" ]; then
  bash "$SKILL_DIR/scripts/migrate-layout.sh" "$PROJECT_DIR"
fi

OPENKNOWLEDGE_TEMPLATES="$(
  find "$PROJECT_DIR" \
    \( -path "$PROJECT_DIR/.git" -o -name node_modules \) -prune -o \
    -type d -path '*/.ok/templates' -print -quit 2>/dev/null || true
)"
if [ -n "$OPENKNOWLEDGE_TEMPLATES" ]; then
  TEMPLATE_DIR="$TASKS_DIR/.ok/templates"
else
  TEMPLATE_DIR="$TASKS_DIR/.templates"
fi

mkdir -p "$AUTOMATIONS_DIR" "$TASKS_DIR" "$RUNTIME_DIR" "$TEMPLATE_DIR"

for old_template in "$AUTOMATIONS_DIR/.ok/templates/automation.md" "$AUTOMATIONS_DIR/.templates/automation.md"; do
  [ -f "$old_template" ] || continue
  if [ ! -f "$TEMPLATE_DIR/automation.md" ]; then
    mv "$old_template" "$TEMPLATE_DIR/automation.md"
  else
    mv "$old_template" "$RUNTIME_DIR/legacy-automation-template.md"
  fi
done

[ -f "$TEMPLATE_DIR/automation.md" ] || cp "$SKILL_DIR/templates/AUTOMATION.md.template" "$TEMPLATE_DIR/automation.md"

[ -f "$AUTOMATIONS_DIR/CONTEXT.md" ] || cp "$SKILL_DIR/templates/CONTEXT.md.template" "$AUTOMATIONS_DIR/CONTEXT.md"
touch "$RUNTIME_DIR/.gitignore"
while IFS= read -r ignored; do
  [ -z "$ignored" ] || grep -qxF "$ignored" "$RUNTIME_DIR/.gitignore" || echo "$ignored" >> "$RUNTIME_DIR/.gitignore"
done < "$SKILL_DIR/templates/runtime.gitignore.template"

GENERATED_IGNORE="$AUTOMATIONS_DIR/.gitignore"
touch "$GENERATED_IGNORE"
sed -i.bak -e '/^AGENT-OPTIONS\.md$/d' -e '/^DASHBOARD\.md$/d' -e '/^RUNS\.md$/d' "$GENERATED_IGNORE" && rm -f "$GENERATED_IGNORE.bak"
grep -qxF "INDEX.md" "$GENERATED_IGNORE" || echo "INDEX.md" >> "$GENERATED_IGNORE"
rm -f "$AUTOMATIONS_DIR/DASHBOARD.md" "$AUTOMATIONS_DIR/RUNS.md"

cp "$SKILL_DIR/scripts/heartbeat-run.sh" "$RUNTIME_DIR/heartbeat-run.sh"
cp "$SKILL_DIR/scripts/heartbeat-report.sh" "$RUNTIME_DIR/heartbeat-report.sh"
cp "$SKILL_DIR/scripts/validate-heartbeat.py" "$RUNTIME_DIR/validate-heartbeat.py"
cp "$SKILL_DIR/scripts/heartbeat_engine.py" "$RUNTIME_DIR/heartbeat_engine.py"
chmod +x "$RUNTIME_DIR/heartbeat-run.sh" "$RUNTIME_DIR/heartbeat-report.sh" "$RUNTIME_DIR/validate-heartbeat.py" "$RUNTIME_DIR/heartbeat_engine.py"

python3 "$RUNTIME_DIR/heartbeat_engine.py" migrate "$AUTOMATIONS_DIR"

if ! grep -l '^type:[[:space:]]*automation[[:space:]]*$' "$TASKS_DIR"/*.md >/dev/null 2>&1; then
  cp "$TEMPLATE_DIR/automation.md" "$TASKS_DIR/example-automation.md"
fi

python3 "$RUNTIME_DIR/heartbeat_engine.py" scan "$AUTOMATIONS_DIR"
python3 "$RUNTIME_DIR/heartbeat_engine.py" report "$AUTOMATIONS_DIR"

if [ "$TEMPLATE_DIR" = "$TASKS_DIR/.ok/templates" ]; then
  mkdir -p "$AUTOMATIONS_DIR/.ok" "$TASKS_DIR/.ok"
  [ -f "$AUTOMATIONS_DIR/.ok/frontmatter.yml" ] || cp "$SKILL_DIR/templates/frontmatter.yml" "$AUTOMATIONS_DIR/.ok/frontmatter.yml"
  [ -f "$TASKS_DIR/.ok/frontmatter.yml" ] || cp "$SKILL_DIR/templates/tasks-frontmatter.yml" "$TASKS_DIR/.ok/frontmatter.yml"
fi

find "$AUTOMATIONS_DIR/.ok/templates" "$AUTOMATIONS_DIR/.templates" -depth -type d -empty -exec rmdir {} \; 2>/dev/null || true

echo "scaffolded $AUTOMATIONS_DIR (tasks/, INDEX.md, CONTEXT.md)"
echo "runtime: $RUNTIME_DIR (.heartbeat.db, AGENT-OPTIONS.md, engine, runner, reporter, validator)"
echo "templates: $TEMPLATE_DIR"
echo "not yet registered or scheduled - run: heartbeat register && heartbeat schedule enable"
