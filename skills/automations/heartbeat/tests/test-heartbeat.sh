#!/usr/bin/env bash
# shellcheck disable=SC2016 # Markdown fixture backticks must remain literal.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$TEST_DIR/.." && pwd)"
VALIDATOR="$SKILL_DIR/scripts/validate-heartbeat.py"
INIT_SCRIPT="$SKILL_DIR/scripts/init.sh"
TEST_ROOT="$(mktemp -d /tmp/heartbeat-tests.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

assert_contains() {
  grep -qF "$1" "$2" || fail "$2 does not contain: $1"
}

python3 "$VALIDATOR" "$SKILL_DIR/templates/HEARTBEAT.md.template" >/dev/null

LEGACY_FILE="$TEST_ROOT/legacy.md"
printf '%s\n' \
  'tasks:' \
  '  - name: legacy-check' \
  '    interval: 1d' \
  '    prompt: "Legacy installations remain valid."' > "$LEGACY_FILE"
python3 "$VALIDATOR" "$LEGACY_FILE" >/dev/null

ESCAPED_PIPE_FILE="$TEST_ROOT/escaped-pipe.md"
printf '%s\n' \
  '| Task | Interval | Prompt |' \
  '|---|---|---|' \
  '| `pipe-check` | `1d` | Compare A \| B. |' > "$ESCAPED_PIPE_FILE"
python3 "$VALIDATOR" "$ESCAPED_PIPE_FILE" >/dev/null

DUPLICATE_SOURCE_FILE="$TEST_ROOT/duplicate-source.md"
cp "$SKILL_DIR/templates/HEARTBEAT.md.template" "$DUPLICATE_SOURCE_FILE"
printf '%s\n' \
  '' \
  'tasks:' \
  '  - name: legacy-check' \
  '    interval: 1d' \
  '    prompt: "This second source must be rejected."' >> "$DUPLICATE_SOURCE_FILE"
if python3 "$VALIDATOR" "$DUPLICATE_SOURCE_FILE" > "$TEST_ROOT/duplicate-source.out" 2>&1; then
  fail "validator accepted both table and legacy task sources"
fi
assert_contains "keep one source of truth" "$TEST_ROOT/duplicate-source.out"

MISSING_PROMPT_FILE="$TEST_ROOT/missing-prompt.md"
printf '%s\n' \
  '| Task | Interval | Prompt |' \
  '|---|---|---|' \
  '| `missing-prompt` | `1d` | |' > "$MISSING_PROMPT_FILE"
if python3 "$VALIDATOR" "$MISSING_PROMPT_FILE" > "$TEST_ROOT/missing-prompt.out" 2>&1; then
  fail "validator accepted a task without a prompt"
fi
assert_contains "missing required prompt" "$TEST_ROOT/missing-prompt.out"

DUPLICATE_TASK_FILE="$TEST_ROOT/duplicate-task.md"
printf '%s\n' \
  '| Task | Interval | Prompt |' \
  '|---|---|---|' \
  '| `same-task` | `1d` | First check. |' \
  '| `same-task` | `7d` | Second check. |' > "$DUPLICATE_TASK_FILE"
if python3 "$VALIDATOR" "$DUPLICATE_TASK_FILE" > "$TEST_ROOT/duplicate-task.out" 2>&1; then
  fail "validator accepted duplicate task names"
fi
assert_contains "duplicate task name: same-task" "$TEST_ROOT/duplicate-task.out"

INVALID_FRONTMATTER_FILE="$TEST_ROOT/invalid-frontmatter.md"
printf '%s\n' \
  '---' \
  'enabled: sometimes' \
  '---' \
  '| Task | Interval | Prompt |' \
  '|---|---|---|' \
  '| `valid-task` | `1d` | Valid check. |' > "$INVALID_FRONTMATTER_FILE"
if python3 "$VALIDATOR" "$INVALID_FRONTMATTER_FILE" > "$TEST_ROOT/invalid-frontmatter.out" 2>&1; then
  fail "validator accepted an invalid frontmatter enabled value"
fi
assert_contains "frontmatter 'enabled' must be true or false" "$TEST_ROOT/invalid-frontmatter.out"

OPENKNOWLEDGE_PROJECT="$TEST_ROOT/openknowledge-project"
mkdir -p "$OPENKNOWLEDGE_PROJECT/records/.ok/templates"
(cd "$OPENKNOWLEDGE_PROJECT" && bash "$INIT_SCRIPT" >/dev/null)
OPENKNOWLEDGE_AUTOMATIONS="$OPENKNOWLEDGE_PROJECT/automations"
OPENKNOWLEDGE_RUNTIME="$OPENKNOWLEDGE_AUTOMATIONS/_heartbeat"
assert_dir "$OPENKNOWLEDGE_AUTOMATIONS/.ok/templates"
assert_file "$OPENKNOWLEDGE_AUTOMATIONS/.ok/frontmatter.yml"
assert_file "$OPENKNOWLEDGE_AUTOMATIONS/.ok/templates/heartbeat.md"
[ ! -e "$OPENKNOWLEDGE_AUTOMATIONS/.ok/templates/runs.md" ] || fail "generated RUNS.md is exposed as a stampable template"
assert_file "$OPENKNOWLEDGE_AUTOMATIONS/CONTEXT.md"
assert_file "$OPENKNOWLEDGE_AUTOMATIONS/HEARTBEAT.md"
assert_file "$OPENKNOWLEDGE_AUTOMATIONS/RUNS.md"
assert_file "$OPENKNOWLEDGE_RUNTIME/.heartbeat.db"
assert_file "$OPENKNOWLEDGE_RUNTIME/.gitignore"
assert_contains '.heartbeat.db' "$OPENKNOWLEDGE_RUNTIME/.gitignore"
python3 "$OPENKNOWLEDGE_RUNTIME/validate-heartbeat.py" "$OPENKNOWLEDGE_AUTOMATIONS/HEARTBEAT.md" >/dev/null
assert_contains "title: Heartbeat" "$OPENKNOWLEDGE_AUTOMATIONS/HEARTBEAT.md"
assert_contains "title: Heartbeat runs" "$OPENKNOWLEDGE_AUTOMATIONS/RUNS.md"
(cd "$OPENKNOWLEDGE_RUNTIME" && ./heartbeat-report.sh)
assert_contains "title: Heartbeat runs" "$OPENKNOWLEDGE_AUTOMATIONS/RUNS.md"
assert_contains "# Heartbeat runs" "$OPENKNOWLEDGE_AUTOMATIONS/RUNS.md"

PLAIN_PROJECT="$TEST_ROOT/plain-project"
mkdir -p "$PLAIN_PROJECT"
(cd "$PLAIN_PROJECT" && bash "$INIT_SCRIPT" >/dev/null)
PLAIN_AUTOMATIONS="$PLAIN_PROJECT/automations"
PLAIN_RUNTIME="$PLAIN_AUTOMATIONS/_heartbeat"
assert_dir "$PLAIN_AUTOMATIONS/.templates"
assert_file "$PLAIN_AUTOMATIONS/.templates/heartbeat.md"
[ ! -e "$PLAIN_AUTOMATIONS/.templates/runs.md" ] || fail "generated RUNS.md is exposed as a stampable template"
[ ! -d "$PLAIN_AUTOMATIONS/.ok/templates" ] || fail "plain project unexpectedly used .ok/templates"
python3 "$PLAIN_RUNTIME/validate-heartbeat.py" "$PLAIN_AUTOMATIONS/HEARTBEAT.md" >/dev/null

LEGACY_PROJECT="$TEST_ROOT/legacy-project"
LEGACY_DIR="$LEGACY_PROJECT/automations/heartbeat"
mkdir -p "$LEGACY_DIR/.ok/templates"
cp "$SKILL_DIR/templates/HEARTBEAT.md.template" "$LEGACY_DIR/HEARTBEAT.md"
cp "$SKILL_DIR/templates/RUNS.md.template" "$LEGACY_DIR/RUNS.md"
cp "$SKILL_DIR/templates/HEARTBEAT.md.template" "$LEGACY_DIR/.ok/templates/heartbeat.md"
cp "$SKILL_DIR/templates/RUNS.md.template" "$LEGACY_DIR/.ok/templates/runs.md"
sqlite3 "$LEGACY_DIR/.heartbeat.db" < "$SKILL_DIR/scripts/schema.sql"
sqlite3 "$LEGACY_DIR/.heartbeat.db" "INSERT INTO runs (ts, date, time, status, output) VALUES ('2026-01-01T00:00:00Z','2026-01-01','00:00:00','ok','preserved');"
printf '%s\n' '{"agent":"codex"}' > "$LEGACY_DIR/.heartbeat.json"
(cd "$LEGACY_PROJECT" && bash "$INIT_SCRIPT" >/dev/null)
assert_file "$LEGACY_PROJECT/automations/HEARTBEAT.md"
assert_file "$LEGACY_PROJECT/automations/RUNS.md"
assert_file "$LEGACY_PROJECT/automations/_heartbeat/.heartbeat.db"
assert_file "$LEGACY_PROJECT/automations/_heartbeat/.heartbeat.json"
assert_file "$LEGACY_PROJECT/automations/_heartbeat/legacy-runs-template.md"
[ "$(sqlite3 "$LEGACY_PROJECT/automations/_heartbeat/.heartbeat.db" 'SELECT output FROM runs WHERE id=1;')" = preserved ] || fail "legacy run history was not preserved"
[ ! -d "$LEGACY_DIR" ] || fail "empty legacy heartbeat directory remains after migration"

printf '%s\n' \
  '# Project' \
  '' \
  '## Automation' \
  'Scheduled checks live under automations/. Current: automations/heartbeat/ (checklist: HEARTBEAT.md, history: RUNS.md).' > "$LEGACY_PROJECT/AGENTS.md"
FAKE_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CRONTAB="$TEST_ROOT/crontab.txt"
mkdir -p "$FAKE_HOME" "$FAKE_BIN"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [ "${1:-}" = -l ]; then [ ! -f "$FAKE_CRONTAB" ] || cat "$FAKE_CRONTAB"; exit 0; fi' \
  'cp "$1" "$FAKE_CRONTAB"' > "$FAKE_BIN/crontab"
chmod +x "$FAKE_BIN/crontab"
printf '*/30 * * * * cd %s/automations/heartbeat && ./heartbeat-run.sh && ./heartbeat-report.sh\n' "$LEGACY_PROJECT" > "$FAKE_CRONTAB"
(cd "$LEGACY_PROJECT" && HOME="$FAKE_HOME" bash "$SKILL_DIR/scripts/register.sh" >/dev/null)
assert_contains 'Scheduled checks live in automations/ (checklist: HEARTBEAT.md, history: RUNS.md; runtime: _heartbeat/).' "$LEGACY_PROJECT/AGENTS.md"
if grep -qF 'Current: automations/heartbeat/' "$LEGACY_PROJECT/AGENTS.md"; then fail "legacy AGENTS.md pointer remains"; fi
(cd "$LEGACY_PROJECT" && PATH="$FAKE_BIN:$PATH" FAKE_CRONTAB="$FAKE_CRONTAB" bash "$SKILL_DIR/scripts/schedule.sh" enable >/dev/null)
assert_contains "$LEGACY_PROJECT/automations/_heartbeat" "$FAKE_CRONTAB"
if grep -qF "$LEGACY_PROJECT/automations/heartbeat" "$FAKE_CRONTAB"; then fail "legacy cron path remains"; fi

printf 'PASS: heartbeat split creation, migration, registration, and scheduling\n'
