# skills

Personal agent skills, installed from a single repo into every agent harness that
reads `~/.claude/skills` or `~/.agents/skills`.

## Install

```sh
git clone https://github.com/robertsinke/skills.git ~/.local/share/robert-skills
~/.local/share/robert-skills/scripts/link-skills.sh
```

`git pull` in that clone keeps every installed skill up to date - each one is a symlink
into this repo, not a copy.

## Skills

### heartbeat (`skills/automations/heartbeat`)

Scheduled, filesystem-only local automations for a project - works with whichever
coding agent CLI (Claude Code, Codex, Cursor) is configured there. No server, no
external dependencies beyond `sh`, `sqlite3`, `python3`, and `git` (all present by
default on macOS / most Linux dev machines).

Set up in a project:

```sh
cd /path/to/any/project
~/.claude/skills/heartbeat/scripts/init.sh
```

This creates `automations/heartbeat/` in that project (`HEARTBEAT.md` checklist,
`.heartbeat.db` history, auto-generated `RUNS.md`), registers a cron entry, and points
the project's `AGENTS.md` at it so any agent working there is aware of it.

See `skills/automations/heartbeat/SKILL.md` for full details.

























