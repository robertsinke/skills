#!/usr/bin/env python3
"""Heartbeat task discovery, validation, scheduling, execution, and views."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import time
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

GENERATED = {"DASHBOARD.md", "AGENT-OPTIONS.md", "RUNS.md", "CONTEXT.md"}
FIELDS = {
    "title", "type", "name", "enabled", "schedule", "timezone",
    "missed_run", "max_lateness", "agent", "model", "effort",
    "permission_mode", "timeout",
}
REQUIRED = {"title", "type", "name", "enabled", "schedule", "agent", "model", "effort"}
AGENTS = {"auto", "claude", "codex", "cursor", "opencode", "custom"}
EFFORTS = {
    "claude": {"default", "low", "medium", "high", "xhigh", "max"},
    "codex": {"default", "minimal", "low", "medium", "high", "xhigh"},
    "cursor": {"default", "low", "medium", "high", "xhigh"},
    "opencode": {"default"}, "custom": {"default"}, "auto": {"default"},
}
COMMANDS = {"claude": "claude", "codex": "codex", "cursor": "agent", "opencode": "opencode"}
SAFETY_PREFIX = """You are running as an unattended scheduled automation, not an interactive session.
These rules override the task below:
- Report findings by default; make no destructive changes.
- Never read, print, or transmit secrets, credentials, tokens, or API keys.
- Never install software or change system/global configuration.
- Never commit or push unless the task explicitly requests that exact action.
- If an action is unsafe or ambiguous, report it instead of taking it.
Reply with exactly HEARTBEAT_OK if nothing needs attention.

Task:
"""


class ConfigError(Exception):
    pass


def scalar(raw: str):
    raw = raw.strip()
    if not raw:
        return ""
    if raw.startswith('"'):
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ConfigError(f"invalid quoted value: {exc.msg}") from exc
    if raw.startswith("'"):
        if not raw.endswith("'"):
            raise ConfigError("unterminated quoted value")
        return raw[1:-1].replace("''", "'")
    low = raw.lower()
    if low in {"true", "false"}:
        return low == "true"
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    return raw


def parse_document(path: Path) -> tuple[dict, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        raise ConfigError("missing YAML frontmatter")
    try:
        end = next(i for i, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration as exc:
        raise ConfigError("frontmatter is missing its closing ---") from exc
    data = {}
    for number, line in enumerate(lines[1:end], 2):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"([a-z][a-z0-9_]*)\s*:\s*(.*)", line)
        if not match:
            raise ConfigError(f"frontmatter line {number} must be a flat key: value property")
        key = match.group(1)
        if key in data:
            raise ConfigError(f"duplicate property: {key}")
        data[key] = scalar(match.group(2))
    return data, "\n".join(lines[end + 1 :]).strip()


def duration(value, field: str) -> int:
    match = re.fullmatch(r"(\d+)(m|h|d)", str(value or ""))
    if not match:
        raise ConfigError(f"{field} must use minutes, hours, or days, such as 10m, 4h, or 7d")
    amount, unit = int(match.group(1)), match.group(2)
    return amount * {"m": 60, "h": 3600, "d": 86400}[unit]


def parse_schedule(value: str):
    value = str(value).strip().lower()
    match = re.fullmatch(r"every\s+(\d+[mhd])", value)
    if match:
        return ("interval", duration(match.group(1), "schedule"))
    match = re.fullmatch(r"daily\s+at\s+([01]\d|2[0-3]):([0-5]\d)", value)
    if match:
        return ("daily", int(match.group(1)), int(match.group(2)))
    match = re.fullmatch(r"weekly\s+on\s+(mon|tue|wed|thu|fri|sat|sun)\s+at\s+([01]\d|2[0-3]):([0-5]\d)", value)
    if match:
        return ("weekly", ("mon", "tue", "wed", "thu", "fri", "sat", "sun").index(match.group(1)), int(match.group(2)), int(match.group(3)))
    raise ConfigError("schedule must be 'every 30m', 'daily at 07:30', or 'weekly on mon at 09:00'")


def timezone(value):
    if not value or value == "local":
        return dt.datetime.now().astimezone().tzinfo
    try:
        return ZoneInfo(str(value))
    except ZoneInfoNotFoundError as exc:
        raise ConfigError(f"unknown timezone: {value}") from exc


def capabilities_path(automations: Path) -> Path:
    return automations / "_heartbeat" / "capabilities.json"


def load_capabilities(automations: Path) -> dict:
    try:
        return json.loads(capabilities_path(automations).read_text())
    except (OSError, json.JSONDecodeError):
        return {"agents": {}}


def validate_task(path: Path, data: dict, body: str, caps: dict) -> list[str]:
    errors = []
    unknown = sorted(set(data) - FIELDS)
    if unknown:
        errors.append("unknown properties: " + ", ".join(unknown))
    missing = sorted(key for key in REQUIRED if key not in data or data[key] == "")
    if missing:
        errors.append("missing properties: " + ", ".join(missing))
    if data.get("type") != "automation":
        errors.append("type must be automation")
    name = str(data.get("name", ""))
    if name and not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
        errors.append("name must be kebab-case")
    if name and path.stem != name:
        errors.append(f"filename must be {name}.md")
    if not isinstance(data.get("enabled"), bool):
        errors.append("enabled must be true or false")
    try:
        parse_schedule(str(data.get("schedule", "")))
    except ConfigError as exc:
        errors.append(str(exc))
    try:
        timezone(data.get("timezone", "local"))
    except ConfigError as exc:
        errors.append(str(exc))
    if data.get("missed_run", "catch-up") not in {"catch-up", "skip"}:
        errors.append("missed_run must be catch-up or skip")
    for key, default in (("max_lateness", "4h"), ("timeout", "10m")):
        try:
            duration(data.get(key, default), key)
        except ConfigError as exc:
            errors.append(str(exc))
    agent = str(data.get("agent", ""))
    effort = str(data.get("effort", ""))
    if agent not in AGENTS:
        errors.append("agent must be auto, claude, codex, cursor, opencode, or custom")
    elif effort not in EFFORTS[agent]:
        errors.append(f"effort '{effort}' is unsupported by {agent}")
    if data.get("permission_mode", "auto") not in {"auto", "restricted"}:
        errors.append("permission_mode must be auto or restricted")
    if not body:
        errors.append("prompt body is empty")
    available = caps.get("agents", {})
    if agent in COMMANDS and agent in available and not available[agent].get("installed"):
        errors.append(f"agent '{agent}' is not installed on this computer")
    if agent in available and available[agent].get("auth_status") == "unauthenticated":
        errors.append(f"agent '{agent}' is installed but not authenticated")
    model = str(data.get("model", ""))
    if agent in available and model != "default" and available[agent].get("models_status") == "verified":
        if model not in available[agent].get("models", []):
            errors.append(f"model '{model}' is not available for {agent}")
    if agent == "cursor" and effort != "default" and model == "default":
        errors.append("cursor requires an explicit model when effort is not default")
    return errors


def discover(automations: Path) -> tuple[list[dict], list[dict]]:
    caps = load_capabilities(automations)
    tasks, invalid = [], []
    seen = set()
    for path in sorted(automations.glob("*.md")):
        if path.name in GENERATED:
            continue
        try:
            data, body = parse_document(path)
            errors = validate_task(path, data, body, caps)
            agent, model = str(data.get("agent", "")), str(data.get("model", ""))
            status = caps.get("agents", {}).get(agent, {}).get("models_status")
            warnings = []
            if model and model != "default" and status != "verified":
                warnings.append(f"model '{model}' cannot be verified locally for {agent}")
            if data.get("name") in seen:
                errors.append(f"duplicate name: {data.get('name')}")
            seen.add(data.get("name"))
            item = {"path": str(path), "body": body, **data}
            (invalid if errors else tasks).append({**item, "errors": errors, "warnings": warnings})
        except (OSError, ConfigError) as exc:
            invalid.append({"path": str(path), "name": path.stem, "title": path.stem, "errors": [str(exc)]})
    return tasks, invalid


def run_capture(args: list[str], timeout=8) -> tuple[int, str]:
    try:
        result = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
        return result.returncode, (result.stdout or result.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, str(exc)


def find_command(command: str, previous: str | None = None) -> str | None:
    candidates = [
        shutil.which(command),
        previous,
        *(str(path / command) for path in (
            Path.home() / ".local/bin",
            Path.home() / ".npm-global/bin",
            Path.home() / ".opencode/bin",
            Path.home() / ".agents/bin",
            Path("/opt/homebrew/bin"),
            Path("/usr/local/bin"),
        )),
    ]
    return next((candidate for candidate in candidates if candidate and os.access(candidate, os.X_OK)), None)


def scan_capabilities(automations: Path) -> dict:
    previous = load_capabilities(automations).get("agents", {})
    agents = {}
    for name, command in COMMANDS.items():
        path = find_command(command, previous.get(name, {}).get("path"))
        info = {"installed": bool(path), "path": path, "version": None, "auth_status": "unavailable", "models": [], "models_status": "unavailable", "efforts": sorted(EFFORTS[name])}
        if path:
            _, info["version"] = run_capture([path, "--version"])
            if name == "claude":
                _, output = run_capture([path, "auth", "status"])
                try:
                    info["auth_status"] = "authenticated" if json.loads(output).get("loggedIn") else "unauthenticated"
                except (json.JSONDecodeError, AttributeError):
                    pass
            elif name == "codex":
                code, output = run_capture([path, "login", "status"])
                if code == 0:
                    info["auth_status"] = "authenticated" if "logged in" in output.lower() else "unauthenticated"
            if name == "cursor":
                code, output = run_capture([path, "models"], 15)
                if code == 0:
                    info["models"] = sorted({line.strip().split()[0] for line in output.splitlines() if line.strip() and not line.startswith(("Available", "Model"))})
                    info["models_status"] = "verified"
            elif name == "opencode":
                code, output = run_capture([path, "models"], 15)
                if code == 0:
                    info["models"] = sorted({line.strip() for line in output.splitlines() if "/" in line and " " not in line.strip()})
                    info["models_status"] = "verified"
        agents[name] = info
    result = {"scanned_at": dt.datetime.now(dt.timezone.utc).isoformat(), "agents": agents}
    target = capabilities_path(automations)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2) + "\n")
    lines = ["---", "title: Agent options", "description: Agents, models, and effort levels available on this computer.", "generated: true", "local: true", f"last_scanned: {result['scanned_at']}", "---", "", "# Agent options", "", "| Agent | Installed | Authentication | Version | Model discovery | Effort |", "|---|---:|---|---|---|---|"]
    for name, info in agents.items():
        efforts = ", ".join(f"`{v}`" for v in info["efforts"])
        lines.append(f"| `{name}` | {'Yes' if info['installed'] else 'No'} | {info['auth_status']} | {info['version'] or '—'} | {info['models_status']} | {efforts} |")
    for name, info in agents.items():
        if info["models"]:
            lines.extend(["", f"## {name.title()} models", "", *[f"- `{model}`" for model in info["models"]]])
    (automations / "AGENT-OPTIONS.md").write_text("\n".join(lines) + "\n")
    return result


def connect_db(automations: Path) -> sqlite3.Connection:
    db = automations / "_heartbeat" / ".heartbeat.db"
    db.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db)
    conn.execute("""CREATE TABLE IF NOT EXISTS runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, date TEXT, time TEXT,
      task TEXT, task_file TEXT, scheduled_for TEXT, agent TEXT, model TEXT,
      effort TEXT, permission_mode TEXT, status TEXT, exit_code INTEGER,
      duration_ms INTEGER, input_tokens INTEGER, output_tokens INTEGER,
      cost_usd REAL, output TEXT, git_before TEXT, git_after TEXT,
      dirty_files INTEGER, note TEXT)""")
    existing = {row[1] for row in conn.execute("PRAGMA table_info(runs)")}
    columns = {
        "ts": "TEXT", "date": "TEXT", "time": "TEXT", "task": "TEXT",
        "task_file": "TEXT", "scheduled_for": "TEXT", "agent": "TEXT",
        "model": "TEXT", "effort": "TEXT", "permission_mode": "TEXT",
        "status": "TEXT", "exit_code": "INTEGER", "duration_ms": "INTEGER",
        "input_tokens": "INTEGER", "output_tokens": "INTEGER", "cost_usd": "REAL",
        "output": "TEXT", "git_before": "TEXT", "git_after": "TEXT",
        "dirty_files": "INTEGER", "note": "TEXT",
    }
    for name, kind in columns.items():
        if name not in existing:
            conn.execute(f"ALTER TABLE runs ADD COLUMN {name} {kind}")
    conn.commit()
    return conn


def latest_scheduled(conn, name: str):
    row = conn.execute("SELECT scheduled_for FROM runs WHERE task=? AND scheduled_for IS NOT NULL ORDER BY scheduled_for DESC LIMIT 1", (name,)).fetchone()
    return dt.datetime.fromisoformat(row[0]) if row else None


def occurrence(task: dict, now: dt.datetime, last):
    spec = parse_schedule(task["schedule"])
    zone = timezone(task.get("timezone", "local"))
    local_now = now.astimezone(zone)
    if spec[0] == "interval":
        if last is None:
            return now
        candidate = last + dt.timedelta(seconds=spec[1])
        while candidate + dt.timedelta(seconds=spec[1]) <= now:
            candidate += dt.timedelta(seconds=spec[1])
        return candidate
    if spec[0] == "daily":
        candidate = local_now.replace(hour=spec[1], minute=spec[2], second=0, microsecond=0)
        if candidate > local_now:
            candidate -= dt.timedelta(days=1)
    else:
        days = (local_now.weekday() - spec[1]) % 7
        candidate = (local_now - dt.timedelta(days=days)).replace(hour=spec[2], minute=spec[3], second=0, microsecond=0)
        if candidate > local_now:
            candidate -= dt.timedelta(days=7)
    return candidate.astimezone(dt.timezone.utc)


def next_occurrence(task: dict, now: dt.datetime, last):
    spec = parse_schedule(task["schedule"])
    candidate = occurrence(task, now, last)
    if candidate > now:
        return candidate
    if spec[0] == "interval":
        while candidate <= now:
            candidate += dt.timedelta(seconds=spec[1])
    else:
        candidate += dt.timedelta(days=1 if spec[0] == "daily" else 7)
    return candidate


def insert_run(conn, task, scheduled, agent, status, output, **values):
    now = dt.datetime.now(dt.timezone.utc)
    conn.execute("""INSERT INTO runs
      (ts,date,time,task,task_file,scheduled_for,agent,model,effort,permission_mode,status,exit_code,duration_ms,input_tokens,output_tokens,cost_usd,output,git_before,git_after,dirty_files)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""", (
        now.isoformat(), now.date().isoformat(), now.time().replace(microsecond=0).isoformat(), task.get("name"), Path(task.get("path", "")).name,
        scheduled.isoformat() if scheduled else None, agent, task.get("model", "default"), task.get("effort", "default"), task.get("permission_mode", "auto"), status,
        values.get("exit_code", 0), values.get("duration_ms", 0), values.get("input_tokens", 0), values.get("output_tokens", 0), values.get("cost_usd", 0), output,
        values.get("git_before"), values.get("git_after"), values.get("dirty_files", 0)))
    conn.commit()


def resolve_agent(task, automations: Path, caps):
    agent = task["agent"]
    if agent != "auto":
        return agent
    root = automations.parent
    markers = (("claude", root / ".claude"), ("codex", root / ".codex"), ("cursor", root / ".cursor"), ("opencode", root / ".opencode"))
    for name, marker in markers:
        if marker.exists() and caps.get("agents", {}).get(name, {}).get("auth_status") == "authenticated":
            return name
    authenticated = next((name for name in COMMANDS if caps.get("agents", {}).get(name, {}).get("auth_status") == "authenticated"), None)
    if authenticated:
        return authenticated
    for name, marker in markers:
        if marker.exists() and caps.get("agents", {}).get(name, {}).get("installed"):
            return name
    return next((name for name in COMMANDS if caps.get("agents", {}).get(name, {}).get("installed")), "claude")


def command_for(task, agent, runtime: Path):
    model, effort, permission = task["model"], task["effort"], task.get("permission_mode", "auto")
    if agent == "claude":
        cmd = ["claude", "-p", "--output-format", "json"]
        if model != "default": cmd += ["--model", model]
        if effort != "default": cmd += ["--effort", effort]
        cmd += ["--permission-mode", "plan" if permission == "restricted" else "bypassPermissions"]
        if permission != "restricted": cmd += ["--settings", '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false}}']
    elif agent == "codex":
        cmd = ["codex", "exec", "--json"]
        if model != "default": cmd += ["-m", model]
        if effort != "default": cmd += ["-c", f"model_reasoning_effort={effort}"]
        cmd += ["--sandbox", "read-only"] if permission == "restricted" else ["--approve-for-me", "--sandbox", "workspace-write"]
    elif agent == "cursor":
        selected = model if effort == "default" else f"{model}[effort={effort}]"
        cmd = ["agent", "-p", "--output-format", "json"]
        if selected != "default": cmd += ["--model", selected]
        if permission == "restricted": cmd += ["--mode", "plan"]
    elif agent == "opencode":
        cmd = ["opencode", "run"]
        if model != "default": cmd += ["--model", model]
        if permission != "restricted": cmd += ["--auto"]
    else:
        config_path = runtime / ".heartbeat.json"
        try:
            config = json.loads(config_path.read_text())
            cmd = shlex.split(config["agent_command"])
        except (OSError, KeyError, json.JSONDecodeError) as exc:
            raise ConfigError("custom agent requires agent_command in _heartbeat/.heartbeat.json") from exc
    return cmd


def parse_output(agent, raw):
    usage, text = {}, raw
    try:
        if agent == "codex":
            objects = [json.loads(line) for line in raw.splitlines() if line.lstrip().startswith("{")]
            message = next((o for o in objects if o.get("type") == "item.completed" and o.get("item", {}).get("type") == "agent_message"), {})
            usage = next((o.get("usage", {}) for o in reversed(objects) if o.get("type") == "turn.completed"), {})
            text = message.get("item", {}).get("text", raw)
        else:
            obj = json.loads(raw)
            usage = obj.get("usage", {})
            text = obj.get("result") or obj.get("output") or raw
    except (json.JSONDecodeError, TypeError):
        pass
    return text, usage


def execute_task(task, agent, automations, conn, scheduled):
    root, runtime = automations.parent, automations / "_heartbeat"
    try:
        cmd = command_for(task, agent, runtime)
        if agent in COMMANDS:
            agent_path = load_capabilities(automations).get("agents", {}).get(agent, {}).get("path")
            if not agent_path or not os.access(agent_path, os.X_OK):
                raise ConfigError(f"agent '{agent}' executable is unavailable; refresh AGENT-OPTIONS.md")
            cmd[0] = agent_path
    except ConfigError as exc:
        insert_run(conn, task, scheduled, agent, "configuration_error", str(exc))
        return
    prompt = SAFETY_PREFIX + task["body"]
    full_cmd, input_text = cmd + [prompt], None
    if agent == "custom":
        try:
            config = json.loads((runtime / ".heartbeat.json").read_text())
        except (OSError, json.JSONDecodeError):
            config = {}
        if config.get("agent_input") == "stdin":
            full_cmd, input_text = cmd, prompt
    before = run_capture(["git", "-C", str(root), "rev-parse", "HEAD"])[1] or "none"
    started = time.monotonic()
    try:
        result = subprocess.run(full_cmd, input=input_text, cwd=root, text=True, capture_output=True, timeout=duration(task.get("timeout", "10m"), "timeout"))
        raw, exit_code = (result.stdout or result.stderr), result.returncode
        text, usage = parse_output(agent, raw)
        status = "ok" if exit_code == 0 and "HEARTBEAT_OK" in text else ("alert" if exit_code == 0 else "error")
    except subprocess.TimeoutExpired as exc:
        text, usage, exit_code, status = f"agent exceeded timeout; partial output: {exc.stdout or ''}", {}, 124, "timeout"
    except OSError as exc:
        text, usage, exit_code, status = str(exc), {}, 127, "configuration_error"
    after = run_capture(["git", "-C", str(root), "rev-parse", "HEAD"])[1] or "none"
    dirty = len(run_capture(["git", "-C", str(root), "status", "--porcelain"])[1].splitlines())
    insert_run(conn, task, scheduled, agent, status, text, exit_code=exit_code, duration_ms=int((time.monotonic()-started)*1000), input_tokens=usage.get("input_tokens", 0), output_tokens=usage.get("output_tokens", 0), cost_usd=usage.get("total_cost_usd", 0) or 0, git_before=before, git_after=after, dirty_files=dirty)
    if status != "ok":
        notify(root.name, f"{task['title']}: {status}")


def notify(project: str, message: str):
    if sys.platform == "darwin" and shutil.which("osascript"):
        script = f'display notification {json.dumps(message)} with title {json.dumps("Heartbeat · " + project)}'
        subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    elif shutil.which("notify-send"):
        subprocess.run(["notify-send", f"Heartbeat · {project}", message], capture_output=True, text=True)


def report(automations: Path):
    tasks, invalid = discover(automations)
    conn = connect_db(automations)
    now = dt.datetime.now(dt.timezone.utc)
    rows = ["---", "title: Dashboard", "description: Status and schedules for local automations.", "generated: true", "local: true", "---", "", "# Dashboard", "", "| Automation | Schedule | Agent | Model | Validation | Last run | Next run |", "|---|---|---|---|---|---|---|"]
    for task in tasks:
        last = conn.execute("SELECT status, ts FROM runs WHERE task=? ORDER BY ts DESC LIMIT 1", (task["name"],)).fetchone()
        scheduled = latest_scheduled(conn, task["name"])
        nxt = next_occurrence(task, now, scheduled).astimezone(timezone(task.get("timezone", "local"))).strftime("%Y-%m-%d %H:%M %Z")
        validation = "Valid" if not task.get("warnings") else "Valid · " + "; ".join(task["warnings"])
        rows.append(f"| [{task['title']}]({Path(task['path']).name}) | `{task['schedule']}` | `{task['agent']}` | `{task['model']}` | {validation} | {last[0] + ' · ' + last[1] if last else 'Never'} | {nxt} |")
    for item in invalid:
        rows.append(f"| [{item.get('title', item['name'])}]({Path(item['path']).name}) | — | — | — | **Invalid:** {'; '.join(item['errors'])} | — | — |")
    (automations / "DASHBOARD.md").write_text("\n".join(rows) + "\n")
    run_rows = ["---", "title: Runs", "description: Generated history for local automations.", "generated: true", "local: true", "---", "", "# Runs", "", "| Date | Task | Agent | Model | Status | Duration | Summary |", "|---|---|---|---|---|---|---|"]
    for row in conn.execute("SELECT date,task,agent,model,status,duration_ms,output FROM runs ORDER BY ts DESC LIMIT 100"):
        summary = (row[6] or "").replace("|", "\\|").replace("\n", " ")[:100]
        run_rows.append(f"| {row[0] or '—'} | `{row[1] or 'legacy'}` | `{row[2] or '—'}` | `{row[3] or '—'}` | {row[4]} | {row[5] or 0}ms | {summary} |")
    (automations / "RUNS.md").write_text("\n".join(run_rows) + "\n")


def run_due(automations: Path):
    cap_file = capabilities_path(automations)
    if not cap_file.exists() or time.time() - cap_file.stat().st_mtime > 86400:
        scan_capabilities(automations)
    tasks, _ = discover(automations)
    conn, now = connect_db(automations), dt.datetime.now(dt.timezone.utc)
    for task in tasks:
        if not task["enabled"]:
            continue
        last = latest_scheduled(conn, task["name"])
        candidate = occurrence(task, now, last)
        if last and candidate <= last:
            continue
        if candidate > now:
            continue
        lateness = (now - candidate).total_seconds()
        maximum = duration(task.get("max_lateness", "4h"), "max_lateness")
        if lateness > maximum or (task.get("missed_run", "catch-up") == "skip" and lateness > 600):
            insert_run(conn, task, candidate, task["agent"], "missed", "scheduled occurrence was outside its allowed run window")
            continue
        agent = resolve_agent(task, automations, load_capabilities(automations))
        execute_task(task, agent, automations, conn, candidate)
    report(automations)


def split_table(line: str):
    protected = line.strip().strip("|")
    cells, current, escaped = [], [], False
    for char in protected:
        if escaped:
            current.append(char); escaped = False
        elif char == "\\":
            escaped = True
        elif char == "|":
            cells.append("".join(current).strip()); current = []
        else:
            current.append(char)
    cells.append("".join(current).strip())
    return [re.sub(r"^`|`$", "", cell) for cell in cells]


def migrate_heartbeat(automations: Path):
    old = automations / "HEARTBEAT.md"
    if not old.exists():
        return
    lines = old.read_text().splitlines()
    header = next((i for i, line in enumerate(lines) if [c.lower() for c in split_table(line)] == ["task", "interval", "prompt"]), None)
    if header is None:
        raise ConfigError("cannot migrate HEARTBEAT.md: task table not found")
    runtime = automations / "_heartbeat"; runtime.mkdir(exist_ok=True)
    config = {}
    try: config = json.loads((runtime / ".heartbeat.json").read_text())
    except (OSError, json.JSONDecodeError): pass
    for line in lines[header + 2:]:
        if not line.strip().startswith("|"): break
        name, interval, prompt = split_table(line)
        target = automations / f"{name}.md"
        if target.exists():
            raise ConfigError(f"cannot migrate: {target.name} already exists")
        title = name.replace("-", " ").title()
        content = f'''---
title: {title}
type: automation
name: {name}
enabled: true
schedule: "every {interval or '1d'}"
timezone: local
missed_run: catch-up
max_lateness: 4h
agent: {config.get('agent', 'auto')}
model: {config.get('model', 'default')}
effort: {config.get('effort', 'default')}
permission_mode: {config.get('permission_mode', 'auto')}
timeout: 10m
---

# Prompt

{prompt}
'''
        target.write_text(content)
    old.rename(runtime / "legacy-HEARTBEAT.md")
    for relative in (Path(".ok/templates/heartbeat.md"), Path(".templates/heartbeat.md")):
        legacy_template = automations / relative
        if legacy_template.exists():
            destination = runtime / "legacy-heartbeat-template.md"
            if destination.exists():
                destination = runtime / f"legacy-{relative.parts[0].lstrip('.')}-heartbeat-template.md"
            legacy_template.rename(destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("validate", "scan", "report", "run", "migrate"))
    parser.add_argument("path", nargs="?", default="..")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    automations = Path(args.path).resolve()
    if automations.is_file(): automations = automations.parent
    try:
        if args.command == "scan": scan_capabilities(automations)
        elif args.command == "report": report(automations)
        elif args.command == "run": run_due(automations)
        elif args.command == "migrate": migrate_heartbeat(automations)
        else:
            cap_file = capabilities_path(automations)
            if not cap_file.exists() or time.time() - cap_file.stat().st_mtime > 86400:
                scan_capabilities(automations)
            tasks, invalid = discover(automations)
            result = {"valid": not invalid and bool(tasks), "tasks": tasks, "invalid": invalid}
            if args.json: print(json.dumps(result, indent=2))
            else:
                for task in tasks:
                    for warning in task.get("warnings", []): print(f"warning: {Path(task['path']).name}: {warning}")
                for item in invalid: print(f"error: {Path(item['path']).name}: {'; '.join(item['errors'])}")
                print(f"valid: {len(tasks)} automation(s)") if result["valid"] else None
            if not result["valid"]: raise SystemExit(1)
    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr); raise SystemExit(1)


if __name__ == "__main__":
    main()
