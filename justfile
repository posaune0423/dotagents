set shell := ["bash", "-cu"]

# List recipes (default)
default:
    @just --list

# Link shared assets plus managed Codex, Claude, and Gemini entries into home directories
link-global:
    ./scripts/link-dotagents.sh --home --all --tool-links

# Read-only check that the global symlinks from link-global are intact
verify-global:
    ./scripts/link-dotagents.sh --verify

# Integration tests for global link topology and home-local config preservation
test-links:
    ./scripts/tests/link-dotagents.test.sh

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

# Nix の devShell に入ったあと、初回だけ。`bun install` が package.json の prepare（lefthook）まで実行する。一発なら: nix run .#setup
bootstrap:
    bun install

prepare:
    bun run prepare

format:
    bun run format

lint:
    bun run lint

check:
    bun run check
