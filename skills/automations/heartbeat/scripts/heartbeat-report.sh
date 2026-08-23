#!/usr/bin/env bash
# heartbeat-report.sh
# Expected to run with cwd = automations/heartbeat/
set -euo pipefail

sqlite3 .heartbeat.db <<'SQL' > RUNS.md
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














