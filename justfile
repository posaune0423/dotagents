set shell := ["bash", "-cu"]

# List recipes (default)
default:
    @just --list

# Symlink dotagents -> ~/.agents (global); ~/.claude/CLAUDE.md and ~/.gemini/GEMINI.md only
link-global:
    ./scripts/link-dotagents.sh --home --all --tool-configs

# Remove ~/.codex/commands and symlink ~/.codex/prompts -> ~/.agents/commands
link-codex-prompts:
    ./scripts/relink-codex-prompts.sh

# Setup <project>/.agents and link .cursor/.codex/.claude (pass project path)
link-project target:
    ./scripts/link-project-agents.sh --target "{{target}}"

# Basic verification that SKILL.md is visible (pass project path)
verify-project target:
    ./scripts/verify-project-links.sh --target "{{target}}"

# Legacy: rsync dotagents -> <project>/.agents (pass project path)
install target:
    ./scripts/sync-agents.sh --target "{{target}}"

# --- dev (delegates to package.json / bun) ---

prepare:
    bun run prepare

format:
    bun run format

lint:
    bun run lint

check:
    bun run check
