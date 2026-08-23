# Heartbeat CLI

## Setup primitives

```sh
heartbeat init                 # files only; migrates legacy HEARTBEAT.md
heartbeat register             # registry + AGENTS.md pointer
heartbeat unregister           # registry only
heartbeat schedule enable      # install/refresh five-minute dispatcher cron
heartbeat schedule disable     # comment out dispatcher cron
```

`heartbeat automations create` composes init, register, and schedule enable.

## Automations

```sh
heartbeat automations add <name>
heartbeat automations edit <name>
heartbeat automations list
heartbeat automations show [--project <path>]
heartbeat automations pause
heartbeat automations resume
heartbeat automations delete [--purge] [--project <path>]
```

`add` stamps `automations/tasks/<name>.md` from the local automation template.
`show` refreshes and prints `DASHBOARD.md`. Default deletion keeps task files
and history; `--purge` removes heartbeat runtime and generated views, but keeps
user-authored automation files.

## Local agent options

```sh
heartbeat capabilities refresh
heartbeat capabilities show
```

Refresh deterministically scans installed agent CLIs, writes ignored
`_heartbeat/capabilities.json`, and regenerates ignored
`_heartbeat/AGENT-OPTIONS.md`.

## Runs

```sh
heartbeat runs list [--project <path>]
heartbeat runs show <id>
heartbeat runs annotate <id> "<note>"
```

Run history is task-qualified. Prefer these commands or generated `RUNS.md`
over querying `_heartbeat/.heartbeat.db` directly.
