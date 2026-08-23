#!/usr/bin/env bash
# UserPromptSubmit: append a small evidence-work routing backstop as developer context.
set -euo pipefail

# Consume hook JSON from stdin. Semantic routing stays with the model and skill description;
# brittle shell keyword classification is intentionally avoided.
cat >/dev/null || true

# Use `read <<EOF` (not `$(cat <<EOF)`) so apostrophes in the text are safe on Bash 3.2 (macOS).
read -r -d '' ADDITIONAL_CONTEXT <<'EOF' || true
[Evidence work routing] Consider $evidence-work only when a non-implementation request depends on specialist, current, target-specific, or user-specific evidence. Keep casual everyday questions on the direct path. If the skill applies, let its selected mode decide whether bounded read-only subagents add enough value; do not delegate merely to appear thorough.
EOF

jq -n \
	--arg ctx "$ADDITIONAL_CONTEXT" \
	'{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
