#!/usr/bin/env python3
"""Validate HEARTBEAT.md against the heartbeat schema.

Schema (deliberately small, not general YAML):
  A `tasks:` line introduces a list. Each task is a `  - name: ...` block
  with at least `name:` and `prompt:` fields (`interval:` is recommended,
  warned about if missing, but not fatal). `name` must be kebab-case
  (lowercase letters, digits, single hyphens - checked, not just a naming
  convention) and unique. An optional top-level `enabled: false` disables
  every task without touching cron or files.

This exists so a malformed or empty HEARTBEAT.md can never silently become
the agent prompt for an unattended run - see SKILL.md, Safety invariants.
It is intentionally a hand-rolled parser for this one schema, not a real
YAML parser: the schema is small and fixed on purpose, so a checklist can
never smuggle in config directives the runner does not already know about.

Usage: validate-heartbeat.py <path>
  exit 0, prints "valid: N task(s)" (plus any warning: lines) if OK.
  exit 1, prints one "error: ..." line per fatal problem if not.
"""
import re
import sys

KEBAB_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def parse_tasks(lines, start):
    tasks = []
    current = None
    for line in lines[start + 1:]:
        if not line.strip():
            continue
        m_name = re.match(r"^\s*-\s+name:\s*(.+)$", line)
        if m_name:
            if current is not None:
                tasks.append(current)
            current = {"name": m_name.group(1).strip().strip("\"'")}
            continue
        m_field = re.match(r"^\s+(\w+):\s*(.*)$", line)
        if m_field and current is not None:
            key, val = m_field.group(1), m_field.group(2).strip().strip("\"'")
            current[key] = val
            continue
        # a non-indented, non-task-field line ends the tasks: block
        break
    if current is not None:
        tasks.append(current)
    return tasks


def main():
    if len(sys.argv) != 2:
        print("error: usage: validate-heartbeat.py <path>")
        sys.exit(1)

    path = sys.argv[1]
    try:
        with open(path) as f:
            lines = f.read().splitlines()
    except OSError as e:
        print(f"error: cannot read {path}: {e}")
        sys.exit(1)

    if not any(l.strip() for l in lines):
        print("error: file is empty")
        sys.exit(1)

    tasks_idx = next((i for i, l in enumerate(lines) if l.strip() == "tasks:"), None)
    if tasks_idx is None:
        print("error: no top-level 'tasks:' block found")
        sys.exit(1)

    tasks = parse_tasks(lines, tasks_idx)

    fatal = []
    warnings = []
    if not tasks:
        fatal.append("'tasks:' block has no entries")

    seen_names = set()
    for i, t in enumerate(tasks):
        label = t.get("name") or f"task #{i + 1}"
        if not t.get("name"):
            fatal.append(f"{label}: missing required 'name'")
        elif t["name"] in seen_names:
            fatal.append(f"duplicate task name: {t['name']}")
        elif not KEBAB_RE.match(t["name"]):
            fatal.append(
                f"{label}: name must be kebab-case (lowercase letters, digits, "
                f"single hyphens, no leading/trailing hyphen): got '{t['name']}'"
            )
        else:
            seen_names.add(t["name"])
        if not t.get("prompt"):
            fatal.append(f"{label}: missing required 'prompt'")
        if not t.get("interval"):
            warnings.append(f"{label}: no 'interval' hint set (not fatal)")

    for w in warnings:
        print(f"warning: {w}")

    if fatal:
        for e in fatal:
            print(f"error: {e}")
        sys.exit(1)

    print(f"valid: {len(tasks)} task(s)")
    sys.exit(0)


if __name__ == "__main__":
    main()
