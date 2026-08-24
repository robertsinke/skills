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
├── tasks/
│   ├── <name>.md                    user-owned automation files
│   ├── .execution-reports/<name>.md task's own run history, written by the agent itself
│   └── .ok/templates/automation.md (or .templates/automation.md)
├── INDEX.md              generated status, validation, next run, and last-run outcome
├── CONTEXT.md            folder contract
└── _heartbeat/
    ├── AGENT-OPTIONS.md  generated local agents, models, and effort
    └── ...               versioned runtime + ignored local state
```

`INDEX.md` and `_heartbeat/AGENT-OPTIONS.md` are generated and local. Files
under `tasks/` are the only task configuration source. Never hand-edit the
SQLite database or generated files. `tasks/.execution-reports/<name>.md` is
the exception to "generated" — the agent appends to it as part of running the
task, and it's real accumulated content, not a build artifact; it's tracked
in git.

## Automation schema

One Markdown file is one independently scheduled task. Frontmatter is reserved
for the thin, vault-wide navigational fields every content type in an
ICM-style workspace uses (`title`, `type`) — not engine config, so automation
files stay filterable/navigable the same way as everything else. Everything
the dispatcher itself needs lives in a `# Configuration` section in the body,
as flat `key: value` lines (same strict, unknown-properties-are-errors parsing
as frontmatter, just relocated). The `# Prompt` section is the task prompt.

```markdown
---
title: Daily briefing
type: automation
---

# Configuration

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

# Prompt

Prepare today's briefing. Report findings without changing files.
```

Properties (frontmatter or Configuration — both merge into one property set;
duplicates across the two are an error):

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
  agent-dependent, not a universal security boundary. Restricted tasks can't
  write their execution report either (see Safety invariants) — their run
  history falls back to a terse inline note in `INDEX.md` instead of a link.
- `timeout`, `max_lateness`: integer plus `m`, `h`, or `d`.

An invalid automation never runs and does not block valid siblings. Its exact
file/property errors appear in `INDEX.md` and `heartbeat validate` output.

## Local agent options

`heartbeat capabilities refresh` scans installed built-in agent CLIs without
using a model, checks authentication where the CLI exposes a deterministic
status command, writes `_heartbeat/capabilities.json`, and generates
`_heartbeat/AGENT-OPTIONS.md`. It refreshes during init, before validation when needed,
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
- For non-restricted tasks, the prefix also instructs the agent to append its
  findings to its own `tasks/.execution-reports/<name>.md` before finishing.
  This is the source of truth for what happened — the dispatcher only reads
  stdout for the terse ok/alert signal (did it reply `HEARTBEAT_OK`), never to
  extract content, so a change in an agent's streaming output format can't
  silently corrupt run history the way parsing full replies would.
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
heartbeat automations show         # index + registration/schedule state
heartbeat automations pause        # disable cron
heartbeat automations resume       # enable cron
heartbeat runs list                # per-task history
```

`heartbeat init` migrates both the previous `HEARTBEAT.md` table and flat
`automations/<name>.md` task files into `automations/tasks/`, preserves
`.heartbeat.db`, and archives the old checklist under ignored
`_heartbeat/legacy-HEARTBEAT.md`. Run `register` afterward to refresh AGENTS.md.
