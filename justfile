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

# Validate the default and role-specific Codex subagent model configuration
test-agent-routing:
    ./scripts/tests/codex-agent-routing.test.sh

# Validate skill frontmatter: allowed keys, name/dir match, and description budget
test-skills:
    ./scripts/tests/skills-frontmatter.test.sh

# Validate provider-neutral scheduled-task definitions
test-schedules:
    ./scripts/tests/schedules.test.sh

# Integration tests for destructive-boundary checks in worktree cleanup
test-cleanup:
    ./scripts/tests/safe-dev-storage-cleanup.test.sh

# Integration tests for the Claude Code hook scripts in claude/hooks
test-hooks:
    ./scripts/tests/hooks.test.sh

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
    bun run check && just test-skills && just test-schedules && just test-cleanup && just test-hooks && just test-agent-routing && just test-evidence-work

# Validate evidence-work routing and the A/B evaluation harness without model calls
test-evidence-work:
	./scripts/tests/evidence-work-eval.test.sh

# Compare control, automatic routing, and explicit invocation on the 8-case smoke set
eval-evidence-work-smoke *args:
	./skills/evidence-work/scripts/eval.ts --mode smoke {{args}}

# Compare control and automatic routing across the full set with three repetitions
eval-evidence-work-full *args:
	./skills/evidence-work/scripts/eval.ts --mode full {{args}}

# Diagnose selected routing failures by forcing evidence-work for comma-separated case ids
eval-evidence-work-forced case_ids *args:
	./skills/evidence-work/scripts/eval.ts --mode forced --forced-cases "{{case_ids}}" {{args}}

# Measure the routing backstop separately after the skill itself passes smoke evaluation
eval-evidence-work-hook *args:
	./skills/evidence-work/scripts/eval.ts --mode hook {{args}}
