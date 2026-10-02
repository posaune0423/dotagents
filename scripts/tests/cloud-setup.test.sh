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

mkdir -p -- "${TEST_HOME}/.claude"
printf '%s\n' '{"model": "cloud-default", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "true"}]}]}}' \
	>"${TEST_HOME}/.claude/settings.json"

HOME="${TEST_HOME}" bash "${ROOT}/scripts/cloud-setup.sh" >/dev/null
HOME="${TEST_HOME}" bash "${ROOT}/scripts/cloud-setup.sh" >/dev/null

# Claude Code reads user skills, commands, and rules only from ~/.claude, so the
# ~/.agents assets must be reachable from there exactly as on a local machine.
for kind in skills commands rules; do
	[[ "$(cd "${TEST_HOME}/.claude/${kind}" && pwd -P)" == "$(cd "${SOURCE_ROOT}/${kind}" && pwd -P)" ]] ||
		fail "${TEST_HOME}/.claude/${kind} does not resolve to ${SOURCE_ROOT}/${kind}"
done
[[ -f "${TEST_HOME}/.claude/skills/tdd/SKILL.md" ]] || fail "a tracked skill is not visible under ~/.claude/skills"
[[ -f "${TEST_HOME}/.claude/CLAUDE.md" ]] || fail "global instructions are not linked"
[[ -f "${TEST_HOME}/.claude/agents/light-worker.md" ]] || fail "subagents are not linked"

settings="${TEST_HOME}/.claude/settings.json"
jq -e '.model == "cloud-default"' "${settings}" >/dev/null || fail "existing settings were not preserved"
jq -e '.hooks.Stop | length == 1' "${settings}" >/dev/null || fail "existing hooks were not preserved"
jq -e '
	[.hooks.SessionStart[].hooks[].command | select(test("cloud-setup\\.sh\"? --refresh$"))] | length == 1
' "${settings}" >/dev/null || fail "the refresh hook must be registered exactly once across runs"

echo "PASS: cloud setup"
