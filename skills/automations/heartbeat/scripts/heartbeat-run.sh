#!/usr/bin/env bash
# heartbeat-run.sh
# Expected to run with cwd = automations/heartbeat/ inside the target project.
set -uo pipefail

[ -f HEARTBEAT.md ] || exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd ../.. && pwd))"

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
if [ "$AGENT" = "auto" ]; then
  if   [ -d "$PROJECT_ROOT/.claude" ]; then AGENT=claude
  elif [ -d "$PROJECT_ROOT/.codex" ] || [ -f "$PROJECT_ROOT/AGENTS.md" ]; then AGENT=codex
  elif [ -d "$PROJECT_ROOT/.cursor" ]; then AGENT=cursor
  else AGENT=claude
  fi
fi

MODEL=$(read_cfg model default)
EFFORT=$(read_cfg effort default)
# permission_mode: "auto" (default) lets the run proceed unattended without stalling on
# approval prompts - this is required for a cron-triggered run since nothing is there to
# click "allow". "restricted" attempts a read-only / no-side-effects mode per agent, on a
# best-effort basis (exact behavior varies by CLI and version - verify locally before relying
# on it). Safety instead comes from SAFETY_PREFIX below, which is enforced by this script and
# cannot be overridden from HEARTBEAT.md.
PERMISSION_MODE=$(read_cfg permission_mode auto)

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

case "$AGENT" in
  claude)
    ARGS=(-p --output-format json)
    [ "$MODEL" != default ] && ARGS+=(--model "$MODEL")
    if [ "$PERMISSION_MODE" = restricted ]; then ARGS+=(--permission-mode plan)
    else ARGS+=(--permission-mode bypassPermissions)
    fi
    RAW=$(cd "$PROJECT_ROOT" && claude "${ARGS[@]}" "$CHECKLIST" 2>&1); EXIT=$?
    ;;
  codex)
    ARGS=(exec --json)
    [ "$MODEL" != default ] && ARGS+=(-m "$MODEL")
    [ "$EFFORT" != default ] && ARGS+=(-c "model_reasoning_effort=$EFFORT")
    if [ "$PERMISSION_MODE" = restricted ]; then ARGS+=(--sandbox read-only)
    else ARGS+=(--full-auto --sandbox workspace-write)
    fi
    RAW=$(cd "$PROJECT_ROOT" && codex "${ARGS[@]}" "$CHECKLIST" 2>&1); EXIT=$?
    ;;
  cursor)
    ARGS=(-p --output-format json)
    [ "$MODEL" != default ] && ARGS+=(--model "$MODEL")
    if [ "$PERMISSION_MODE" = restricted ]; then ARGS+=(--sandbox enabled)
    fi
    # Note: Cursor CLI already runs non-interactively with full access under -p by default,
    # so no extra flag is needed for auto mode.
    RAW=$(cd "$PROJECT_ROOT" && agent "${ARGS[@]}" "$CHECKLIST" 2>&1); EXIT=$?
    ;;
  *)
    RAW="unknown agent: $AGENT"; EXIT=1
    ;;
esac

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

case "$EXIT" in
  0) case "$OUT" in *HEARTBEAT_OK*) STATUS=ok ;; *) STATUS=alert ;; esac ;;
  *) STATUS=error ;;
esac

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
