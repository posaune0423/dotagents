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

for agent in light-worker explorer monitor docs-researcher; do
	assert_contains \
		"${ROOT}/codex/agents/${agent}.toml" \
		'model = "gpt-5.3-codex-spark"' \
		"${agent} must remain routed to GPT-5.3-Codex-Spark"
done

assert_contains \
	"${ROOT}/codex/config.toml" \
	'default_subagent_model = "gpt-5.3-codex-spark"' \
	'Codex config must default unspecified subagents to GPT-5.3-Codex-Spark'
assert_contains \
	"${ROOT}/codex/config.toml" \
	'default_subagent_reasoning_effort = "medium"' \
	'Codex config must define the default subagent reasoning effort'

echo "PASS: Codex agent model routing contract"
