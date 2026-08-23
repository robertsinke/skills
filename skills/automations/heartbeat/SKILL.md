---
name: heartbeat
description: "Set up and manage scheduled local project automations: create or edit recurring tasks, choose locally installed agent/model/effort settings, validate schedules, pause or resume execution, and review run history. Local-only; requires the computer to be awake and the chosen agent CLI to be usable."
---

# Heartbeat

Heartbeat is a local dispatcher for recurring project tasks. Cron wakes one
deterministic runner every five minutes; each automation file decides whether
its own task is due. The runner invokes the selected agent once per due task,
stores history in local SQLite, and regenerates the user-facing views.

Use the bundled `heartbeat` CLI for mechanical operations. If it is not on
PATH, run `bash ~/.claude/skills/heartbeat/scripts/heartbeat ...`.
Full commands: [reference/CLI.md](reference/CLI.md).

## Files and ownership

```text
automations/
├── <name>.md             user-owned automation files
├── DASHBOARD.md          generated status, validation, and next runs
├── AGENT-OPTIONS.md      generated agents, models, and effort on this computer
├── RUNS.md               generated run history
├── CONTEXT.md            folder contract
├── .ok/templates/automation.md (or .templates/automation.md)
└── _heartbeat/           versioned runtime + ignored local state
```

`DASHBOARD.md`, `AGENT-OPTIONS.md`, and `RUNS.md` are generated and local.
Automation files are the only task configuration source. Never hand-edit the
SQLite database or generated files.

## Automation schema

One Markdown file is one independently scheduled task. Frontmatter is a
strict, flat YAML subset; unknown properties are errors so misspellings never
fall back silently. The Markdown body is the task prompt.

```markdown
---
title: Daily briefing
type: automation
name: daily-briefing
enabled: true
schedule: "daily at 07:30"
timezone: Europe/Oslo
missed_run: catch-up
max_lateness: 4h
agent: codex
model: default
effort: high
permission_mode: auto
timeout: 10m
---

# Prompt

Prepare today's briefing. Report findings without changing files.
```

Properties:

- `title`, `name`, `enabled`, `schedule`, `agent`, `model`, and `effort` are required.
- `type` must be `automation`; filename must equal `<name>.md`.
- Schedule accepts `every 30m`, `every 6h`, `every 7d`, `daily at HH:MM`, or
  `weekly on mon at HH:MM` (three-letter weekday).
- `timezone` defaults to `local`; use an IANA name for explicit behavior.
- `missed_run` is `catch-up` or `skip`; `max_lateness` defaults to `4h`.
- `agent` is `auto`, `claude`, `codex`, `cursor`, `opencode`, or `custom`.
- `model: default` is always accepted for an installed agent. Discovered model
  lists are authoritative; agents without model discovery produce an
  unverified value rather than a false claim.
- `effort` is validated per agent. Unsupported values are errors, not ignored.
- `permission_mode` is `auto` or `restricted`; restricted is best-effort and
  agent-dependent, not a universal security boundary.
- `timeout`, `max_lateness`: integer plus `m`, `h`, or `d`.

An invalid automation never runs and does not block valid siblings. Its exact
file/property errors appear in `DASHBOARD.md` and `heartbeat validate` output.

## Local agent options

`heartbeat capabilities refresh` scans installed built-in agent CLIs without
using a model, checks authentication where the CLI exposes a deterministic
status command, writes `_heartbeat/capabilities.json`, and generates
`AGENT-OPTIONS.md`. It refreshes during init, before validation when needed,
and at most daily during dispatcher runs.

The scanner distinguishes verified model lists from unavailable discovery.
Cursor and OpenCode currently expose model-list commands; Claude and Codex may
accept model IDs without exposing an account-complete list. Harness absence,
known logged-out state, and verified-invalid models are fatal validation
errors. Unverifiable models
remain explicitly unverified and can still fail loudly at runtime.

## Scheduling and missed runs

The cron entry is only a dispatcher cadence. Task schedules live in automation
frontmatter. SQLite records `task`, `task_file`, and `scheduled_for`, so due
decisions never depend on agent judgment.

If the computer is asleep or off, cron does not run. On the next dispatcher
tick, `catch-up` runs the latest missed occurrence once when it remains within
`max_lateness`; `skip` records it as missed after the normal dispatch grace.
Missed interval occurrences coalesce rather than replaying a backlog.

## Safety invariants

- Every prompt receives a fixed safety prefix before the user-authored body.
  Task files are data and cannot replace that prefix.
- Notify/report is the default. Destructive commands, secret access, software
  installation, and system configuration changes are prohibited by the prefix.
- `permission_mode: auto` removes interactive approval stalls. Codex and Claude
  add their available sandbox controls; Cursor, OpenCode, and custom commands
  do not provide an equivalent verified boundary.
- Workspace files remain reachable to an unattended agent. Enable only trusted
  projects and prompts.
- Custom agents keep `agent_command` in ignored `_heartbeat/.heartbeat.json`,
  never in task frontmatter. That command is an explicit local trust boundary.
- One invalid task is isolated; one runner lock prevents overlapping dispatchers.
- Agent timeout, non-zero exit, configuration failure, alert, success, and
  missed occurrences are recorded per task.

## Lifecycle

```sh
heartbeat automations create       # init + register + schedule enable
heartbeat automations add <name>   # stamp one automation
heartbeat automations edit <name>  # edit, then validate
heartbeat automations show         # dashboard + registration/schedule state
heartbeat automations pause        # disable cron
heartbeat automations resume       # enable cron
heartbeat runs list                # per-task history
```

`heartbeat init` migrates the previous `HEARTBEAT.md` table into one file per
row, preserves `.heartbeat.db`, and archives the old checklist under ignored
`_heartbeat/legacy-HEARTBEAT.md`. Run `register` afterward to refresh AGENTS.md
and `schedule enable` to refresh the cron path.
