#!/usr/bin/env bash
# Static contract for skill discovery metadata.
#
# Codex and Claude Code load every skill's name and description into the model
# context before any skill is used, and both shorten or drop descriptions once
# the listing exceeds a budget (Codex: about 8,000 characters). The checks
# below keep the shared skills inside that budget and inside the Agent Skills
# frontmatter contract so a skill is never silently truncated or rejected.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Skills vendored from other repositories keep their upstream description; the
# repository-owned ones are held to a tighter cap.
VENDORED="defuddle json-canvas obsidian-bases obsidian-cli obsidian-markdown shadcn find-skills playwright-cli mermaid-er-diagram"
OWNED_MAX=300
VENDORED_MAX=1024
TOTAL_MAX=8000

# Agent Skills spec fields plus the Claude Code specific fields that Codex
# tolerates. Anything else is a typo or a field no runtime reads.
ALLOWED_KEYS="name description license compatibility metadata allowed-tools disallowed-tools when_to_use argument-hint arguments disable-model-invocation user-invocable paths context agent model effort background hooks shell"

status=0
total=0

fail() {
	echo "FAIL: $*" >&2
	status=1
}

frontmatter() {
	awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{exit} NR>1' "$1"
}

description_of() {
	# Handles single-line values and `>` / `>-` / `|` block scalars.
	frontmatter "$1" | awk '
		/^description:/ {
			p=1
			sub(/^description:[ ]*/, "")
			if ($0 ~ /^[>|]-?[ ]*$/) { next }
			print; next
		}
		p && /^[A-Za-z_-]+:/ { p=0 }
		p { sub(/^[ ]+/, ""); print }
	' | tr -s ' \n' ' ' | sed -e 's/^ //' -e 's/ $//' -e 's/^"//' -e 's/"$//'
}

top_level_keys() {
	frontmatter "$1" | awk '/^[A-Za-z_-]+:/ { sub(/:.*/, ""); print }'
}

is_vendored() {
	local name
	for name in $VENDORED; do
		[[ "$name" == "$1" ]] && return 0
	done
	return 1
}

for dir in "${ROOT}"/skills/*/ "${ROOT}"/schedules/*/; do
	skill="${dir%/}"
	name="$(basename "$skill")"
	file="${skill}/SKILL.md"
	[[ -f "$file" ]] || continue
	# Machine-local skills are not part of the shared contract.
	git -C "$ROOT" ls-files --error-unmatch "$file" >/dev/null 2>&1 || continue

	if ! frontmatter "$file" >/dev/null; then
		fail "${name}: SKILL.md must start with YAML frontmatter"
		continue
	fi

	declared="$(frontmatter "$file" | awk '/^name:/ { sub(/^name:[ ]*/, ""); print; exit }')"
	[[ "$declared" == "$name" ]] || fail "${name}: frontmatter name '${declared}' must match the directory name"

	while IFS= read -r key; do
		[[ -n "$key" ]] || continue
		case " ${ALLOWED_KEYS} " in
		*" ${key} "*) ;;
		*) fail "${name}: unsupported frontmatter key '${key}'" ;;
		esac
	done <<<"$(top_level_keys "$file")"

	desc="$(description_of "$file")"
	[[ -n "$desc" ]] || fail "${name}: description is required"
	case "$desc" in
	*"<"* | *">"*) fail "${name}: description must not contain angle brackets" ;;
	esac

	len=${#desc}
	total=$((total + len))
	if is_vendored "$name"; then
		max=$VENDORED_MAX
	else
		max=$OWNED_MAX
	fi
	[[ "$len" -le "$max" ]] || fail "${name}: description is ${len} chars; keep it under ${max} so the listing is never shortened"
done

[[ "$total" -le "$TOTAL_MAX" ]] || fail "combined skill descriptions are ${total} chars; Codex starts shortening the listing above ${TOTAL_MAX}"

[[ "$status" -eq 0 ]] && echo "PASS: skill frontmatter contract (${total} description chars)"
exit "$status"
