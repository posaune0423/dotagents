---
name: init-agent
description: >
  Bootstraps shared agent layout at the repository root: creates symlinks so
  `.agents/skills`, `.agents/commands`, and `.agents/rules` appear under
  `.cursor`, `.claude`, and `.codex`, and adds `CLAUDE.md` as a symlink to
  `AGENTS.md`. Use when initializing a repo, after cloning, or when the user
  says init-agent, agent symlink setup, or unify Cursor/Codex/Claude agent files.
---

# init-agent

## When to use

- New checkout or new repo: wire one canonical tree (`.agents/...`) into tool-specific folders.
- User asks to run **init-agent** or to symlink `.agents` into `.cursor` / `.claude` / `.codex`.
- Duplicated rules or skills drift: prefer a single source under `.agents` and symlinks into each tool.

## Preconditions

- Current working directory is the **repository root** (the directory that contains `.agents` and `AGENTS.md`).
- These directories exist (create empty dirs if needed before running):
  - `.agents/skills`
  - `.agents/commands`
  - `.agents/rules`
- **Unix-like OS** (macOS, Linux). Symlinks on Windows may require Developer Mode or elevated permissions; the script does not support that path.

## What it does

From repo root, run:

```bash
bash .agents/skills/init-agent/scripts/init-agent.sh
```

The script:

1. Ensures `.agents/skills`, `.agents/commands`, and `.agents/rules` exist.
2. For each of `.cursor`, `.claude`, and `.codex`:
   - Creates `skills`, `commands`, and `rules` as **symlinks** to `../.agents/skills`, `../.agents/commands`, and `../.agents/rules` respectively (paths relative to each symlink).
3. Creates `CLAUDE.md` → `AGENTS.md` at the repo root if `CLAUDE.md` is absent.

The script **refuses** to replace an existing real file or directory at a target path. If a symlink already points to the expected target, it is left as-is.

## After running

- **Cursor**: skills under `.cursor/skills`, rules under `.cursor/rules` (may require reload).
- **Claude Code**: skills/commands/rules under `.claude/*`.
- **Codex**: mirrored under `.codex/*` for project-local tooling; Codex also discovers `.agents/skills` per [Agent Skills](https://developers.openai.com/codex/skills) — symlinks keep one source tree.

If something does not pick up, restart the IDE or Codex/Claude session.

## Troubleshooting

- **"exists and is not a symlink"**: Remove or rename the conflicting path, then re-run.
- **Wrong symlink target**: Delete the symlink and re-run; the script will recreate it.
- **Missing `.agents/...`**: Create the missing folder (can be empty), then re-run.
