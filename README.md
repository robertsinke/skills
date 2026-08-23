# skills

Personal agent skills, installed from a single repo into every agent harness that
reads `~/.claude/skills` or `~/.agents/skills`.

## Install

```sh
git clone https://github.com/robertsinke/skills.git ~/.local/share/robert-skills
~/.local/share/robert-skills/scripts/link-skills.sh
```

`git pull` in that clone keeps every installed skill up to date - each one is a symlink
into this repo, not a copy. The install script also symlinks each skill's CLI (`heartbeat`, `talk-to-me`) onto
PATH via `~/.agents/bin` (add that to your PATH if the script tells you to).

## Skills

### heartbeat (`skills/automations/heartbeat`)

Scheduled, local automations for a project - works with any coding agent CLI
that has a scriptable non-interactive mode, not just Claude Code, Codex, and
Cursor: those three plus OpenCode are built-in presets, and anything else
(pi, a future tool) plugs in via agent_command in .heartbeat.json. Not
literally filesystem-only: uses a local SQLite file for run history, cron for
scheduling, and a small global registry file for cross-project discovery. No
server, no cloud service, no account - no external dependencies beyond sh,
sqlite3, python3, and git (all present by default on macOS / most Linux dev
machines).

Set up in a project (init + register + schedule enable, composed):

```sh
cd /path/to/any/project
heartbeat automations create
```

This creates automations/heartbeat/ in that project (HEARTBEAT.md checklist,
validated against a small schema before every run, plus .heartbeat.db
history and auto-generated RUNS.md), registers a cron entry, points the
project AGENTS.md at it, and registers it in
~/.agents/heartbeat/registry.txt. Each of those three steps (init, register,
schedule enable) is also independently callable.

CLI commands (full reference: `skills/automations/heartbeat/reference/CLI.md`):

```sh
heartbeat init / register / unregister / schedule <enable|disable>   # primitives
heartbeat automations create / list / show / edit / pause / resume / delete
heartbeat runs list / show <id> / annotate <id> "note"
```

Runs are unattended, so heartbeat-run.sh enforces a fixed safety prefix (no
destructive commands, no unscoped git commits, no reading secrets) that
cannot be overridden from HEARTBEAT.md, takes a lock so a slow run is never
duplicated by the next cron tick, and runs the agent CLI under a portable
timeout (no external timeout binary assumed) so a hung agent cannot wedge
the schedule forever. See `skills/automations/heartbeat/SKILL.md` for the full safety model and failure
handling.

### talk-to-me (`skills/voice/talk-to-me`)

Local, open-source voice I/O for an agent session - speak to the user and listen
for their spoken reply. Text-to-speech via [Piper](https://github.com/OHF-Voice/piper1-gpl)
(GPL-3.0), speech-to-text via [Vosk](https://alphacephei.com/vosk) (Apache-2.0).
No account, no API key, no cloud call, no browser dependency - both engines run
fully offline on the user's machine, installed into an isolated venv that never
touches system/global Python.

One-time setup (creates the venv, installs the 4 pip packages it needs, downloads
a small default voice/model, ~100MB total):

```sh
talk-to-me setup
talk-to-me status   # verify
```

Then, in a session:

```sh
talk-to-me say "Here's what I found. Want me to go ahead?"
talk-to-me listen   # records the mic, auto-stops on silence, prints the transcript
```

See `skills/voice/talk-to-me/SKILL.md` for voice/model customization and usage notes.
