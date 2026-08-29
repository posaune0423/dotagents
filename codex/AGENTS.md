# Global Instructions

## Rules

- Actively use skills and subagents to keep the main thread context clean.
  - **Skill**: For tasks requiring specialized knowledge, read the relevant skill's `SKILL.md` before starting work (for example, `skills/<name>/SKILL.md`), and apply its procedures and constraints exactly as written. Do not stop at merely declaring skill use.
  - **Subagent**: Delegate work when an isolated context or parallel execution is useful and the active host provides an appropriate subagent.
    - `architect`: Clarifies architecture, trade-offs, responsibility boundaries, and implementation plans.
    - `browser-debugger`: Reproduces browser issues and gathers evidence from the console, network, DOM, and screenshots.
    - `docs-researcher`: Verifies APIs, defaults, and version differences against official documentation.
    - `light-worker`: Handles mechanical checks such as formatting, linting, type checking, and tests.
      - When spawning `light-worker`, default to `fork_turns="none"`; use the smallest positive integer only when recent context is essential. Never use `fork_turns="all"`.
      - Make the delegated prompt self-contained with the objective, working directory, exact files or commands, whether edits are allowed, and acceptance criteria.
    - `web-operator`: Retrieves Notion, Slack, X, and internal SaaS pages through an already-logged-in browser and returns only what matters.

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

- Before creating a worktree, compare `git rev-parse --path-format=absolute --git-dir` with `git rev-parse --path-format=absolute --git-common-dir`.
- If the paths differ, the current directory is already a linked worktree; stay there and do not create another one unless the user explicitly asks for a worktree lifecycle operation.
- Create worktrees with the host's own worktree tooling (in Claude Code, its worktree feature and the `EnterWorktree` / `ExitWorktree` tools) rather than by shelling out. Only that path processes the repository's `.worktreeinclude`, which copies the gitignored files a fresh worktree needs; `git worktree add` run from a shell copies nothing.
- When a worktree must be handled from a shell, use plain `git worktree add`, and remove it with `git worktree remove` followed by `git branch -d`. Both already refuse to discard work: `remove` stops on a dirty worktree and `branch -d` stops on an unmerged branch. Escalate to `--force` or `-D` only after the user confirms discarding it.
- Never copy dependency directories such as `node_modules` between worktrees. Install them per worktree so each one resolves independently.

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
- E2E and browser work during local development: Use `playwright` instead of `chrome-devtools`.
- Authenticated web: Delegate pages that require a login to `web-operator`, choosing a route in this order: MCP, then CLI, then the authenticated browser. The browser profile map lives at `~/.claude/browser-profiles.json`. Do not use `playwright` for an authenticated external service unless a saved storage state exists; it otherwise starts from a fresh profile with no session.
- Interactive logins: Never attempt a login that needs a browser round trip, such as `ntn login`. When a credential is absent, switch to the authenticated browser route instead of retrying.
- Python: `uv`.
