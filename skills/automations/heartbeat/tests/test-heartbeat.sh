#!/usr/bin/env bash
# shellcheck disable=SC2016 # fixture scripts and Markdown must stay literal
set -euo pipefail
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$TEST_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/heartbeat-v2-tests.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
assert_file() { [ -f "$1" ] || fail "missing $1"; }
assert_contains() { grep -qF "$1" "$2" || fail "$2 lacks $1"; }

FAKE_BIN="$TEST_ROOT/bin"; mkdir -p "$FAKE_BIN"
for name in claude codex agent opencode; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  --version) echo "fake 1.0" ;;' \
    '  models) if [ "$(basename "$0")" = agent ]; then echo "test-model"; else echo "test/provider-model"; fi ;;' \
    '  *) if [ "$(basename "$0")" = codex ]; then printf '\''{"type":"item.completed","item":{"type":"agent_message","text":"HEARTBEAT_OK"}}\n'\''; else printf '\''{"result":"HEARTBEAT_OK"}\n'\''; fi ;;' \
    'esac' > "$FAKE_BIN/$name"
  chmod +x "$FAKE_BIN/$name"
done

PROJECT="$TEST_ROOT/project"
mkdir -p "$PROJECT/.ok/templates"
(cd "$PROJECT" && PATH="$FAKE_BIN:$PATH" bash "$SKILL_DIR/scripts/init.sh" >/dev/null)
AUTO="$PROJECT/automations"; RUN="$AUTO/_heartbeat"
assert_file "$AUTO/example-automation.md"
assert_file "$AUTO/DASHBOARD.md"
assert_file "$AUTO/AGENT-OPTIONS.md"
assert_file "$AUTO/RUNS.md"
assert_file "$AUTO/.ok/templates/automation.md"
assert_file "$AUTO/.ok/frontmatter.yml"
assert_file "$RUN/heartbeat_engine.py"
[ ! -e "$AUTO/HEARTBEAT.md" ] || fail "clean install created legacy HEARTBEAT.md"
python3 "$RUN/validate-heartbeat.py" "$AUTO" >/dev/null
assert_contains '"models_status": "verified"' "$RUN/capabilities.json"

(cd "$RUN" && PATH="$FAKE_BIN:$PATH" ./heartbeat-run.sh)
[ "$(sqlite3 "$RUN/.heartbeat.db" 'SELECT task FROM runs ORDER BY id DESC LIMIT 1;')" = example-automation ] || fail "task run was not recorded"
assert_contains 'example-automation' "$AUTO/DASHBOARD.md"
assert_contains 'example-automation' "$AUTO/RUNS.md"

sqlite3 "$RUN/.heartbeat.db" 'DELETE FROM runs;'
(cd "$RUN" && PATH="/usr/bin:/bin" ./heartbeat-run.sh)
[ "$(sqlite3 "$RUN/.heartbeat.db" 'SELECT status FROM runs ORDER BY id DESC LIMIT 1;')" = ok ] || fail "cron-like PATH could not use discovered absolute agent path"

INVALID="$AUTO/bad-model.md"
sed 's/name: example-automation/name: bad-model/; s/title: Example automation/title: Bad model/; s/agent: auto/agent: cursor/; s/model: default/model: missing-model/' "$SKILL_DIR/templates/AUTOMATION.md.template" > "$INVALID"
if python3 "$RUN/validate-heartbeat.py" "$AUTO" > "$TEST_ROOT/invalid.out" 2>&1; then fail "invalid discovered model passed"; fi
assert_contains "model 'missing-model' is not available for cursor" "$TEST_ROOT/invalid.out"
rm "$INVALID"

LEGACY="$TEST_ROOT/legacy"; mkdir -p "$LEGACY/automations/_heartbeat" "$LEGACY/.ok/templates"
printf '%s\n' '---' 'title: Heartbeat runs' 'generated: true' '---' '' '# Heartbeat runs' > "$LEGACY/automations/RUNS.md"
printf '%s\n' \
  '---' 'title: Heartbeat' 'enabled: true' '---' '' '# Heartbeat' '' \
  '| Task | Interval | Prompt |' '|---|---|---|' \
  '| `daily-briefing` | `1d` | Prepare a briefing. |' \
  '| `dead-links` | `30d` | Check links. |' > "$LEGACY/automations/HEARTBEAT.md"
sqlite3 "$LEGACY/automations/_heartbeat/.heartbeat.db" 'CREATE TABLE runs (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, date TEXT, time TEXT, status TEXT, output TEXT); INSERT INTO runs(ts,date,time,status,output) VALUES("2026-01-01","2026-01-01","00:00:00","ok","preserved");'
(cd "$LEGACY" && PATH="$FAKE_BIN:$PATH" bash "$SKILL_DIR/scripts/init.sh" >/dev/null)
assert_file "$LEGACY/automations/daily-briefing.md"
assert_file "$LEGACY/automations/dead-links.md"
assert_file "$LEGACY/automations/_heartbeat/legacy-HEARTBEAT.md"
[ "$(sqlite3 "$LEGACY/automations/_heartbeat/.heartbeat.db" 'SELECT output FROM runs WHERE id=1;')" = preserved ] || fail "legacy history lost"
python3 "$LEGACY/automations/_heartbeat/validate-heartbeat.py" "$LEGACY/automations" >/dev/null

CRON_BIN="$TEST_ROOT/cron-bin"; CRON_FILE="$TEST_ROOT/crontab"; mkdir -p "$CRON_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = -l ]; then [ ! -f "$CRON_FILE" ] || cat "$CRON_FILE"; else cp "$1" "$CRON_FILE"; fi' > "$CRON_BIN/crontab"
chmod +x "$CRON_BIN/crontab"
printf '*/30 * * * * cd %s/automations/_heartbeat && ./heartbeat-run.sh && ./heartbeat-report.sh\n' "$PROJECT" > "$CRON_FILE"
(cd "$PROJECT" && CRON_FILE="$CRON_FILE" PATH="$CRON_BIN:$PATH" bash "$SKILL_DIR/scripts/schedule.sh" enable >/dev/null)
assert_contains "*/5 * * * * cd $PROJECT/automations/_heartbeat" "$CRON_FILE"

echo "PASS: task files, strict validation, capabilities, execution, views, migration, and scheduling"
