# Global Instructions

## How to work

- Done means implemented, run, checked, and with whatever broke fixed. Do not stop after the first implementation to wait for review; the user says so when a task should stop early.
- When something is ambiguous, proceed on stated assumptions for reversible work. Ask only where different readings change the deliverable materially, or before a destructive, public, or paid action, and keep working on what does not depend on the answer.
- Local test, lint, format, typecheck, and build runs, file reads, and `git status`, `git diff`, and `git log` need no per-step approval.
- Batch independent tool calls (searches, reads, check runs) into one message and run them in parallel. Sequence only what depends on an earlier result.
- Change existing files with targeted edits to the affected lines; do not rewrite whole files.

## Skills and subagents

- For tasks requiring specialized knowledge, read the relevant skill's `SKILL.md` before starting work and apply its procedures and constraints exactly as written. Do not stop at merely declaring skill use.
- Delegate to a subagent only when an isolated context or parallel execution is useful. Make the delegated prompt self-contained with the objective, working directory, exact files or commands, whether edits are allowed, and acceptance criteria.
- When spawning `light-worker`, default to `fork_turns="none"`; use the smallest positive integer only when recent context is essential. Never use `fork_turns="all"`.

## Development Style

- Develop behavior changes with TDD (Exploration -> Red -> Green -> Refactoring). Configuration files, docs, throwaway scripts, and generated code are exempt.
- If KPIs or coverage targets are provided, keep iterating until they are met.

### Git Branching

- Never prefix branch names with an agent or tool name such as `codex/`.
- Follow the repository's established branch naming convention when one exists.
- Otherwise, use a simple Git Flow convention: `feature/<short-kebab-case-name>` for features, `fix/<short-kebab-case-name>` for regular fixes, `release/<version-or-name>` for release preparation, and `hotfix/<short-kebab-case-name>` for urgent production fixes.
- Reuse the repository's existing long-lived branches; do not introduce `develop` or another long-lived branch unless the repository already uses it or the user explicitly requests it.

### Git Worktrees

- When an agent creates a worktree, use `git wt --basedir=.worktrees --nocd <branch>` so it stays under `<project>/.worktrees/`. If already inside a linked worktree, do not create another one.

### Code Design

- Separate state from logic.
- Define contract layers (APIs/types) strictly, and keep implementation layers regenerable.
- Express rules that can be checked statically with the environment's linter or ast-grep, not with prompts.

### Tools

- Task: Use `justfile` instead of Makefile.
- Node.js: Use Bun and Node.js v24+.
- E2E and browser work during local development: Use `playwright` instead of `chrome-devtools`.
- Python: `uv`.
