# Global Instructions

## Rules

- Keep the main thread's context clean.
  - **Skill**: For tasks requiring specialized knowledge, read the relevant skill's `SKILL.md` directly under that skill before starting work (for example, `skills/<name>/SKILL.md`), and apply its procedures and constraints exactly as written. Do not stop at merely declaring that you will use the skill.
  - **Subagent**: Route a side task through a subagent when it would otherwise flood the conversation with output nobody will reference again — long check output, CI logs, browser dumps, whole documentation pages — or when two or more independent edits can run in parallel. Keep work in the main thread when it needs back-and-forth, shares context across phases, or finishes in a handful of tool calls.

## Development Style

Develop with TDD (Exploration -> Red -> Green -> Refactoring).
If KPIs or coverage targets are provided, keep iterating until they are met.
Ask questions to clarify ambiguous instructions.

### Code Design

- Separate state from logic.
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
