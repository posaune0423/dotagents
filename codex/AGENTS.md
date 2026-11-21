# Global Instructions

## How to work

- Finish the task you were asked to do. Done means implemented, run and checked, and with whatever broke fixed. Do not stop after proposing a next step; keep going through the steps within the scope of the request.
- When something is ambiguous and the work is reversible, proceed on an assumption and state it in the final answer. Ask only when the answer would materially change the deliverable, or before a destructive, public, or paid action. While waiting for an answer, keep working on whatever does not depend on it.
- Local test, lint, format, type check, and build runs, file reads, and `git status`, `git diff`, and `git log` need no per-step confirmation.
- Before finishing, run the change and confirm it works as intended. Say so when something could not be verified.
- Batch independent tool calls (searches, file reads, check runs) and run them in parallel. Run only calls that depend on an earlier result in sequence.
- Edit existing files at the affected lines; do not rewrite whole files.
- When the user's instructions and a skill disagree, follow the user's instructions.

## Skills and subagents

- **Skill**: For tasks requiring specialized knowledge, read the relevant skill's `SKILL.md` before starting work (for example, `skills/<name>/SKILL.md`) and follow its procedures and constraints. Do not stop at merely declaring skill use.
- **Subagent**: Every spawn starts from an empty context and costs time and tokens. Use one only when at least one of these applies.
  - Independent pieces of work can run in parallel.
  - Long output, such as test, lint, or CI logs or large amounts of documentation or web pages, should stay out of the main thread.
  - A review needs someone who has not seen the implementation.
  - Keep back-and-forth work, changes that take a few tool calls, and latency-sensitive work in the main thread.
  - Make the delegated prompt self-contained: objective, working directory, exact files or commands, whether edits are allowed, acceptance criteria, and what to return.
  - Use only agents the active host defines.
    - `light-worker`: Runs formatting, linting, type checks, tests, and builds, and returns only the result. Fixes mechanical failures only.
      - When spawning it in Codex, default to `fork_turns="none"`; use the smallest positive integer only when recent context is essential. Do not use `fork_turns="all"`.
    - `docs-researcher`: Verifies APIs, defaults, and version differences against the official documentation of an external library or CLI.
    - `researcher`: Owns one independent, read-only research lane, such as primary sources, a repository, or data.
    - `impl-worker`: Implements a change whose files, behavior, and acceptance criteria are already decided.
    - `pr-runner`: Opens or updates a PR, watches CI, and handles review comments.
    - `web-operator` (Claude Code): Retrieves Notion, Slack, X, and internal SaaS pages through an already-logged-in browser and returns only what matters.
    - `architect`, `reviewer`, `evidence-analyst`, `evidence-auditor` (Codex): Own design decisions, independent code review, and evidence analysis and auditing.

## Development Style

- Develop behavior changes with TDD (Exploration -> Red -> Green -> Refactoring). Configuration files, documents, throwaway scripts, and generated code are exempt.
- If KPIs or coverage targets are provided, keep iterating until they are met.
- When descriptions of the current implementation or coding conventions in documentation or instruction files conflict with existing code, inspect the relevant code and tests and follow the consistent conventions in the existing code. Do not rewrite working code to match documentation solely because they disagree.
- Honor explicit new requirements, migration plans, and security constraints even when existing code differs. Ask only when it is unclear which source is outdated and the answer would materially change the work. In the final reply, briefly report each inconsistency found and how it was resolved.

### Git Branching

- Never prefix branch names with an agent or tool name such as `codex/`.
- Follow the repository's established branch naming convention when one exists.
- Otherwise, use a simple Git Flow convention: `feature/<short-kebab-case-name>` for features, `fix/<short-kebab-case-name>` for regular fixes, `release/<version-or-name>` for release preparation, and `hotfix/<short-kebab-case-name>` for urgent production fixes.
- Reuse the repository's existing long-lived branches; do not introduce `develop` or another long-lived branch unless the repository already uses it or the user explicitly requests it.

### Git Worktrees

- When an agent creates a worktree, use `git wt --basedir=.worktrees --nocd <branch>` so it stays under `<project>/.worktrees/`. Where `git wt` is unavailable, use `git worktree add .worktrees/<branch> -b <branch>`. If already inside a linked worktree, do not create another one.

### Code Design

- Separate state from logic.
- Define contract layers (APIs/types) strictly, and keep implementation layers regenerable.
- Express rules that can be checked statically with the environment's linter or ast-grep, not with prompts.

### Tools

- Task: Use `justfile` instead of Makefile.
- Node.js: Use Bun and Node.js v24+.
- E2E and browser work during local development: Use `playwright` instead of `chrome-devtools`.
  - Run browsers headless by default (`playwright-cli open` without `--headed`). Use `--headed` only when the user must see or operate the window (e.g. manual login), and do not drive browsers through Computer Use / `orca computer`, because both bring the window to the front.
- Python: `uv`.
