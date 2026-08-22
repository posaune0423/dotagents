# Global Instructions

## Rules

- Actively use skills and subagents to keep the main thread context clean.
  - **Skill**: For tasks requiring specialized knowledge, read the relevant skill's `SKILL.md` directly under that skill before starting work (for example, `skills/<name>/SKILL.md`), and apply its procedures and constraints exactly as written. Do not stop at merely declaring that you will use the skill.
  - **Subagent**: Proactively delegate to subagents when work benefits from an isolated context or parallel execution (refactoring, review passes, broad codebase exploration, UI debugging, documentation research, or lightweight PR workflows). You do not need the user to explicitly ask for a subagent—judge from the task and use the dedicated agents below. For those cases, delegation is mandatory.
  - [browser_debugger](./agents/browser_debugger.toml): A dedicated subagent for debugging UIs and web apps.
  - [docs_researcher](./agents/docs_researcher.toml): A dedicated subagent that uses `ctx7` and web_search tools to search for and collect necessary information from official documentation, forums, issues, and local files.
  - [light_worker](./agents/light_worker.toml): A dedicated subagent for lightweight tasks such as formatting, linting, type checks, and PR creation/updating workflows (docs/metadata updates, quick PR-ready touch-ups).
  - [qwen_worker](./agents/qwen_worker.toml): A dedicated subagent that uses the local LLM qwen3.6 via lmstudio.
  - Note: Skills and subagents may be used together. You may also pass knowledge from a skill to a subagent and have it execute the work.
  - Note: For small tasks where no relevant skill or subagent exists, proceed with the normal workflow.

## Development Style

Develop with TDD (Exploration -> Red -> Green -> Refactoring).
If KPIs or coverage targets are provided, keep iterating until they are met.
Ask questions to clarify ambiguous instructions.

### Git Branching

- Never prefix branch names with an agent or tool name such as `codex/`.
- Follow the repository's established branch naming convention when one exists.
- Otherwise, use a simple Git Flow convention: `feature/<short-kebab-case-name>` for features, `fix/<short-kebab-case-name>` for regular fixes, `release/<version-or-name>` for release preparation, and `hotfix/<short-kebab-case-name>` for urgent production fixes.
- Reuse the repository's existing long-lived branches; do not introduce `develop` or another long-lived branch unless the repository already uses it or the user explicitly requests it.

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
- Node.js: bun, v24+.
- E2E: Use `playwright` instead of `chrome-devtools`.
- Python: `uv`.
