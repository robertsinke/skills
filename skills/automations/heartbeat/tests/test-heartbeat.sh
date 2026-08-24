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
  cat > "$FAKE_BIN/$name" <<'FAKE_AGENT'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "fake 1.0" ;;
  auth) echo '{"loggedIn":true}' ;;
  login) echo "Logged in using ChatGPT" ;;
  models) if [ "$(basename "$0")" = agent ]; then echo "test-model"; else echo "test/provider-model"; fi ;;
  *)
    # Simulate a well-behaved agent honoring the "append your findings to
    # <report_path>" instruction embedded in the prompt (last argument).
    prompt="${*: -1}"
    report_path=$(printf '%s' "$prompt" | grep -oE 'automations/tasks/\.execution-reports/[a-z0-9-]+\.md' | head -1)
    if [ -n "$report_path" ]; then
      mkdir -p "$(dirname "$report_path")"
      printf '## fake-run\nfake findings\n' >> "$report_path"
    fi
    if [ "$(basename "$0")" = codex ]; then
      printf '{"type":"item.completed","item":{"type":"agent_message","text":"HEARTBEAT_OK"}}\n'
    else
      printf '{"result":"HEARTBEAT_OK"}\n'
    fi
    ;;
esac
FAKE_AGENT
  chmod +x "$FAKE_BIN/$name"
done

PROJECT="$TEST_ROOT/project"
mkdir -p "$PROJECT/.ok/templates"
(cd "$PROJECT" && PATH="$FAKE_BIN:$PATH" bash "$SKILL_DIR/scripts/init.sh" >/dev/null)
AUTO="$PROJECT/automations"; RUN="$AUTO/_heartbeat"
assert_file "$AUTO/tasks/example-automation.md"
assert_file "$AUTO/INDEX.md"
assert_file "$RUN/AGENT-OPTIONS.md"
assert_file "$AUTO/tasks/.ok/templates/automation.md"
assert_file "$AUTO/.ok/frontmatter.yml"
assert_file "$AUTO/tasks/.ok/frontmatter.yml"
assert_file "$RUN/heartbeat_engine.py"
[ ! -e "$AUTO/HEARTBEAT.md" ] || fail "clean install created legacy HEARTBEAT.md"
[ ! -e "$AUTO/AGENT-OPTIONS.md" ] || fail "agent options remained at automations root"
[ "$(find "$AUTO" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | sort | tr '\n' ' ')" = "CONTEXT.md INDEX.md " ] || fail "unexpected Markdown file at automations root"
python3 "$RUN/validate-heartbeat.py" "$AUTO" >/dev/null
python3 "$RUN/validate-heartbeat.py" "$AUTO/tasks" >/dev/null
python3 "$RUN/validate-heartbeat.py" "$AUTO/tasks/example-automation.md" >/dev/null
assert_contains '"models_status": "verified"' "$RUN/capabilities.json"
assert_contains '"auth_status": "authenticated"' "$RUN/capabilities.json"
python3 -c 'import importlib.util,sys; s=importlib.util.spec_from_file_location("heartbeat_engine",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); task={"model":"default","effort":"default","permission_mode":"auto"}; cmd=m.command_for(task,"codex",None); assert "--approve-for-me" in cmd and "--sandbox" not in cmd' "$RUN/heartbeat_engine.py"

(cd "$RUN" && PATH="$FAKE_BIN:$PATH" ./heartbeat-run.sh)
[ "$(sqlite3 "$RUN/.heartbeat.db" 'SELECT task FROM runs ORDER BY id DESC LIMIT 1;')" = example-automation ] || fail "task run was not recorded"
assert_contains 'example-automation' "$AUTO/INDEX.md"
assert_contains 'tasks/example-automation.md' "$AUTO/INDEX.md"
assert_contains '_heartbeat/AGENT-OPTIONS.md' "$AUTO/INDEX.md"

# The fake agent honored the "append your findings" instruction embedded in
# the prompt: the run should carry a report_path, and INDEX.md should link to
# the report instead of showing inline fallback text.
REPORT="$AUTO/tasks/.execution-reports/example-automation.md"
assert_file "$REPORT"
assert_contains 'fake findings' "$REPORT"
[ "$(sqlite3 "$RUN/.heartbeat.db" 'SELECT report_path FROM runs ORDER BY id DESC LIMIT 1;')" = "tasks/.execution-reports/example-automation.md" ] || fail "run was not recorded with a report_path"
assert_contains '[report](tasks/.execution-reports/example-automation.md)' "$AUTO/INDEX.md"

(cd "$PROJECT" && HOME="$TEST_ROOT/home" bash "$SKILL_DIR/scripts/heartbeat" automations add second-task >/dev/null)
assert_file "$AUTO/tasks/second-task.md"
rm "$AUTO/tasks/second-task.md"

printf '%s\n' '# Test' '' '## Automation' 'Scheduled checks live in automations/ (checklist: HEARTBEAT.md, history: RUNS.md; runtime: \_heartbeat/).' > "$PROJECT/AGENTS.md"
(cd "$PROJECT" && HOME="$TEST_ROOT/home" bash "$SKILL_DIR/scripts/heartbeat" register >/dev/null)
assert_contains 'Scheduled automation tasks live in automations/tasks/' "$PROJECT/AGENTS.md"
assert_contains 'INDEX.md' "$PROJECT/AGENTS.md"
[ "$(grep -c '^Scheduled ' "$PROJECT/AGENTS.md")" = 1 ] || fail "registration duplicated the automation pointer"

# Re-registering a project stuck on the pre-INDEX.md pointer wording (as any
# already-registered project has post-upgrade) must update it, not leave it stale.
printf '%s\n' '# Test' '' '## Automation' 'Scheduled automation tasks live in automations/tasks/ (overview: automations/DASHBOARD.md, history: automations/RUNS.md; runtime and local agent choices: automations/_heartbeat/).' > "$PROJECT/AGENTS.md"
(cd "$PROJECT" && HOME="$TEST_ROOT/home" bash "$SKILL_DIR/scripts/heartbeat" register >/dev/null)
assert_contains 'INDEX.md' "$PROJECT/AGENTS.md"
grep -q 'DASHBOARD.md' "$PROJECT/AGENTS.md" && fail "re-registration left stale DASHBOARD.md reference"
[ "$(grep -c '^Scheduled ' "$PROJECT/AGENTS.md")" = 1 ] || fail "re-registration duplicated the automation pointer"

sqlite3 "$RUN/.heartbeat.db" 'DELETE FROM runs;'
(cd "$RUN" && PATH="/usr/bin:/bin" ./heartbeat-run.sh)
[ "$(sqlite3 "$RUN/.heartbeat.db" 'SELECT status FROM runs ORDER BY id DESC LIMIT 1;')" = ok ] || fail "cron-like PATH could not use discovered absolute agent path"

INVALID="$AUTO/tasks/bad-model.md"
sed 's/name: example-automation/name: bad-model/; s/title: Example automation/title: Bad model/; s/agent: auto/agent: cursor/; s/model: default/model: missing-model/' "$SKILL_DIR/templates/AUTOMATION.md.template" > "$INVALID"
if python3 "$RUN/validate-heartbeat.py" "$AUTO" > "$TEST_ROOT/invalid.out" 2>&1; then fail "invalid discovered model passed"; fi
assert_contains "model 'missing-model' is not available for cursor" "$TEST_ROOT/invalid.out"
rm "$INVALID"

sed 's/name: example-automation/name: logged-out/; s/title: Example automation/title: Logged out/; s/agent: auto/agent: claude/' "$SKILL_DIR/templates/AUTOMATION.md.template" > "$AUTO/tasks/logged-out.md"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["agents"]["claude"]["auth_status"]="unauthenticated"; open(p,"w").write(json.dumps(d))' "$RUN/capabilities.json"
if python3 "$RUN/validate-heartbeat.py" "$AUTO" > "$TEST_ROOT/auth.out" 2>&1; then fail "logged-out agent passed validation"; fi
assert_contains "agent 'claude' is installed but not authenticated" "$TEST_ROOT/auth.out"
rm "$AUTO/tasks/logged-out.md"
PATH="$FAKE_BIN:$PATH" python3 "$RUN/heartbeat_engine.py" scan "$AUTO"

LEGACY="$TEST_ROOT/legacy"; mkdir -p "$LEGACY/automations/_heartbeat" "$LEGACY/.ok/templates"
printf '%s\n' '.heartbeat.db' '.heartbeat.lock/' > "$LEGACY/automations/_heartbeat/.gitignore"
printf '%s\n' '---' 'title: Heartbeat runs' 'generated: true' '---' '' '# Heartbeat runs' > "$LEGACY/automations/RUNS.md"
printf '%s\n' \
  '---' 'title: Heartbeat' 'enabled: true' '---' '' '# Heartbeat' '' \
  '| Task | Interval | Prompt |' '|---|---|---|' \
  '| `daily-briefing` | `1d` | Prepare a briefing. |' \
  '| `dead-links` | `30d` | Check links. |' > "$LEGACY/automations/HEARTBEAT.md"
sqlite3 "$LEGACY/automations/_heartbeat/.heartbeat.db" 'CREATE TABLE runs (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, date TEXT, time TEXT, status TEXT, output TEXT); INSERT INTO runs(ts,date,time,status,output) VALUES("2026-01-01","2026-01-01","00:00:00","ok","preserved");'
(cd "$LEGACY" && PATH="$FAKE_BIN:$PATH" bash "$SKILL_DIR/scripts/init.sh" >/dev/null)
assert_file "$LEGACY/automations/tasks/daily-briefing.md"
assert_file "$LEGACY/automations/tasks/dead-links.md"
assert_file "$LEGACY/automations/_heartbeat/legacy-HEARTBEAT.md"
assert_contains 'capabilities.json' "$LEGACY/automations/_heartbeat/.gitignore"
assert_contains 'legacy-HEARTBEAT.md' "$LEGACY/automations/_heartbeat/.gitignore"
[ "$(sqlite3 "$LEGACY/automations/_heartbeat/.heartbeat.db" 'SELECT output FROM runs WHERE id=1;')" = preserved ] || fail "legacy history lost"
python3 "$LEGACY/automations/_heartbeat/validate-heartbeat.py" "$LEGACY/automations" >/dev/null

FLAT="$TEST_ROOT/flat"; mkdir -p "$FLAT/automations/.ok/templates" "$FLAT/automations/_heartbeat"
cp "$SKILL_DIR/templates/AUTOMATION.md.template" "$FLAT/automations/flat-task.md"
sed -i.bak 's/name: example-automation/name: flat-task/' "$FLAT/automations/flat-task.md"; rm "$FLAT/automations/flat-task.md.bak"
cp "$SKILL_DIR/templates/AUTOMATION.md.template" "$FLAT/automations/.ok/templates/automation.md"
printf '%s\n' '# old options' > "$FLAT/automations/AGENT-OPTIONS.md"
(cd "$FLAT" && PATH="$FAKE_BIN:$PATH" bash "$SKILL_DIR/scripts/init.sh" >/dev/null)
assert_file "$FLAT/automations/tasks/flat-task.md"
assert_file "$FLAT/automations/tasks/.ok/templates/automation.md"
assert_file "$FLAT/automations/_heartbeat/AGENT-OPTIONS.md"
[ ! -e "$FLAT/automations/flat-task.md" ] || fail "flat task was not migrated"
[ ! -e "$FLAT/automations/AGENT-OPTIONS.md" ] || fail "flat agent options was not migrated"

CRON_BIN="$TEST_ROOT/cron-bin"; CRON_FILE="$TEST_ROOT/crontab"; mkdir -p "$CRON_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = -l ]; then [ ! -f "$CRON_FILE" ] || cat "$CRON_FILE"; else cp "$1" "$CRON_FILE"; fi' > "$CRON_BIN/crontab"
chmod +x "$CRON_BIN/crontab"
printf '*/30 * * * * cd %s/automations/_heartbeat && ./heartbeat-run.sh && ./heartbeat-report.sh\n' "$PROJECT" > "$CRON_FILE"
(cd "$PROJECT" && CRON_FILE="$CRON_FILE" PATH="$CRON_BIN:$PATH" bash "$SKILL_DIR/scripts/schedule.sh" enable >/dev/null)
assert_contains "*/5 * * * * cd $PROJECT/automations/_heartbeat" "$CRON_FILE"

echo "PASS: task files, strict validation, capabilities, execution, views, migration, and scheduling"
