#!/usr/bin/env bash
# Exercise the shared initializer without installing the skill into a project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/shared/skills/init-agent/scripts" "$TMP/project with spaces/.codex"
SCRIPT="$TMP/shared/skills/init-agent/scripts/init-agent.sh"
cp "$ROOT/skills/init-agent/scripts/init-agent.sh" "$SCRIPT"
repo="$TMP/project with spaces"
printf '# Project notes\n\nKeep this existing guidance.\n' >"$repo/AGENTS.md"
cp "$repo/AGENTS.md" "$TMP/expected-agents.md"
printf '# Existing tool configuration\n' >"$repo/.codex/config.toml"
cp "$repo/.codex/config.toml" "$TMP/expected-config.toml"

bash "$SCRIPT" "$repo"
for parent in .cursor .claude .codex; do
	for sub in skills commands rules; do
		[[ "$(readlink "$repo/$parent/$sub")" == "../.agents/$sub" ]]
		[[ -d "$repo/$parent/$sub" ]]
	done
done
[[ "$(readlink "$repo/CLAUDE.md")" == AGENTS.md ]]
[[ -f "$repo/CLAUDE.md" ]]
[[ ! -e "$repo/.agents/skills/init-agent" ]]
[[ ! -e "$TMP/shared/.codex" ]]
cmp "$repo/AGENTS.md" "$TMP/expected-agents.md"
cmp "$repo/.codex/config.toml" "$TMP/expected-config.toml"

# Running from the project root is also supported and leaves existing content intact.
(cd "$repo" && bash "$SCRIPT")
cmp "$repo/AGENTS.md" "$TMP/expected-agents.md"

# Refuse real files/directories and unexpected links rather than replacing them.
for conflict in directory symlink; do
	project="$TMP/$conflict"
	mkdir -p "$project/.cursor"
	cp "$TMP/expected-agents.md" "$project/AGENTS.md"
	if [[ "$conflict" == directory ]]; then
		mkdir "$project/.cursor/skills"
		printf 'keep\n' >"$project/.cursor/skills/existing"
	else
		ln -s missing-target "$project/.cursor/skills"
	fi
	if bash "$SCRIPT" "$project" >"$TMP/conflict.log" 2>&1; then
		echo "FAIL: accepted conflicting $conflict" >&2
		exit 1
	fi
	if [[ "$conflict" == directory ]]; then
		[[ "$(cat "$project/.cursor/skills/existing")" == keep ]]
	else
		[[ "$(readlink "$project/.cursor/skills")" == missing-target ]]
	fi
done

echo 'init-agent tests: passed'
