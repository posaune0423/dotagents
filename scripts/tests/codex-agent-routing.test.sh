#!/usr/bin/env bash
# shellcheck disable=SC2016 # Markdown backticks below are intentional literals.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	local file="$1"
	local expected="$2"
	local message="$3"

	rg -Fq -- "${expected}" "${file}" || fail "${message}"
}

assert_not_contains() {
	local file="$1"
	local unexpected="$2"
	local message="$3"

	if rg -Fq -- "${unexpected}" "${file}"; then
		fail "${message}"
	fi
}

for agent in light-worker explorer monitor docs-researcher; do
	assert_contains \
		"${ROOT}/codex/agents/${agent}.toml" \
		'model = "gpt-5.3-codex-spark"' \
		"${agent} must remain routed to GPT-5.3-Codex-Spark"
done

assert_not_contains \
	"${ROOT}/codex/config.toml" \
	'default_subagent_model' \
	'Codex config must not override the model for unspecified subagents'
assert_not_contains \
	"${ROOT}/codex/config.toml" \
	'default_subagent_reasoning_effort' \
	'Codex config must not override the reasoning effort for unspecified subagents'

assert_contains \
	"${ROOT}/codex/AGENTS-ja.md" \
	'`light-worker`をspawnするときは`fork_turns="none"`を既定とし、必要な直近contextだけが不可欠な場合に限り必要最小限の正整数を使う。`fork_turns="all"`は使わない。' \
	'Japanese source must require bounded history for light-worker'
assert_contains \
	"${ROOT}/codex/AGENTS-ja.md" \
	'目的、作業directory、対象file・command、変更可否、完了条件' \
	'Japanese source must require a self-contained light-worker brief'

assert_contains \
	"${ROOT}/codex/AGENTS.md" \
	'When spawning `light-worker`, default to `fork_turns="none"`; use the smallest positive integer only when recent context is essential. Never use `fork_turns="all"`.' \
	'English runtime instructions must require bounded history for light-worker'
assert_contains \
	"${ROOT}/codex/AGENTS.md" \
	'objective, working directory, exact files or commands, whether edits are allowed, and acceptance criteria' \
	'English runtime instructions must require a self-contained light-worker brief'

echo "PASS: Codex agent model routing contract"
