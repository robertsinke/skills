#!/usr/bin/env bash
# heartbeat-report.sh
# Expected to run with cwd = automations/heartbeat/
set -euo pipefail

FRONTMATTER_SOURCE=""
for candidate in RUNS.md .ok/templates/runs.md .templates/runs.md; do
  if [ -f "$candidate" ] && [ "$(head -n 1 "$candidate")" = "---" ]; then
    FRONTMATTER_SOURCE="$candidate"
    break
  fi
done

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

mv "$REPORT_TMP" RUNS.md
trap - EXIT
