#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GIT_COMMON_DIR="$(git -C "${ROOT}" rev-parse --path-format=absolute --git-common-dir)"
SOURCE_ROOT="$(dirname -- "${GIT_COMMON_DIR}")"
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

mkdir -p -- \
	"${TEST_HOME}/.agents/schedules" \
	"${TEST_HOME}/.codex/automations" \
	"${TEST_HOME}/.claude/agents" \
	"${TEST_HOME}/.claude/scheduled-tasks" \
	"${TEST_HOME}/.gemini"
printf '%s\n' "local-codex-config" >"${TEST_HOME}/.codex/config.toml"
printf '%s\n' "local-claude-settings" >"${TEST_HOME}/.claude/settings.json"
printf '%s\n' "previous-global-instructions" >"${TEST_HOME}/.codex/AGENTS.md"
printf '%s\n' "previous-agent" >"${TEST_HOME}/.claude/agents/local.md"
printf '%s\n' "local-shared-schedule" >"${TEST_HOME}/.agents/schedules/local.txt"
printf '%s\n' "local-codex-automation" >"${TEST_HOME}/.codex/automations/local.txt"
printf '%s\n' "local-claude-schedule" >"${TEST_HOME}/.claude/scheduled-tasks/local.txt"

HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --home --all --tool-links
HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --home --all --tool-links

assert_link "${TEST_HOME}/.agents/skills" "${SOURCE_ROOT}/skills"
assert_link "${TEST_HOME}/.agents/commands" "${SOURCE_ROOT}/commands"
assert_link "${TEST_HOME}/.agents/rules" "${SOURCE_ROOT}/rules"
assert_link "${TEST_HOME}/.codex/AGENTS.md" "${SOURCE_ROOT}/codex/AGENTS.md"
assert_link "${TEST_HOME}/.codex/agents" "${SOURCE_ROOT}/codex/agents"
assert_link "${TEST_HOME}/.codex/hooks" "${SOURCE_ROOT}/codex/hooks"
assert_link "${TEST_HOME}/.codex/hooks.json" "${SOURCE_ROOT}/codex/hooks.json"
assert_link "${TEST_HOME}/.claude/CLAUDE.md" "${SOURCE_ROOT}/claude/CLAUDE.md"
assert_link "${TEST_HOME}/.claude/agents" "${SOURCE_ROOT}/claude/agents"
assert_link "${TEST_HOME}/.claude/hooks" "${SOURCE_ROOT}/claude/hooks"
assert_link "${TEST_HOME}/.gemini/GEMINI.md" "${SOURCE_ROOT}/gemini/GEMINI.md"

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
[[ ! -L "${TEST_HOME}/.agents/schedules" ]] || fail "shared schedules must not be linked globally"
[[ "$(<"${TEST_HOME}/.agents/schedules/local.txt")" == "local-shared-schedule" ]] ||
	fail "global schedule state was modified"
[[ ! -L "${TEST_HOME}/.codex/automations" ]] || fail "Codex automations must stay home-local"
[[ "$(<"${TEST_HOME}/.codex/automations/local.txt")" == "local-codex-automation" ]] ||
	fail "Codex automation state was modified"
[[ ! -L "${TEST_HOME}/.claude/scheduled-tasks" ]] || fail "Claude schedules must stay home-local"
[[ "$(<"${TEST_HOME}/.claude/scheduled-tasks/local.txt")" == "local-claude-schedule" ]] ||
	fail "Claude schedule state was modified"

assert_link "${ROOT}/claude/CLAUDE.md" "../codex/AGENTS.md"
assert_link "${ROOT}/gemini/GEMINI.md" "../codex/AGENTS.md"

review_rc=0
jq -e '.env == {} and .remoteControlAtStartup == false' "${ROOT}/claude/settings.template.json" >/dev/null || {
	echo "FAIL: Claude settings template must be valid JSON with an empty env and opt-in Remote Control" >&2
	review_rc=1
}
jq -e '.remoteControlAtStartup == false' "${ROOT}/claude/settings.json" >/dev/null || {
	echo "FAIL: Claude reference settings must not start Remote Control automatically" >&2
	review_rc=1
}
jq -e '
	.hooks.UserPromptSubmit == [
		{
			"hooks": [
				{
					"type": "command",
					"command": "~/.codex/hooks/user_prompt_submit_proactive_context.sh"
				}
			]
		}
	]
' "${ROOT}/codex/hooks.json" >/dev/null || {
	echo "FAIL: Codex UserPromptSubmit hook must register the proactive-context command" >&2
	review_rc=1
}
rg -Fq 'links ~/.claude/agents -> <repo>/claude/agents;' "${ROOT}/claude/agents/architect.md" || {
	echo "FAIL: Claude architect example must document the home-to-repository link direction" >&2
	review_rc=1
}
rg -Fq 'Writes and file edits are unsupported, even when explicitly requested.' "${ROOT}/codex/agents/qwen_worker.toml" || {
	echo "FAIL: Qwen worker must document its read-only sandbox boundary" >&2
	review_rc=1
}
rg -Fq 'return `BLOCKED:`' "${ROOT}/codex/agents/qwen_worker.toml" || {
	echo "FAIL: Qwen worker must block tasks that require modifications" >&2
	review_rc=1
}
# Codex discovers a subagent only through its [agents.*] entry, so a TOML file
# added without one is silently unavailable.
for agent_toml in "${ROOT}"/codex/agents/*.toml; do
	agent_name="$(basename -- "${agent_toml}" .toml)"
	rg -Fq "[agents.${agent_name}]" "${ROOT}/codex/config.toml" || {
		echo "FAIL: Codex agent ${agent_name} is not registered in codex/config.toml" >&2
		review_rc=1
	}
done
[[ "${review_rc}" -eq 0 ]] || fail "review finding regressions detected"

HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --verify

ln -sfn -- "${TEST_ROOT}/wrong-target" "${TEST_HOME}/.gemini/GEMINI.md"
if HOME="${TEST_HOME}" bash "${ROOT}/scripts/link-dotagents.sh" --verify >/dev/null 2>&1; then
	fail "verification must reject a drifted managed link"
fi

HOME="${TEST_HOME}" bash "${ROOT}/scripts/relink-codex-prompts.sh"
assert_link "${TEST_HOME}/.codex/prompts" "${TEST_HOME}/.agents/commands"
assert_link "${TEST_HOME}/.codex/hooks" "${SOURCE_ROOT}/codex/hooks"
assert_link "${TEST_HOME}/.codex/hooks.json" "${SOURCE_ROOT}/codex/hooks.json"
assert_link "${TEST_HOME}/.claude/hooks" "${SOURCE_ROOT}/claude/hooks"

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
	"${FIXTURE_MAIN}/claude/hooks" \
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
	"${FIXTURE_MAIN}/claude/agents/.keep" \
	"${FIXTURE_MAIN}/claude/hooks/.keep"
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
assert_link "${WORKTREE_HOME}/.claude/hooks" "${FIXTURE_MAIN_CANONICAL}/claude/hooks"

echo "PASS: managed global agent links"
