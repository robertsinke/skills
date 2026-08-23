# skills

Personal agent skills, installed from a single repo into every agent harness that
reads `~/.claude/skills` or `~/.agents/skills`.

## Install

```sh
git clone https://github.com/robertsinke/skills.git ~/.local/share/robert-skills
~/.local/share/robert-skills/scripts/link-skills.sh
```

`git pull` in that clone keeps every installed skill up to date - each one is a symlink
into this repo, not a copy. The install script also symlinks the `heartbeat` CLI onto
PATH via `~/.agents/bin` (add that to your PATH if the script tells you to).

## Skills

### heartbeat (`skills/automations/heartbeat`)

Scheduled, filesystem-only local automations for a project - works with whichever
coding agent CLI (Claude Code, Codex, Cursor) is configured there. No server, no
external dependencies beyond `sh`, `sqlite3`, `python3`, and `git` (all present by
default on macOS / most Linux dev machines).

Set up in a project:

```sh
cd /path/to/any/project
heartbeat automations create
```

This creates `automations/heartbeat/` in that project (`HEARTBEAT.md` checklist,
`.heartbeat.db` history, auto-generated `RUNS.md`), registers a cron entry, points
the project's `AGENTS.md` at it, and registers it in `~/.agents/heartbeat/registry.txt`.

CLI commands:

```sh
heartbeat automations create                        # scaffold + register this project
heartbeat automations list                          # every registered project + its last run
heartbeat automations show [--project <path>]        # one project: registration, cron state, checklist, last run
heartbeat automations edit                           # open $EDITOR on this project's HEARTBEAT.md
heartbeat automations pause / resume                  # toggle this project's cron entry
heartbeat automations delete [--purge] [--project <path>]  # unregister + stop cron (add --purge to also delete files)
heartbeat runs list [--project <path>]                 # recent runs as a markdown table
heartbeat runs show <id>                               # full row for one run
heartbeat runs annotate <id> "<note>"                  # sanctioned way to edit run history
```

See `skills/automations/heartbeat/SKILL.md` for full details.




































