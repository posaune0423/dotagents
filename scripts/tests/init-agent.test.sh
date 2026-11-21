#!/usr/bin/env bash
# Exercise the shared initializer without installing the skill into a project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/shared/skills" "$TMP/project with spaces/.codex"
cp -R "$ROOT/skills/init-agent" "$TMP/shared/skills/init-agent"
SCRIPT="$TMP/shared/skills/init-agent/scripts/init-agent.sh"
SCAFFOLD=(AGENTS.md docs/PRD.md docs/STRUCTURE.md docs/TECHNOLOGY.md docs/specs/ph01.md)

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_links() {
	local repo="$1"
	for parent in .cursor .claude .codex; do
		for sub in skills commands rules; do
			[[ "$(readlink "$repo/$parent/$sub")" == "../.agents/$sub" ]] || fail "$parent/$sub link in $repo"
			[[ -d "$repo/$parent/$sub" ]] || fail "$parent/$sub does not resolve in $repo"
		done
	done
	[[ "$(readlink "$repo/CLAUDE.md")" == AGENTS.md && -f "$repo/CLAUDE.md" ]] || fail "CLAUDE.md link in $repo"
}

# Existing project: keep its AGENTS.md and tool config, add only the missing scaffold.
repo="$TMP/project with spaces"
printf '# Project notes\n\nKeep this existing guidance.\n' >"$repo/AGENTS.md"
cp "$repo/AGENTS.md" "$TMP/expected-agents.md"
printf '# Existing tool configuration\n' >"$repo/.codex/config.toml"
cp "$repo/.codex/config.toml" "$TMP/expected-config.toml"
mkdir -p "$repo/docs"
printf '# Our PRD\n' >"$repo/docs/PRD.md"

bash "$SCRIPT" "$repo"
assert_links "$repo"
[[ ! -e "$repo/.agents/skills/init-agent" ]] || fail "skill was copied into the project"
[[ ! -e "$TMP/shared/.codex" ]] || fail "links were created next to the skill"
cmp -s "$repo/AGENTS.md" "$TMP/expected-agents.md" || fail "existing AGENTS.md was changed"
cmp -s "$repo/.codex/config.toml" "$TMP/expected-config.toml" || fail "existing tool config was changed"
[[ "$(cat "$repo/docs/PRD.md")" == '# Our PRD' ]] || fail "existing docs/PRD.md was changed"
for file in docs/STRUCTURE.md docs/TECHNOLOGY.md docs/specs/ph01.md; do
	cmp -s "$repo/$file" "$TMP/shared/skills/init-agent/assets/templates/$file" || fail "$file was not scaffolded from its template"
done

# Running again from the project root changes nothing.
snapshot() { (cd "$1" && find . -path ./.git -prune -o -print0 | sort -z | xargs -0 ls -ld | awk '{print $1, $NF}'); }
before="$(snapshot "$repo")"
(cd "$repo" && bash "$SCRIPT") >"$TMP/rerun.log"
[[ "$(snapshot "$repo")" == "$before" ]] || fail "second run changed the project"
if rg -q '^created:' "$TMP/rerun.log"; then fail "second run reported new files"; fi

# New project: generate the Orca-style AGENTS.md base and every doc template.
fresh="$TMP/fresh"
mkdir -p "$fresh"
bash "$SCRIPT" "$fresh" >/dev/null
assert_links "$fresh"
for file in "${SCAFFOLD[@]}"; do
	cmp -s "$fresh/$file" "$TMP/shared/skills/init-agent/assets/templates/$file" || fail "$file missing in a new project"
done
for heading in '# Checks' '# Repo Rules' '# Docs' '# Code Style' '# First Class Citizens' '# Footguns'; do
	rg -Fxq "$heading" "$fresh/AGENTS.md" || fail "AGENTS.md base lacks '$heading'"
done

# --links-only skips the scaffold, so a project without AGENTS.md is refused.
bare="$TMP/bare"
mkdir -p "$bare"
if bash "$SCRIPT" --links-only "$bare" >"$TMP/bare.log" 2>&1; then fail "--links-only accepted a project without AGENTS.md"; fi
[[ ! -e "$bare/docs" ]] || fail "--links-only created docs/"

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
		fail "accepted conflicting $conflict"
	fi
	if [[ "$conflict" == directory ]]; then
		[[ "$(cat "$project/.cursor/skills/existing")" == keep ]] || fail "conflicting directory was modified"
	else
		[[ "$(readlink "$project/.cursor/skills")" == missing-target ]] || fail "conflicting symlink was modified"
	fi
done

echo 'init-agent tests: passed'
