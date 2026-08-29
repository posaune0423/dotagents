#!/usr/bin/env bash
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

echo "PASS: Codex agent model routing contract"
