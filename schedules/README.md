# Shared schedules

`schedules/` contains provider-neutral scheduled-task definitions that can be used with Codex, Claude Code,
or another compatible agent. These files are the Git-managed source of truth; they are not linked into an
agent's home directory.

## Layout

Each task lives in `schedules/<task-id>/`:

- `schedule.json`: portable metadata, cadence, runtime requirements, and supported targets
- `SKILL.md`: shared task instructions with required skill frontmatter

The directory name, `schedule.json` `id`, and `SKILL.md` `name` must match. Skills must not contain credentials or
other secrets.

## Definitions

| ID                         | Purpose                                                                                           | Targets                           |
| -------------------------- | ------------------------------------------------------------------------------------------------- | --------------------------------- |
| `mac-storage-audit`        | Read-only inventory and storage-pressure report                                                   | Codex local, Claude Desktop local |
| `safe-dev-storage-cleanup` | Remove only fully verified merged-PR worktrees, old dangling build cache, and old dangling images | Codex local, Claude Desktop local |

The cleanup definition is deliberately unavailable to cloud targets because it must inspect local Git worktrees,
processes, Docker state, and disk usage. Its destructive boundaries are implemented by reviewed scripts under the
definition's `scripts/` directory; scheduled agents invoke those scripts instead of assembling deletion commands.

## Applying a definition

Provider state is intentionally kept separate from this repository:

- Codex writes installed automations to `$CODEX_HOME/automations/<id>/automation.toml` (normally
  `~/.codex/automations/<id>/automation.toml`). Create or update the automation through Codex using the values in
  `schedule.json` and the contents of `SKILL.md`.
- Claude Desktop local tasks keep their prompt under
  `${CLAUDE_CONFIG_DIR:-~/.claude}/scheduled-tasks/<task-name>/SKILL.md`, while schedule and runtime settings are
  managed by the app. Create a Local routine and copy the shared definition into it.
- Claude Code `/schedule` creates a cloud Routine in the Claude account. Use the shared skill instructions and cadence when
  creating or updating a definition that targets `claude-code-cloud`; no local symlink is involved. Cloud Routines
  cannot run definitions that require local-file access.

Target names encode the runtime boundary: `codex-local`, `claude-desktop-local`, `claude-code-cloud`, and
`gemini-local`. A definition with `runtime.execution: "local"` cannot declare a cloud target. When `isolation` is
`shared`, disable isolated worktrees so runs use the task's configured state directory consistently.

This repository does not automatically deploy schedules. That avoids replacing provider-owned state, run history,
permissions, working-directory selections, or thread associations.

## Validation

Run:

```bash
just test-schedules
```

`just check` includes the same validation.
