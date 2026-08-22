---
name: heartbeat
description: "Set up and manage scheduled local automations (checks that run on a timer) for the current project - filesystem-only, works with Claude Code, Codex, or Cursor. Use when the user asks to add a recurring/periodic check, review past automation runs, or edit what a project checks automatically."
---

# Heartbeat

Scheduled, filesystem-only checks for a project. No server, no database beyond a
local SQLite file, works with whichever coding agent CLI is configured in the
target project.

Scripts referenced below live alongside this file, under `scripts/` and `templates/`.

## First-time setup in a project

From inside the target project, run the init script from wherever this skill
was installed, e.g.:

```
~/.claude/skills/heartbeat/scripts/init.sh
```

This creates `automations/heartbeat/` in the current project (HEARTBEAT.md,
.heartbeat.db), registers a cron entry, and appends an "## Automation" pointer
to the project's AGENTS.md (skipped if already present).

## Files this manages, inside `automations/heartbeat/`

- `HEARTBEAT.md` - the checklist. Edit directly when asked to add/change a
  check. Multiple checks can live in one file (see the `tasks:` block format
  in templates/HEARTBEAT.md.template) - don't create a new file per check.
- `RUNS.md` - auto-generated run history. Never hand-edit; regenerated after
  every run by `heartbeat-report.sh`.
- `.heartbeat.db` - SQLite backing store. Only `heartbeat-run.sh` writes to it.
- `.heartbeat.json` - optional overrides:
  `{"agent": "claude|codex|cursor", "model": "...", "effort": "..."}`.

## Reviewing history

Read `automations/heartbeat/RUNS.md`. Don't query `.heartbeat.db` directly
unless asked for something not already surfaced there.

## Hard rules (do not override from HEARTBEAT.md)

- Notify-only by default: never enable auto-commit or destructive shell
  commands from within a heartbeat run.
- Never remove the notify-only default without the user explicitly asking.


































