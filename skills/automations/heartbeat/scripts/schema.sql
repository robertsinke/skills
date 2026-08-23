-- status values (free TEXT, not a CHECK constraint, but this is the closed
-- set heartbeat-run.sh actually writes):
--   ok       - ran, replied HEARTBEAT_OK, nothing to report
--   alert    - ran, replied with something other than HEARTBEAT_OK
--   error    - agent CLI exited non-zero
--   timeout  - agent exceeded timeout_seconds and was killed (see .heartbeat.json)
--   invalid  - HEARTBEAT.md failed validate-heartbeat.py; agent was never invoked
--   skipped  - a previous run's lock was still held; this cycle was skipped
CREATE TABLE IF NOT EXISTS runs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  ts            TEXT,
  date          TEXT,
  time          TEXT,
  agent         TEXT,
  model         TEXT,
  effort        TEXT,
  permission_mode TEXT,
  status        TEXT,
  exit_code     INTEGER,
  duration_ms   INTEGER,
  input_tokens  INTEGER,
  output_tokens INTEGER,
  cost_usd      REAL,
  output        TEXT,
  git_before    TEXT,
  git_after     TEXT,
  dirty_files   INTEGER,
  note          TEXT
);




















