#!/usr/bin/env bash
# heartbeat-report.sh
# Expected to run with cwd = automations/_heartbeat/
set -euo pipefail

AUTOMATIONS_DIR="$(cd .. && pwd)"
RUNS_FILE="$AUTOMATIONS_DIR/RUNS.md"

FRONTMATTER_SOURCE=""
if [ -f "$RUNS_FILE" ] && [ "$(head -n 1 "$RUNS_FILE")" = "---" ]; then
  FRONTMATTER_SOURCE="$RUNS_FILE"
fi

REPORT_TMP="$(mktemp)"
trap 'rm -f "$REPORT_TMP"' EXIT

{
  if [ -n "$FRONTMATTER_SOURCE" ]; then
    awk '
      NR == 1 && $0 == "---" { print; in_frontmatter = 1; next }
      in_frontmatter { print; if ($0 == "---") exit }
    ' "$FRONTMATTER_SOURCE"
  else
    printf '%s\n' \
      '---' \
      'title: Heartbeat runs' \
      'description: Generated history for scheduled project checks.' \
      'generated: true' \
      '---'
  fi

  printf '\n# Heartbeat runs\n\n'
  sqlite3 .heartbeat.db <<'SQL'
.mode markdown
.headers on
SELECT date AS Date, time AS Time, agent AS Agent, model AS Model, effort AS Effort,
       permission_mode AS Permissions,
       status AS Status, duration_ms || 'ms' AS Duration,
       input_tokens || '/' || output_tokens AS Tokens,
       printf('$%.4f', cost_usd) AS Cost,
       substr(output, 1, 80) AS Summary
FROM runs ORDER BY ts DESC LIMIT 50;
SQL
} > "$REPORT_TMP"

mv "$REPORT_TMP" "$RUNS_FILE"
trap - EXIT
