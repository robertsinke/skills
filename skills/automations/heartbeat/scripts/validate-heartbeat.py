#!/usr/bin/env python3
"""Validate HEARTBEAT.md against the heartbeat checklist schema.

The canonical format is a Markdown table with exactly three columns:
Task, Interval, and Prompt. The previous ``tasks:`` block remains supported
so existing installations continue to run, but a file containing both formats
is invalid because two task sources can drift apart.

Optional YAML frontmatter may contain ``enabled: false`` to logically disable
the checklist without touching cron or files. Frontmatter is deliberately not
parsed as general YAML; heartbeat only validates the root ``enabled`` value.

Usage: validate-heartbeat.py <path>
  exit 0, prints "valid: N task(s)" (plus warning lines) if OK.
  exit 1, prints one "error: ..." line per fatal problem if not.
"""

import re
import sys


KEBAB_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TABLE_HEADERS = ("task", "interval", "prompt")


def clean_inline(value):
    """Remove optional code formatting around a complete table cell."""
    value = value.strip()
    if len(value) >= 2 and value.startswith("`") and value.endswith("`"):
        value = value[1:-1].strip()
    return value


def split_table_row(line):
    """Split a Markdown table row while preserving escaped pipes in cells."""
    row = line.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|") and not row.endswith(r"\|"):
        row = row[:-1]

    cells = []
    current = []
    index = 0
    while index < len(row):
        char = row[index]
        if char == "\\" and index + 1 < len(row) and row[index + 1] == "|":
            current.append("|")
            index += 2
            continue
        if char == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(char)
        index += 1
    cells.append("".join(current).strip())
    return cells


def is_separator_row(cells):
    return len(cells) == 3 and all(
        re.fullmatch(r":?-{3,}:?", cell.strip()) for cell in cells
    )


def find_table(lines):
    """Return (header index, error) for the canonical task table."""
    for index, line in enumerate(lines):
        cells = split_table_row(line)
        if tuple(cell.lower() for cell in cells) != TABLE_HEADERS:
            continue
        if index + 1 >= len(lines) or not is_separator_row(
            split_table_row(lines[index + 1])
        ):
            return index, "task table is missing a valid Markdown separator row"
        return index, None
    return None, None


def parse_table(lines, start):
    tasks = []
    errors = []
    for line_number, line in enumerate(lines[start + 2 :], start=start + 3):
        if not line.strip():
            if tasks:
                break
            continue
        if "|" not in line:
            break
        cells = split_table_row(line)
        if len(cells) != 3:
            errors.append(
                f"task table row {line_number} must have exactly 3 columns; "
                f"found {len(cells)}"
            )
            continue
        tasks.append(
            {
                "name": clean_inline(cells[0]),
                "interval": clean_inline(cells[1]),
                "prompt": clean_inline(cells[2]),
            }
        )
    return tasks, errors


def parse_legacy_tasks(lines, start):
    tasks = []
    current = None
    for line in lines[start + 1 :]:
        if not line.strip():
            continue
        name_match = re.match(r"^\s*-\s+name:\s*(.+)$", line)
        if name_match:
            if current is not None:
                tasks.append(current)
            current = {"name": name_match.group(1).strip().strip("\"'")}
            continue
        field_match = re.match(r"^\s+(\w+):\s*(.*)$", line)
        if field_match and current is not None:
            key, value = field_match.group(1), field_match.group(2)
            current[key] = value.strip().strip("\"'")
            continue
        break
    if current is not None:
        tasks.append(current)
    return tasks


def validate_frontmatter(lines):
    if not lines or lines[0].strip() != "---":
        return []

    closing_index = next(
        (index for index, line in enumerate(lines[1:], start=1) if line.strip() == "---"),
        None,
    )
    if closing_index is None:
        return ["YAML frontmatter is missing its closing '---'"]

    enabled = None
    for line in lines[1:closing_index]:
        match = re.match(r"^enabled:\s*(.*?)\s*$", line)
        if match:
            enabled = match.group(1).lower()
    if enabled is not None and enabled not in {"true", "false"}:
        return ["frontmatter 'enabled' must be true or false"]
    return []


def validate_tasks(tasks):
    fatal = []
    warnings = []
    if not tasks:
        fatal.append("task list has no entries")

    seen_names = set()
    for index, task in enumerate(tasks):
        label = task.get("name") or f"task #{index + 1}"
        if not task.get("name"):
            fatal.append(f"{label}: missing required task name")
        elif task["name"] in seen_names:
            fatal.append(f"duplicate task name: {task['name']}")
        elif not KEBAB_RE.match(task["name"]):
            fatal.append(
                f"{label}: name must be kebab-case (lowercase letters, digits, "
                f"single hyphens, no leading/trailing hyphen): got '{task['name']}'"
            )
        else:
            seen_names.add(task["name"])

        if not task.get("prompt"):
            fatal.append(f"{label}: missing required prompt")
        if not task.get("interval"):
            warnings.append(f"{label}: no interval hint set (not fatal)")

    return fatal, warnings


def main():
    if len(sys.argv) != 2:
        print("error: usage: validate-heartbeat.py <path>")
        sys.exit(1)

    path = sys.argv[1]
    try:
        with open(path, encoding="utf-8") as file:
            lines = file.read().splitlines()
    except OSError as error:
        print(f"error: cannot read {path}: {error}")
        sys.exit(1)

    if not any(line.strip() for line in lines):
        print("error: file is empty")
        sys.exit(1)

    fatal = validate_frontmatter(lines)
    table_index, table_error = find_table(lines)
    legacy_index = next(
        (index for index, line in enumerate(lines) if line.strip() == "tasks:"),
        None,
    )

    if table_error:
        fatal.append(table_error)
    if table_index is not None and legacy_index is not None:
        fatal.append(
            "both a Markdown task table and legacy 'tasks:' block were found; "
            "keep one source of truth"
        )

    parse_errors = []
    if table_index is not None:
        tasks, parse_errors = parse_table(lines, table_index)
    elif legacy_index is not None:
        tasks = parse_legacy_tasks(lines, legacy_index)
    else:
        tasks = []
        fatal.append(
            "no task list found; add a '| Task | Interval | Prompt |' table"
        )

    fatal.extend(parse_errors)
    task_errors, warnings = validate_tasks(tasks)
    fatal.extend(task_errors)

    for warning in warnings:
        print(f"warning: {warning}")
    if fatal:
        for error in fatal:
            print(f"error: {error}")
        sys.exit(1)

    print(f"valid: {len(tasks)} task(s)")


if __name__ == "__main__":
    main()
