#!/usr/bin/env bash
# Move the legacy automations/heartbeat/ layout into the human/runtime split.
# Files only: scheduling and registration remain separate concerns.
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
AUTOMATIONS_DIR="$PROJECT_DIR/automations"
LEGACY_DIR="$AUTOMATIONS_DIR/heartbeat"
RUNTIME_DIR="$AUTOMATIONS_DIR/_heartbeat"

[ -d "$LEGACY_DIR" ] || exit 0
mkdir -p "$RUNTIME_DIR"

move_if_present() {
  local source="$1" destination="$2"
  [ -e "$source" ] || return 0
  if [ -e "$destination" ]; then
    echo "cannot migrate: destination already exists: $destination" >&2
    exit 1
  fi
  mv "$source" "$destination"
}

move_if_present "$LEGACY_DIR/HEARTBEAT.md" "$AUTOMATIONS_DIR/HEARTBEAT.md"
move_if_present "$LEGACY_DIR/RUNS.md" "$AUTOMATIONS_DIR/RUNS.md"

for name in .heartbeat.db .heartbeat.json .heartbeat.lock heartbeat-run.sh heartbeat-report.sh validate-heartbeat.py; do
  move_if_present "$LEGACY_DIR/$name" "$RUNTIME_DIR/$name"
done

for template_dir in .ok/templates .templates; do
  if [ -f "$LEGACY_DIR/$template_dir/heartbeat.md" ]; then
    mkdir -p "$AUTOMATIONS_DIR/$template_dir"
    move_if_present "$LEGACY_DIR/$template_dir/heartbeat.md" "$AUTOMATIONS_DIR/$template_dir/heartbeat.md"
  fi
  if [ -f "$LEGACY_DIR/$template_dir/runs.md" ]; then
    move_if_present "$LEGACY_DIR/$template_dir/runs.md" "$RUNTIME_DIR/legacy-runs-template.md"
  fi
done

find "$LEGACY_DIR" -depth -type d -empty -exec rmdir {} \; 2>/dev/null || true
if [ -d "$LEGACY_DIR" ]; then
  echo "warning: legacy files remain at $LEGACY_DIR; move them manually after review" >&2
fi
echo "migrated heartbeat layout to $AUTOMATIONS_DIR and $RUNTIME_DIR"
