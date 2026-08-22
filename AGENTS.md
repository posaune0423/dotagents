# dotagents Repository Instructions

## Purpose and Sources of Truth

- This repository is the source of truth for reusable agent skills, commands, rules, and shared tool configuration.
- Keep repository-specific guidance in this file. Cross-repository personal defaults belong in `codex/AGENTS.md`.
- `codex/AGENTS-ja.md` is the canonical authoring source for global instructions. Write the Japanese source first, then translate the complete content into `codex/AGENTS.md`.
- `claude/CLAUDE.md` and `gemini/GEMINI.md` must remain relative symlinks to the English runtime file at `codex/AGENTS.md`.
- Root `CLAUDE.md` and `GEMINI.md` bridge this repository's project instructions to tools that do not read root `AGENTS.md` directly.

## Repository Layout

- `skills/`, `commands/`, and `rules/` contain the shared agent assets linked into `~/.agents` and consumer projects.
- `codex/`, `claude/`, and `gemini/` contain version-controlled global tool entries. Do not rename them back to hidden directories.
- `scripts/` and `justfile` own installation, linking, and verification behavior.
- Consumer projects still use tool-required hidden paths such as `.codex/`, `.claude/`, and `.cursor/`; only this repository's source directories are non-hidden.
- Claude-created `.claude/worktrees/` is machine-local runtime state. Never move, delete, format, or stage it as part of configuration maintenance.

## Development Workflow

- Use TDD for script behavior: add a failing integration test under `scripts/tests/`, observe the expected failure, then implement the smallest fix.
- Use `just` as the task entry point and Bun for package scripts; when Node.js is required, use v24+.
- Run `scripts/tests/link-dotagents.test.sh` for global-link changes and `just check` before handing off changes.
- Shell changes must pass ShellCheck and `shfmt`; Markdown, JSON, and JavaScript/TypeScript must pass the repository's Prettier and ESLint configuration.

## Link Safety

- Global links must resolve into the main checkout, never a disposable worktree.
- Link only repository-managed entries. Keep `~/.codex/config.toml`, `~/.claude/settings.json`, credentials, histories, databases, plugins, and caches home-local.
- Inspect a destination before replacing it. Preserve existing real files through the script's timestamped backup behavior; replacing an existing symlink is allowed.
- Use relative symlinks inside this repository and absolute symlinks from home directories into the main checkout.
- After changing link topology, update the link script, verifier, README, and integration test together.

## Skill and Agent Maintenance

- Keep each reusable skill's contract in its `SKILL.md`; use supporting scripts and references for operational detail.
- Preserve top-level discovery links for project-specific skills that must remain globally discoverable.
- Claude and Codex subagent formats are tool-specific. Do not merge `claude/agents/*.md` and `codex/agents/*.toml` into one generated format.
- Keep shared subagent names identical across Claude and Codex definitions, using kebab-case.
- Keep unrelated working-tree changes out of the task's diff, especially machine-local project skills and active worktree state.

## Global Instruction Translation

- Never edit `codex/AGENTS.md` as the primary source. Update `codex/AGENTS-ja.md` first, then translate the complete Japanese source into English.
