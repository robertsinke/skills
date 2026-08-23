#!/usr/bin/env bash
# unregister.sh - remove the current (or --project) project from the global
# registry so it stops showing up in `heartbeat automations list`.
# Does not touch AGENTS.md or any files under automations/ - those
# are handled by `heartbeat init` (create) and `--purge` (delete).
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
REGISTRY="$HOME/.agents/heartbeat/registry.txt"

if [ ! -f "$REGISTRY" ]; then
  echo "no registry at $REGISTRY - nothing to do"
  exit 0
fi

TMP=$(mktemp)
grep -vxF "$PROJECT_DIR" "$REGISTRY" > "$TMP" 2>/dev/null || true
mv "$TMP" "$REGISTRY"
echo "unregistered $PROJECT_DIR ($REGISTRY)"
