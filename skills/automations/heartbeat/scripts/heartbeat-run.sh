#!/usr/bin/env bash
# heartbeat-run.sh
# Expected to run with cwd = automations/heartbeat/ inside the target project.
set -uo pipefail

[ -f HEARTBEAT.md ] || exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd ../.. && pwd))"

AGENT=$(python3 -c "
import json
try:
    print(json.load(open('.heartbeat.json')).get('agent','auto'))
except Exception:
    print('auto')" 2>/dev/null || echo auto)

if [ "$AGENT" = "auto" ]; then
  if   [ -d "$PROJECT_ROOT/.claude" ]; then AGENT=claude
  elif [ -d "$PROJECT_ROOT/.codex" ] || [ -f "$PROJECT_ROOT/AGENTS.md" ]; then AGENT=codex
  elif [ -d "$PROJECT_ROOT/.cursor" ]; then AGENT=cursor
  else AGENT=claude
  fi
fi

MODEL=$(python3 -c "
import json
try:
    print(json.load(open('.heartbeat.json')).get('model','default'))
except Exception:
    print('default')" 2>/dev/null || echo default)

EFFORT=$(python3 -c "
import json
try:
    print(json.load(open('.heartbeat.json')).get('effort','default'))
except Exception:
    print('default')" 2>/dev/null || echo default)

CHECKLIST="$(cat HEARTBEAT.md)"
BEFORE=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo none)
START=$(date +%s%3N)

case "$AGENT" in
  claude)
    ARGS=(-p --output-format json)
    [ "$MODEL" != default ] && ARGS+=(--model "$MODEL")
    RAW=$(cd "$PROJECT_ROOT" && claude "${ARGS[@]}" "$CHECKLIST" 2>&1); EXIT=$?
    ;;
  codex)
    ARGS=(exec --json)
    [ "$MODEL" != default ] && ARGS+=(-m "$MODEL")
    [ "$EFFORT" != default ] && ARGS+=(-c "model_reasoning_effort=$EFFORT")
    RAW=$(cd "$PROJECT_ROOT" && codex "${ARGS[@]}" "$CHECKLIST" 2>&1); EXIT=$?
    ;;
  cursor)
    ARGS=(-p --output-format json)
    [ "$MODEL" != default ] && ARGS+=(--model "$MODEL")
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
json.dump({'text': text, 'usage': usage}, open('.heartbeat_last.json','w'))" "$RAW" "$AGENT"

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
  (ts, date, time, agent, model, effort, status, exit_code, duration_ms, input_tokens, output_tokens, cost_usd, output, git_before, git_after, dirty_files)
  VALUES ('$(date -u +%FT%TZ)', '$(date -u +%F)', '$(date -u +%T)', '$AGENT', '$MODEL', '$EFFORT', '$STATUS', $EXIT, $DURATION,
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




































































































