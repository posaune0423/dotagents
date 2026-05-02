#!/usr/bin/env bash
# UserPromptSubmit: append proactive Skill/Subagent instructions as developer context.
set -euo pipefail

# Consume hook JSON from stdin (prompt, cwd, etc.); keep for future conditional logic.
cat >/dev/null || true

# Use `read <<EOF` (not `$(cat <<EOF)`) so apostrophes in the text are safe on Bash 3.2 (macOS).
read -r -d '' ADDITIONAL_CONTEXT <<'EOF' || true
[Skill / Subagent] Use Skills (read that skill's SKILL.md first; follow it—do not only declare use) and Subagents (isolated context, refactors/reviews/wide search, parallelism).
EOF

jq -n \
	--arg ctx "$ADDITIONAL_CONTEXT" \
	'{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
