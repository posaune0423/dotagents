# Global Instructions

## Rules

- Actively use skills and subagents to keep the main thread context clean.
  - **Skill**: For tasks requiring specialized knowledge, read the relevant skill's `SKILL.md` before starting work (for example, `skills/<name>/SKILL.md`), and apply its procedures and constraints exactly as written. Do not stop at merely declaring skill use.
  - **Subagent**: Delegate work when an isolated context or parallel execution is useful and the active host provides an appropriate subagent.
    - `architect`: Clarifies architecture, trade-offs, responsibility boundaries, and implementation plans.
    - `browser-debugger`: Reproduces browser issues and gathers evidence from the console, network, DOM, and screenshots.
    - `docs-researcher`: Verifies APIs, defaults, and version differences against official documentation.
    - `light-worker`: Handles mechanical checks such as formatting, linting, type checking, and tests.

## Development Style

Develop with TDD (Exploration -> Red -> Green -> Refactoring).
If KPIs or coverage targets are provided, keep iterating until they are met.
Ask questions to clarify ambiguous instructions.

### Git Branching

- Never prefix branch names with an agent or tool name such as `codex/`.
- Follow the repository's established branch naming convention when one exists.
- Otherwise, use a simple Git Flow convention: `feature/<short-kebab-case-name>` for features, `fix/<short-kebab-case-name>` for regular fixes, `release/<version-or-name>` for release preparation, and `hotfix/<short-kebab-case-name>` for urgent production fixes.
- Reuse the repository's existing long-lived branches; do not introduce `develop` or another long-lived branch unless the repository already uses it or the user explicitly requests it.

### Git Worktrees

- Before invoking the `git-wt` skill to create or switch worktrees, compare `git rev-parse --path-format=absolute --git-dir` with `git rev-parse --path-format=absolute --git-common-dir`.
- If the paths differ, the current directory is already a linked worktree; stay there and do not invoke `git-wt` unless the user explicitly requests a worktree lifecycle operation.
- Use the `git-wt` skill only when a worktree lifecycle operation is actually needed.
- Prefer `git wt` over raw `git worktree add`, `remove`, `move`, or `prune`.

### Code Design

- Maintain separation of concerns.
- Separate state from logic.
- Prioritize readability and maintainability.
- Define contract layers (APIs/types) strictly, and keep implementation layers regenerable.
- Express rules that can be checked statically with the environment's linter or ast-grep, not with prompts.

### Tools

- Search: Use `rg` (ripgrep) instead of `grep`.
- Find: Use `fd` instead of `find`.
- JSON: Use `jq` for JSON processing.
- Shell: Fish shell is the primary shell.
- Task: Use `justfile` instead of Makefile.
- Node.js: Use Bun and Node.js v24+.
- E2E: Use `playwright` instead of `chrome-devtools`.
- Python: `uv`.
