# Global Instructions

## Rules

- **Skill**: For tasks requiring specialized knowledge, read the relevant skill's `SKILL.md` before starting work (for example, `skills/<name>/SKILL.md`), and apply its procedures and constraints exactly as written. Do not stop at merely declaring skill use.
- **Subagent**: Every spawn starts from an empty context and costs time and tokens. Use one only when at least one of these applies.
  - Independent pieces of work can run in parallel.
  - Long output, such as test, lint, or CI logs or large amounts of documentation or web pages, should stay out of the main thread.
  - A review needs someone who has not seen the implementation.
  - Keep back-and-forth work, changes that take a few tool calls, and latency-sensitive work in the main thread.
  - Make the delegated prompt self-contained: objective, working directory, exact files or commands, whether edits are allowed, acceptance criteria, and what to return.
  - Use only agents the active host defines.
    - `light-worker`: Runs formatting, linting, type checks, tests, and builds, and returns only the result. Fixes mechanical failures only.
      - When spawning it, default to `fork_turns="none"`; use the smallest positive integer only when recent context is essential. Never use `fork_turns="all"`.
    - `docs-researcher`: Verifies APIs, defaults, and version differences against the official documentation of an external library or CLI.
    - `researcher`: Owns one independent, read-only research lane, such as primary sources, a repository, or data.
    - `impl-worker`: Implements a change whose files, behavior, and acceptance criteria are already decided.
    - `pr-runner`: Opens or updates a PR, watches CI, and handles review comments.
    - `web-operator` (Claude Code): Retrieves Notion, Slack, X, and internal SaaS pages through an already-logged-in browser and returns only what matters.
    - `architect`, `reviewer`, `evidence-analyst`, `evidence-auditor` (Codex): Own design decisions, independent code review, and evidence analysis and auditing.

## Development Style

Develop with TDD (Exploration -> Red -> Green -> Refactoring).
If KPIs or coverage targets are provided, keep iterating until they are met.
Ask questions to clarify ambiguous instructions.

- When descriptions of the current implementation or coding conventions in documentation or instruction files conflict with existing code, inspect the relevant code and tests and follow the consistent conventions in the existing code. Do not rewrite working code to match documentation solely because they disagree.
- Honor explicit new requirements, migration plans, and security constraints even when existing code differs. Ask only when it is unclear which source is outdated and the answer would materially change the work. In the final reply, briefly report each inconsistency found and how it was resolved.

### Git Branching

- Never prefix branch names with an agent or tool name such as `codex/`.
- Follow the repository's established branch naming convention when one exists.
- Otherwise, use a simple Git Flow convention: `feature/<short-kebab-case-name>` for features, `fix/<short-kebab-case-name>` for regular fixes, `release/<version-or-name>` for release preparation, and `hotfix/<short-kebab-case-name>` for urgent production fixes.
- Reuse the repository's existing long-lived branches; do not introduce `develop` or another long-lived branch unless the repository already uses it or the user explicitly requests it.

### Git Worktrees

- When an agent creates a worktree, use `git wt --basedir=.worktrees --nocd <branch>` so it stays under `<project>/.worktrees/`. If already inside a linked worktree, do not create another one.

### Code Design

- Maintain separation of concerns.
- Separate state from logic.
- Prioritize readability and maintainability.
- Define contract layers (APIs/types) strictly, and keep implementation layers regenerable.
- Express rules that can be checked statically with the environment's linter or ast-grep, not with prompts.

### Tools

- Task: Use `justfile` instead of Makefile.
- Node.js: Use Bun and Node.js v24+.
- E2E and browser work during local development: Use `playwright` instead of `chrome-devtools`.
- Python: `uv`.
