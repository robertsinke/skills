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
OPENKNOWLEDGE_TARGET="$OPENKNOWLEDGE_PROJECT/automations/heartbeat"
assert_dir "$OPENKNOWLEDGE_TARGET/.ok/templates"
assert_file "$OPENKNOWLEDGE_TARGET/.ok/templates/heartbeat.md"
assert_file "$OPENKNOWLEDGE_TARGET/.ok/templates/runs.md"
assert_file "$OPENKNOWLEDGE_TARGET/HEARTBEAT.md"
assert_file "$OPENKNOWLEDGE_TARGET/RUNS.md"
python3 "$OPENKNOWLEDGE_TARGET/validate-heartbeat.py" "$OPENKNOWLEDGE_TARGET/HEARTBEAT.md" >/dev/null
assert_contains "title: Heartbeat" "$OPENKNOWLEDGE_TARGET/HEARTBEAT.md"
assert_contains "title: Heartbeat runs" "$OPENKNOWLEDGE_TARGET/RUNS.md"
(cd "$OPENKNOWLEDGE_TARGET" && ./heartbeat-report.sh)
assert_contains "title: Heartbeat runs" "$OPENKNOWLEDGE_TARGET/RUNS.md"
assert_contains "# Heartbeat runs" "$OPENKNOWLEDGE_TARGET/RUNS.md"

PLAIN_PROJECT="$TEST_ROOT/plain-project"
mkdir -p "$PLAIN_PROJECT"
(cd "$PLAIN_PROJECT" && bash "$INIT_SCRIPT" >/dev/null)
PLAIN_TARGET="$PLAIN_PROJECT/automations/heartbeat"
assert_dir "$PLAIN_TARGET/.templates"
assert_file "$PLAIN_TARGET/.templates/heartbeat.md"
assert_file "$PLAIN_TARGET/.templates/runs.md"
[ ! -d "$PLAIN_TARGET/.ok/templates" ] || fail "plain project unexpectedly used .ok/templates"
python3 "$PLAIN_TARGET/validate-heartbeat.py" "$PLAIN_TARGET/HEARTBEAT.md" >/dev/null

printf 'PASS: heartbeat validator and initialization\n'
