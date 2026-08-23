# heartbeat CLI reference

Full command list. For when to use which, and the safety model, see SKILL.md.

## Primitives

These are independent, testable steps, each backed by its own script in
scripts/, so nothing is duplicated between the CLI and what actually runs.

```sh
heartbeat init                 # scaffold automations/heartbeat/ in the current project
                                #   creates: HEARTBEAT.md and RUNS.md (from templates,
                                #   if missing), .heartbeat.db, heartbeat-run.sh,
                                #   heartbeat-report.sh, validate-heartbeat.py
                                #   templates: automations/heartbeat/.ok/templates/ when
                                #   the repository already uses OpenKnowledge; otherwise
                                #   automations/heartbeat/.templates/
                                #   side effects: files only. no cron, no registry, no AGENTS.md edit.

heartbeat register             # add the current project to ~/.agents/heartbeat/registry.txt
                                #   and append an "## Automation" pointer to its AGENTS.md
                                #   (skipped if already present)
                                #   side effects: registry.txt, AGENTS.md. no files under
                                #   automations/heartbeat/, no cron.

heartbeat unregister           # remove the current project from the registry
                                #   side effects: registry.txt only.

heartbeat schedule enable      # add the cron entry for this project (every 30 minutes)
heartbeat schedule disable     # comment out the cron entry for this project (kept, not
                                #   deleted, so schedule enable restores the same line)
                                #   side effects: crontab only.
```

## automations (composed wrappers)

```sh
heartbeat automations create   # init + register + schedule enable, in that order.
                                #   prints a heading per step so all three side effects
                                #   are visible, not hidden behind one opaque command.

heartbeat automations list     # every registered project + its last run status

heartbeat automations show [--project <path>]
                                # one project: registered, schedule state, lock state,
                                #   HEARTBEAT.md validation result, the checklist itself,
                                #   and the last run row

heartbeat automations edit     # open $EDITOR on the HEARTBEAT.md for this project, then
                                #   validate it and warn (not block) if it fails

heartbeat automations pause    # alias for: heartbeat schedule disable
heartbeat automations resume   # alias for: heartbeat schedule enable

heartbeat automations delete [--purge] [--project <path>]
                                # schedule disable + unregister.
                                #   default: keeps HEARTBEAT.md, .heartbeat.db, RUNS.md on disk.
                                #   --purge: also deletes automations/heartbeat/ entirely.
```

This is full CRUD on automations: create (init + register + schedule enable,
or the composed create), read (list / show), update (edit, schedule / pause /
resume), delete (delete). Deletion never removes history by default; use
--purge only when the user explicitly wants that.

## runs

```sh
heartbeat runs list [--project <path>]   # recent runs as a markdown table
heartbeat runs show <id>                 # full row for one run
heartbeat runs annotate <id> "<note>"    # the only sanctioned way to edit run history
```

Prefer heartbeat runs list, or reading automations/heartbeat/RUNS.md, over
querying .heartbeat.db directly.
