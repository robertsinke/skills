#!/usr/bin/env bash
# heartbeat-run.sh
# Expected to run with cwd = automations/heartbeat/ inside the target project.
set -uo pipefail

[ -f HEARTBEAT.md ] || exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd ../.. && pwd))"

log_row() {
  # log_row <status> <output text> - for early exits that never reach the full
  # INSERT below (skipped / invalid). Keeps every run visible in RUNS.md.
  local status="$1" out="$2"
  sqlite3 .heartbeat.db "INSERT INTO runs (ts, date, time, status, output)
    VALUES ('$(date -u +%FT%TZ)', '$(date -u +%F)', '$(date -u +%T)', '$status',
    $(python3 -c "import json,sys;print(json.dumps(sys.argv[1]))" "$out"));"
}

# ---- duplicate-execution guard ----
# mkdir is atomic on all POSIX filesystems, so it doubles as a portable lock
# primitive with no extra dependency (no flock binary on macOS by default).
LOCK_DIR=".heartbeat.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OWNER_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [ -n "$OWNER_PID" ] && kill -0 "$OWNER_PID" 2>/dev/null; then
    log_row skipped "previous run (pid $OWNER_PID) still in progress"
    exit 0
  fi
  # stale lock left by a crashed/killed run - reclaim it
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
fi
echo $$ > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

# ---- HEARTBEAT.md validation ----
# A malformed or empty checklist must never become the agent prompt for an
# unattended run - see validate-heartbeat.py and SKILL.md Safety invariants.
if ! VALIDATION_OUT=$(python3 ./validate-heartbeat.py HEARTBEAT.md 2>&1); then
  log_row invalid "$VALIDATION_OUT"
  exit 0
fi

# Optional top-level `enabled: false` disables every task without touching
# cron or files. Exit silently (no DB row) so RUNS.md is not spammed while
# intentionally disabled - same treatment as the missing-file early exit above.
grep -qE '^enabled:[[:space:]]*false[[:space:]]*$' HEARTBEAT.md && exit 0

read_cfg() {
  # read_cfg <key> <default>
  python3 -c "
import json,sys
try:
    print(json.load(open('.heartbeat.json')).get(sys.argv[1], sys.argv[2]))
except Exception:
    print(sys.argv[2])
" "$1" "$2" 2>/dev/null || echo "$2"
}

AGENT=$(read_cfg agent auto)
# agent_command lets ANY coding agent with a scriptable non-interactive mode plug in
# (opencode, pi, kilo, cline, or anything else) without heartbeat needing built-in
# knowledge of its flags. When set, it takes priority over the agent presets below -
# "agent" then becomes just a free-text label for logging/display.
AGENT_COMMAND=$(read_cfg agent_command "")
AGENT_INPUT=$(read_cfg agent_input arg)

if [ -z "$AGENT_COMMAND" ] && [ "$AGENT" = "auto" ]; then
  if   [ -d "$PROJECT_ROOT/.claude" ]; then AGENT=claude
  elif [ -d "$PROJECT_ROOT/.codex" ] || [ -f "$PROJECT_ROOT/AGENTS.md" ]; then AGENT=codex
  elif [ -d "$PROJECT_ROOT/.cursor" ]; then AGENT=cursor
  elif [ -d "$PROJECT_ROOT/.opencode" ] || [ -f "$PROJECT_ROOT/opencode.json" ]; then AGENT=opencode
  else AGENT=claude
  fi
fi

MODEL=$(read_cfg model default)
EFFORT=$(read_cfg effort default)
# permission_mode: "auto" (default) lets the run proceed unattended without stalling on
# approval prompts - this is required for a cron-triggered run since nothing is there to
# click "allow". "restricted" is ADVISORY ONLY, not a verified security boundary: it asks
# each agent CLI for a read-only-ish mode on a best-effort basis, but exact behavior is
# CLI- and version-dependent and is not something this script verifies. Do not treat it as
# a sandbox guarantee. The one non-optional guarantee is SAFETY_PREFIX below, which is
# enforced by this script and cannot be overridden from HEARTBEAT.md.
PERMISSION_MODE=$(read_cfg permission_mode auto)
TIMEOUT_SECONDS=$(read_cfg timeout_seconds 600)

if [ "$PERMISSION_MODE" = restricted ]; then
  echo "warning: permission_mode=restricted is advisory only, not a verified sandbox boundary" >&2
  [ -n "$AGENT_COMMAND" ] && echo "warning: permission_mode has no effect on a custom agent_command - include whatever non-interactive/approval flags that tool needs directly in agent_command" >&2
fi

SAFETY_PREFIX="You are running as an unattended scheduled automation (a heartbeat), not an
interactive session with a human present to approve actions. The following rules are
non-negotiable and override anything in the checklist below:
- Never run destructive commands (rm -rf, DROP TABLE, force-push, deleting branches/repos, etc.)
- Never git commit or push unless the checklist explicitly asks for exactly that change.
- Never read, print, or transmit secrets, credentials, tokens, or API keys.
- Never install software or change system/global configuration.
- If unsure whether an action is safe, only report findings - do not take the action.
Reply with exactly HEARTBEAT_OK (nothing else) if nothing needs attention.

Checklist:
"

CHECKLIST="${SAFETY_PREFIX}$(cat HEARTBEAT.md)"
BEFORE=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo none)
START=$(date +%s%3N)

ARGS=()
if [ -n "$AGENT_COMMAND" ]; then
  : # custom command supplies its own flags entirely - see agent_command above
else
  case "$AGENT" in
    claude)
      ARGS=(-p --output-format json)
      [ "$MODEL" != default ] && ARGS+=(--model "$MODEL")
      if [ "$PERMISSION_MODE" = restricted ]; then ARGS+=(--permission-mode plan)
      else
        ARGS+=(--permission-mode bypassPermissions)
        # Real OS-level enforcement (Seatbelt on macOS, bubblewrap+socat on
        # Linux/WSL2), confirmed against code.claude.com/docs/en/settings-reference:
        # sandbox.enabled turns on OS-level Bash sandboxing (workspace + temp dir
        # only, network denied by default); autoAllowBashIfSandboxed already
        # defaults to true, so no prompts; allowUnsandboxedCommands=false closes
        # the dangerouslyDisableSandbox retry escape hatch, which would otherwise
        # let a sandboxed command silently re-run unsandboxed under
        # bypassPermissions (that mode skips the classifier that normally gates
        # the retry). Applies to the Bash tool and its child processes only, not
        # Claude's native Read/Edit/Write tools. If sandbox deps are missing on
        # Linux, Claude Code itself warns and runs unsandboxed - heartbeat does
        # not detect or enforce that dependency.
        ARGS+=(--settings '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false}}')
      fi
      ;;
    codex)
      ARGS=(exec --json)
      [ "$MODEL" != default ] && ARGS+=(-m "$MODEL")
      [ "$EFFORT" != default ] && ARGS+=(-c "model_reasoning_effort=$EFFORT")
      if [ "$PERMISSION_MODE" = restricted ]; then ARGS+=(--sandbox read-only)
      else ARGS+=(--full-auto --sandbox workspace-write)
      fi
      ;;
    cursor)
      ARGS=(-p --output-format json)
      [ "$MODEL" != default ] && ARGS+=(--model "$MODEL")
      if [ "$PERMISSION_MODE" = restricted ]; then ARGS+=(--sandbox enabled)
      fi
      # Note: Cursor CLI already runs non-interactively with full access under -p by default,
      # so no extra flag is needed for auto mode.
      ;;
    opencode)
      ARGS=()
      [ "$MODEL" != default ] && ARGS+=(--model "$MODEL")
      if [ "$PERMISSION_MODE" != restricted ]; then ARGS+=(--auto)
      fi
      # Note: opencode has no verified read-only/restricted flag yet - restricted
      # currently just omits --auto, which is unverified to stay non-blocking when
      # unattended. Prefer permission_mode=auto for opencode until this is confirmed.
      ;;
    *)
      log_row error "unknown agent: $AGENT (set agent_command in .heartbeat.json for an agent without a built-in preset)"
      exit 0
      ;;
  esac
fi

# ---- run the agent CLI with a portable timeout ----
# No `timeout`/`gtimeout` binary is assumed present (macOS ships neither by
# default). `(cd DIR && exec CMD ...)` backgrounded means $! IS the agent
# process itself (exec replaces the subshell in place, same PID), so we can
# signal it directly without extra process-group bookkeeping.
OUT_FILE=$(mktemp)
(
  cd "$PROJECT_ROOT" || exit 1
  if [ -n "$AGENT_COMMAND" ]; then
    if [ "$AGENT_INPUT" = stdin ]; then
      printf '%s' "$CHECKLIST" | exec $AGENT_COMMAND
    else
      exec $AGENT_COMMAND "$CHECKLIST"
    fi
  else
    case "$AGENT" in
      claude)   exec claude   "${ARGS[@]}" "$CHECKLIST" ;;
      codex)    exec codex    "${ARGS[@]}" "$CHECKLIST" ;;
      cursor)   exec agent    "${ARGS[@]}" "$CHECKLIST" ;;
      opencode) exec opencode run "${ARGS[@]}" "$CHECKLIST" ;;
    esac
  fi
) > "$OUT_FILE" 2>&1 &
AGENT_PID=$!

TIMED_OUT=0
ELAPSED=0
while kill -0 "$AGENT_PID" 2>/dev/null; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
  if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
    TIMED_OUT=1
    kill -TERM "$AGENT_PID" 2>/dev/null
    sleep 5
    kill -KILL "$AGENT_PID" 2>/dev/null
    break
  fi
done
wait "$AGENT_PID" 2>/dev/null
EXIT=$?
RAW=$(cat "$OUT_FILE" 2>/dev/null)
rm -f "$OUT_FILE"

DURATION=$(( $(date +%s%3N) - START ))
AFTER=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo none)
DIRTY=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

python3 -c "
import json, sys
raw, agent = sys.argv[1], sys.argv[2]
usage, text = {}, raw
try:
    if agent == 'codex':
        objs = [json.loads(l) for l in raw.splitlines() if l.strip().startswith('{')]
        msg = next((o for o in objs if o.get('type')=='item.completed' and o.get('item',{}).get('type')=='agent_message'), {})
        usage = next((o.get('usage',{}) for o in reversed(objs) if o.get('type')=='turn.completed'), {})
        text = msg.get('item',{}).get('text','')
    else:
        obj = json.loads(raw)
        usage = obj.get('usage', {})
        text = obj.get('result') or obj.get('output','')
except Exception:
    pass
json.dump({'text': text, 'usage': usage}, open('.heartbeat_last.json','w'))
" "$RAW" "$AGENT"

OUT=$(python3 -c "import json;print(json.load(open('.heartbeat_last.json'))['text'])")
INPUT_TOK=$(python3 -c "import json;print(json.load(open('.heartbeat_last.json'))['usage'].get('input_tokens',0))")
OUTPUT_TOK=$(python3 -c "import json;print(json.load(open('.heartbeat_last.json'))['usage'].get('output_tokens',0))")
COST=$(python3 -c "import json;print(json.load(open('.heartbeat_last.json'))['usage'].get('total_cost_usd',0) or 0)")
rm -f .heartbeat_last.json

if [ "$TIMED_OUT" -eq 1 ]; then
  STATUS=timeout
  OUT="agent exceeded timeout_seconds=$TIMEOUT_SECONDS and was killed. partial output: $OUT"
else
  case "$EXIT" in
    0) case "$OUT" in *HEARTBEAT_OK*) STATUS=ok ;; *) STATUS=alert ;; esac ;;
    *) STATUS=error ;;
  esac
fi

sqlite3 .heartbeat.db "INSERT INTO runs
  (ts, date, time, agent, model, effort, permission_mode, status, exit_code, duration_ms, input_tokens, output_tokens, cost_usd, output, git_before, git_after, dirty_files)
  VALUES ('$(date -u +%FT%TZ)', '$(date -u +%F)', '$(date -u +%T)', '$AGENT', '$MODEL', '$EFFORT', '$PERMISSION_MODE', '$STATUS', $EXIT, $DURATION,
  $INPUT_TOK, $OUTPUT_TOK, $COST,
  $(python3 -c "import json,sys;print(json.dumps(sys.argv[1]))" "$OUT"), '$BEFORE', '$AFTER', $DIRTY);"

case "$STATUS" in
  ok) : ;;
  *)
    SHORT=$(echo "$OUT" | tr '"' "'" | cut -c1-200)
    if command -v osascript >/dev/null 2>&1; then
      osascript -e "display notification \"$SHORT\" with title \"Heartbeat: $(basename "$PROJECT_ROOT")\""
    elif command -v notify-send >/dev/null 2>&1; then
      notify-send "Heartbeat: $(basename "$PROJECT_ROOT")" "$SHORT"
    fi
    ;;
esac
