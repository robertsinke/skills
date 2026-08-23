#!/usr/bin/env bash
# schedule.sh <enable|disable> - toggle the cron entry for the current
# project's automations/_heartbeat/. Canonical implementation; `heartbeat
# schedule enable/disable` (and the `automations pause`/`resume` aliases)
# just call this.
set -euo pipefail

MODE="${1:-}"
case "$MODE" in
  enable|disable) ;;
  *) echo "usage: schedule.sh <enable|disable>" >&2; exit 1 ;;
esac

PROJECT_DIR="$(pwd)"
TARGET="$PROJECT_DIR/automations/_heartbeat"
LEGACY_TARGET="$PROJECT_DIR/automations/heartbeat"
if [ ! -d "$TARGET" ]; then
  echo "no automations/_heartbeat/ at $PROJECT_DIR - run 'heartbeat init' first" >&2
  exit 1
fi

TMP=$(mktemp)
crontab -l 2>/dev/null > "$TMP" || true

if grep -qF "$LEGACY_TARGET" "$TMP"; then
  python3 -c 'from pathlib import Path; import sys; p=Path(sys.argv[1]); p.write_text(p.read_text().replace(sys.argv[2], sys.argv[3]))' "$TMP" "$LEGACY_TARGET" "$TARGET"
fi

if grep -qF "$TARGET" "$TMP"; then
  if [ "$MODE" = disable ]; then
    sed -i.bak "\#$TARGET# s/^\([^#]\)/#\1/" "$TMP"
  else
    sed -i.bak "\#$TARGET# s/^#//" "$TMP"
  fi
else
  if [ "$MODE" = enable ]; then
    CRON_CMD="cd $TARGET && ./heartbeat-run.sh && ./heartbeat-report.sh"
    echo "*/30 * * * * $CRON_CMD" >> "$TMP"
  else
    echo "no cron entry for $TARGET - nothing to disable"
  fi
fi

crontab "$TMP"
rm -f "$TMP" "$TMP.bak"
echo "schedule ${MODE}d for $TARGET"
