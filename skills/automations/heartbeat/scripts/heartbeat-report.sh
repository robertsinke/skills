#!/usr/bin/env bash
set -euo pipefail
RUNTIME_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTOMATIONS_DIR="$(cd "$RUNTIME_DIR/.." && pwd)"
exec python3 "$RUNTIME_DIR/heartbeat_engine.py" report "$AUTOMATIONS_DIR"
