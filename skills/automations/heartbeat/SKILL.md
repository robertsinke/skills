---
name: heartbeat
description: "Set up and manage scheduled local automations (checks that run on a timer) for the current project - local-only (no cloud service, no account), works with any coding agent CLI that has a scriptable non-interactive mode (built-in presets for Claude Code, Codex, Cursor, and OpenCode; anything else via a generic agent_command). Use when the user asks to add a recurring/periodic check, review past automation runs, or edit what a project checks automatically."
---

# Heartbeat

Scheduled, local checks for a project. This is not literally "filesystem-only":
it uses a local SQLite file for run history, cron for scheduling, a small
global registry file for cross-project discovery, and whichever coding agent
CLI is configured in the target project. What it does not use: a server, a
cloud service or database, or an account.

Not confined to any one agent. Built-in presets exist for Claude Code, Codex,
Cursor, and OpenCode - anything else (pi, a future tool, an internal one)
plugs in via agent_command in .heartbeat.json, as long as it has some
scriptable, non-interactive, prompt-in/text-out mode. See Configuration
schema below.

This skill ships a CLI (heartbeat) for every mechanical/deterministic step.
Use the CLI for anything it covers; only hand-edit HEARTBEAT.md, or read
RUNS.md, when the action requires understanding what the user actually wants.
Full command list: reference/CLI.md. This file covers trigger/scope, the
safety model, lifecycle workflows, the config schema, and failure handling.

## If heartbeat is not on PATH

scripts/link-skills.sh symlinks the CLI to ~/.agents/bin/heartbeat and adds
that to PATH via the shell rc file, but a terminal opened before that ran
will not have it yet. If heartbeat is not found, call the bundled script
directly - it works the same either way, no PATH needed:

```
bash ~/.claude/skills/heartbeat/scripts/heartbeat automations create
```

## Trigger and scope

Use this skill when the user asks to:
- add a recurring or periodic check to the current project (a lint sweep, a
  dependency audit, a "tell me if X changes" watcher, a morning summary, etc.)
- review what a project is already checking, or its run history
- change, pause, resume, or remove an existing scheduled check

This is not the right tool for: a one-off task (just do it), a job that needs
sub-minute latency (cron granularity is minutes, and the default schedule is
every 30 minutes), or a long-running interactive process (a heartbeat run is
a single bounded agent CLI invocation, not a persistent service).

Only set this up for trusted projects and trusted checklists. permission_mode:
auto (the default, required for unattended runs) removes the agent CLI's own
approval gate - see Safety invariants below - so a heartbeat run can take any
action the agent decides to take, limited only by the agent following the
safety prefix, not by anything technically enforced. Do not enable it on a
project, or write a HEARTBEAT.md checklist, you would not trust to run
unattended with no one reviewing actions before they happen.

## Safety invariants

These hold regardless of what a project HEARTBEAT.md says, and must not be
weakened when editing a project automation. Read this section as: what is
actually enforced, versus what is prompt-level guidance the agent is
expected to follow but that nothing here technically forces.

- **The safety prefix is a prompt-level guardrail, not a sandboxed
  enforcement boundary.** heartbeat-run.sh prepends a fixed instruction
  block to every prompt, before the HEARTBEAT.md content, and it cannot be
  edited or removed via HEARTBEAT.md - that part is a real, non-negotiable
  guarantee, because HEARTBEAT.md is data (what to check), never policy
  (what is allowed). What it is NOT is a technical restriction on what the
  agent can execute: it only works if the agent reads and follows it. If an
  agent ignores, misreads, or is prompt-injected around the prefix, nothing
  here stops it from running a destructive command.
- **permission_mode "auto" (default) removes the agent CLI's own approval
  gate entirely** (Claude bypassPermissions, Codex --full-auto, etc.) so a
  cron-triggered run does not stall waiting for a human who is not there.
  This means in auto mode there is no technical barrier between the agent
  and any action at all, beyond the model choosing to follow the safety
  prefix above. Real enforcement - OS-level sandboxing, restricted file/
  process permissions, or a runner that inspects and refuses specific
  commands - is not implemented by this skill today. Treat the safety
  prefix as reducing risk, not eliminating it.
- **permission_mode "restricted" is advisory only, not a verified security
  boundary either.** It asks each agent CLI for a read-only-ish mode on a
  best-effort basis (Claude plan mode, Codex --sandbox read-only, Cursor
  --sandbox enabled, OpenCode currently just omits --auto - unverified), but
  exact behavior is CLI- and version-dependent and is not something this
  skill verifies or enforces.
- **agent_command is a trust boundary the user opens explicitly, not an
  integration this skill verifies.** Setting it means heartbeat execs that
  exact command from cron, unattended, with the checklist as its input.
  permission_mode has no effect on it, none of the built-in presets' flags
  apply, and heartbeat cannot inspect or restrict what that command does.
  Only point it at something already trusted to run non-interactively and
  unattended on this machine.
- **Notify-only by default.** Never enable auto-commit or destructive shell
  commands from within a heartbeat run without the user explicitly asking -
  this is a checklist-authoring convention layered on top of the guardrails
  above, not a substitute for them.
- **HEARTBEAT.md must pass validation before it is ever used as a prompt.**
  A malformed or empty checklist is data that failed to parse, not an
  instruction to interpret creatively - the run is skipped and logged as
  status=invalid instead of being sent to the agent. See Configuration
  schema below.
- **Deletion never removes history by default.** heartbeat automations
  delete only unregisters and disables the schedule; --purge is required to
  delete HEARTBEAT.md, RUNS.md, or .heartbeat.db, and only when the user
  explicitly wants that.
- Never hand-edit .heartbeat.db or RUNS.md; both are generated. The only
  sanctioned way to annotate history is heartbeat runs annotate <id> "<note>".

## Lifecycle workflows

First-time setup, from inside the target project, is three independent
steps composed into one command:

```
heartbeat automations create
```

which runs, in order:

1. **init** - scaffold automations/heartbeat/ (HEARTBEAT.md from the
   template, .heartbeat.db, and copies of heartbeat-run.sh,
   heartbeat-report.sh, validate-heartbeat.py). Files only - nothing is
   scheduled or discoverable yet.
2. **register** - add the project to ~/.agents/heartbeat/registry.txt (so
   heartbeat automations list finds it) and append an "## Automation"
   pointer to the project AGENTS.md.
3. **schedule enable** - add the cron entry.

Each step is independently callable (heartbeat init, heartbeat register,
heartbeat schedule enable) and testable on its own - useful if only part of
the setup needs to be redone, or to understand exactly which side effect
caused what. See reference/CLI.md for every command.

Everyday workflows:
- **Add or change a check**: edit HEARTBEAT.md directly, or
  heartbeat automations edit. Multiple checks live in one file under one
  tasks: block - do not create a new file per check.
- **Review**: heartbeat automations list (all projects),
  heartbeat automations show (one project - registration, schedule state,
  lock state, validation result, checklist, last run), or
  heartbeat runs list / RUNS.md (history for one project).
- **Pause/resume**: heartbeat automations pause / resume (aliases for
  heartbeat schedule disable / enable) - a **schedule disable**: cron itself
  stops firing, as opposed to enabled: false in HEARTBEAT.md, which is a
  logical disable (cron still fires, the run just no-ops). See Configuration
  schema below for that distinction.
- **Remove**: heartbeat automations delete [--purge].

## Configuration schema

HEARTBEAT.md is user-authored configuration first, agent prompt content
second - and validate-heartbeat.py enforces a boundary between the two so a
checklist can only ever describe what to check, never grant itself
permissions or override the runner. The schema (deliberately small, not
general YAML):

```
tasks:                     # required, at least one entry
  - name: example-check     # required, unique, short kebab-case id
    interval: 30m            # recommended: a hint the agent uses to judge
                              # whether this task is due. Cron itself fires
                              # on ONE fixed schedule for the whole file
                              # (every 30 minutes by default) - there is no
                              # per-task cron entry.
    prompt: "..."             # required, plain text. Data, not policy.
```

Optional top-level enabled: false is a **logical disable**: the checklist
itself says not to run, while cron keeps firing on schedule and immediately
no-ops (heartbeat-run.sh exits before validation, no DB row, no agent call).
Nothing about the registry, cron entry, or any files changes.

Validation runs before every scheduled run (and on demand via
heartbeat automations show or heartbeat automations edit). A file is
invalid if: tasks: is missing, the list is empty, any task is missing name
or prompt, or two tasks share a name. A missing interval is a warning, not
a fatal error.

.heartbeat.json (optional, same directory) overrides runtime behavior, not
the checklist itself:

```
{
  "agent": "claude|codex|cursor|opencode|auto",
  "agent_command": "opencode run --auto",
  "agent_input": "arg|stdin",
  "model": "...",
  "effort": "...",
  "permission_mode": "auto|restricted",
  "timeout_seconds": 600
}
```

There are four built-in agent presets (claude, codex, cursor, opencode), plus
auto (default - detected from marker files/dirs in the project). Setting
agent_command switches to a generic path that works with ANY coding agent CLI
that has a scriptable non-interactive mode: the checklist (with the safety
prefix already prepended) is passed to agent_command as its final argument by
default, or piped via stdin if agent_input is "stdin". agent_command takes
priority over the agent presets - agent then becomes just a label for
logging. There is no built-in usage/cost parsing for agent_command or
opencode today (only claude and codex give structured token/cost data back);
output and status (ok/alert/error, via exit code and the HEARTBEAT_OK
sentinel) still work the same for every agent.

## Failure and recovery rules

- **Duplicate execution**: heartbeat-run.sh takes a lock (a .heartbeat.lock/
  directory, created with mkdir for an atomic, dependency-free lock) before
  doing anything else. If cron fires while a previous run is still going,
  the new run logs status=skipped and exits immediately rather than running
  concurrently. If the lock owner process is no longer alive (a crashed or
  killed prior run), the lock is treated as stale and reclaimed.
- **Agent timeout**: the agent CLI is given timeout_seconds (default 600)
  to finish. No timeout/gtimeout binary is assumed present - macOS ships
  neither by default - so this is implemented with a portable poll-and-kill
  loop in heartbeat-run.sh. On timeout the run is logged as status=timeout
  with whatever partial output existed; killing the process tree is
  best-effort, not guaranteed for every agent CLI/OS combination.
- **Malformed HEARTBEAT.md**: caught by validate-heartbeat.py before any
  agent is invoked. Logged as status=invalid with the specific parse
  error(s); the checklist is never sent to the agent in this state.
- **Missed cron runs**: if the machine is asleep or off at the scheduled
  time, that run simply does not happen - there is no catch-up/backfill
  mechanism. This is an accepted limitation, not a bug: a catch-up run
  would have to guess how much of the missed interval is still relevant.
- **Partial run state**: every code path that actually evaluates a
  checklist (skipped, invalid, timeout, error, alert, ok) writes exactly one
  row to .heartbeat.db, so RUNS.md reflects everything that was attempted.
  Two states are intentionally silent and write no row: HEARTBEAT.md missing
  entirely, and enabled: false (the logical disable from Configuration
  schema) - both mean "nothing was configured to run" rather than a run
  outcome, so RUNS.md is not spammed every cron tick while intentionally
  idle.
- **Recovering from a stuck lock**: heartbeat automations show reports lock
  state (held vs. stale) for a project. A held lock with a dead PID means
  the next scheduled run will reclaim it automatically; nothing manual is
  needed. Only intervene by hand (rm -rf automations/heartbeat/.heartbeat.lock)
  if a genuinely stuck process needs to be cleared before the next cron tick.

## CLI reference

Full command list, flags, and examples: reference/CLI.md.
