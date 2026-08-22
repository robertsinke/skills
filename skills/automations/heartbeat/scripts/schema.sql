CREATE TABLE IF NOT EXISTS runs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  ts            TEXT,
  date          TEXT,
  time          TEXT,
  agent         TEXT,
  model         TEXT,
  effort        TEXT,
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




















