#!/usr/bin/env python3
import os
import subprocess
import sys

engine = os.path.join(os.path.dirname(__file__), "heartbeat_engine.py")
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..")
raise SystemExit(subprocess.call([sys.executable, engine, "validate", path, *sys.argv[2:]]))
