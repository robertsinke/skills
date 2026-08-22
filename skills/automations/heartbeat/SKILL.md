---
name: heartbeat
description: "Set up and manage scheduled local automations (checks that run on a timer) for the current project - filesystem-only, works with Claude Code, Codex, or Cursor. Use when the user asks to add a recurring/periodic check, review past automation runs, or edit what a project checks automatically."
---

# Heartbeat

Scheduled, filesystem-only checks for a project. No server, no database beyond a
local SQLite file, works with whichever coding agent CLI is configured in the
target project.

This skill ships a CLI (`heartbeat`) for the mechanical parts. Use the CLI for
anything deterministic; only hand-edit HEARTBEAT.md or read RUNS.md yourself when
the action requires understanding what the user actually wants.

## First-time setup in a project

From inside the target project:

```
heartbeat automations create
```

This creates `automations/heartbeat/` in the current project (HEARTBEAT.md,
.heartbeat.db), registers a cron entry, appends an "## Automation" pointer to
the project's AGENTS.md (skipped if already present), and registers the project
at ~/.agents/heartbeat/registry.txt so it shows up in `heartbeat automations list`.

## CLI commands

```
heartbeat automations create              # scaffold + register this project
heartbeat automations list                # every registered project + its last run
heartbeat automations edit                # open $EDITOR on this project's HEARTBEAT.md
heartbeat automations pause / resume       # toggle this project's cron entry
heartbeat runs list [--project <path>]     # recent runs as a markdown table
heartbeat runs show <id>                   # full row for one run
heartbeat runs annotate <id> "<note>"      # the only sanctioned way to edit run history
```

## Files this manages, inside `automations/heartbeat/`

- `HEARTBEAT.md` - the checklist. Edit directly (or via `heartbeat automations edit`)
  when asked to add/change a check. Multiple checks can live in one file (see the
  `tasks:` block format in templates/HEARTBEAT.md.template) - don't create a new
  file per check.
- `RUNS.md` - auto-generated run history. Never hand-edit; regenerated after every
  run by `heartbeat-report.sh`.
- `.heartbeat.db` - SQLite backing store. Only `heartbeat-run.sh` and
  `heartbeat runs annotate` write to it - never hand-edit.
- `.heartbeat.json` - optional overrides:
  `{"agent": "claude|codex|cursor", "model": "...", "effort": "..."}`.

## Reviewing history

Prefer `heartbeat runs list` or reading `automations/heartbeat/RUNS.md` over
querying `.heartbeat.db` directly.

## Hard rules (do not override from HEARTBEAT.md)

- Notify-only by default: never enable auto-commit or destructive shell commands
  from within a heartbeat run.
- Never remove the notify-only default without the user explicitly asking.
- Never hand-edit `.heartbeat.db` or `RUNS.md`; use the CLI.

















































