#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
TEST_HOME="${TEST_ROOT}/home"

cleanup() {
	rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_link() {
	local path="$1"
	local expected="$2"

	[[ -L "${path}" ]] || fail "expected symlink: ${path}"
	[[ "$(readlink -- "${path}")" == "${expected}" ]] ||
		fail "unexpected target: ${path} -> $(readlink -- "${path}") (expected ${expected})"
}

mkdir -p -- "${TEST_HOME}/.codex" "${TEST_HOME}/.claude/agents" "${TEST_HOME}/.gemini"
printf '%s\n' "local-codex-config" >"${TEST_HOME}/.codex/config.toml"
printf '%s\n' "local-claude-settings" >"${TEST_HOME}/.claude/settings.json"
printf '%s\n' "previous-global-instructions" >"${TEST_HOME}/.codex/AGENTS.md"
printf '%s\n' "previous-agent" >"${TEST_HOME}/.claude/agents/local.md"

HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --home --all --tool-links
HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --home --all --tool-links

assert_link "${TEST_HOME}/.agents/skills" "${ROOT}/skills"
assert_link "${TEST_HOME}/.agents/commands" "${ROOT}/commands"
assert_link "${TEST_HOME}/.agents/rules" "${ROOT}/rules"
assert_link "${TEST_HOME}/.codex/AGENTS.md" "${ROOT}/codex/AGENTS.md"
assert_link "${TEST_HOME}/.codex/agents" "${ROOT}/codex/agents"
assert_link "${TEST_HOME}/.codex/hooks" "${ROOT}/codex/hooks"
assert_link "${TEST_HOME}/.codex/hooks.json" "${ROOT}/codex/hooks.json"
assert_link "${TEST_HOME}/.claude/CLAUDE.md" "${ROOT}/claude/CLAUDE.md"
assert_link "${TEST_HOME}/.claude/agents" "${ROOT}/claude/agents"
assert_link "${TEST_HOME}/.gemini/GEMINI.md" "${ROOT}/gemini/GEMINI.md"

shopt -s nullglob
codex_instruction_backups=("${TEST_HOME}/.codex/AGENTS.md.bak."*)
claude_agent_backups=("${TEST_HOME}/.claude/agents.bak."*)
shopt -u nullglob
[[ "${#codex_instruction_backups[@]}" -eq 1 ]] || fail "expected one Codex instruction backup"
[[ "$(<"${codex_instruction_backups[0]}")" == "previous-global-instructions" ]] ||
	fail "Codex instruction backup lost content"
[[ "${#claude_agent_backups[@]}" -eq 1 ]] || fail "expected one Claude agents backup"
[[ "$(<"${claude_agent_backups[0]}/local.md")" == "previous-agent" ]] ||
	fail "Claude agents backup lost content"

[[ ! -L "${TEST_HOME}/.codex/config.toml" ]] || fail "Codex config must stay home-local"
[[ "$(<"${TEST_HOME}/.codex/config.toml")" == "local-codex-config" ]] || fail "Codex config was modified"
[[ ! -L "${TEST_HOME}/.claude/settings.json" ]] || fail "Claude settings must stay home-local"
[[ "$(<"${TEST_HOME}/.claude/settings.json")" == "local-claude-settings" ]] || fail "Claude settings were modified"

assert_link "${ROOT}/claude/CLAUDE.md" "../codex/AGENTS.md"
assert_link "${ROOT}/gemini/GEMINI.md" "../codex/AGENTS.md"

HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --verify

ln -sfn -- "${TEST_ROOT}/wrong-target" "${TEST_HOME}/.gemini/GEMINI.md"
if HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --verify >/dev/null 2>&1; then
	fail "verification must reject a drifted managed link"
fi

HOME="${TEST_HOME}" bash "${ROOT}/scripts/relink-codex-prompts.sh"
assert_link "${TEST_HOME}/.codex/prompts" "${TEST_HOME}/.agents/commands"
assert_link "${TEST_HOME}/.codex/hooks" "${ROOT}/codex/hooks"
assert_link "${TEST_HOME}/.codex/hooks.json" "${ROOT}/codex/hooks.json"

FIXTURE_MAIN="${TEST_ROOT}/fixture-main"
FIXTURE_WORKTREE="${TEST_ROOT}/fixture-worktree"
WORKTREE_HOME="${TEST_ROOT}/worktree-home"
mkdir -p -- \
	"${FIXTURE_MAIN}/scripts" \
	"${FIXTURE_MAIN}/skills" \
	"${FIXTURE_MAIN}/commands" \
	"${FIXTURE_MAIN}/rules" \
	"${FIXTURE_MAIN}/codex/agents" \
	"${FIXTURE_MAIN}/codex/hooks" \
	"${FIXTURE_MAIN}/claude/agents" \
	"${FIXTURE_MAIN}/gemini"
cp -- "${ROOT}/scripts/link-dotagents.sh" "${FIXTURE_MAIN}/scripts/link-dotagents.sh"
printf '%s\n' "global" >"${FIXTURE_MAIN}/codex/AGENTS.md"
printf '%s\n' '{}' >"${FIXTURE_MAIN}/codex/hooks.json"
touch \
	"${FIXTURE_MAIN}/skills/.keep" \
	"${FIXTURE_MAIN}/commands/.keep" \
	"${FIXTURE_MAIN}/rules/.keep" \
	"${FIXTURE_MAIN}/codex/agents/.keep" \
	"${FIXTURE_MAIN}/codex/hooks/.keep" \
	"${FIXTURE_MAIN}/claude/agents/.keep"
ln -s ../codex/AGENTS.md "${FIXTURE_MAIN}/claude/CLAUDE.md"
ln -s ../codex/AGENTS.md "${FIXTURE_MAIN}/gemini/GEMINI.md"
git -C "${FIXTURE_MAIN}" init -q
git -C "${FIXTURE_MAIN}" add .
git -C "${FIXTURE_MAIN}" -c user.name=test -c user.email=test@example.com commit -qm fixture
git -C "${FIXTURE_MAIN}" worktree add -q --detach "${FIXTURE_WORKTREE}"
FIXTURE_MAIN_CANONICAL="$(cd "${FIXTURE_MAIN}" && pwd -P)"

HOME="${WORKTREE_HOME}" bash "${FIXTURE_WORKTREE}/scripts/link-dotagents.sh" --home --all --tool-links
assert_link "${WORKTREE_HOME}/.codex/AGENTS.md" "${FIXTURE_MAIN_CANONICAL}/codex/AGENTS.md"
assert_link "${WORKTREE_HOME}/.claude/agents" "${FIXTURE_MAIN_CANONICAL}/claude/agents"

echo "PASS: managed global agent links"
