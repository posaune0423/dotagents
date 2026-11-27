#!/usr/bin/env bash
# Contract for the shared subagent set: which agents exist, how Codex registers
# them, and which models they may pin. Agents inherit the parent model unless a
# lighter one is deliberate, so model upgrades happen in one place.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

names() { find "$1" -maxdepth 1 -name "*.$2" -exec basename {} ".$2" \; | sort | tr '\n' ' '; }

# Only agents that recent sessions actually spawn, with no duplicate roles.
expected_codex='architect docs-researcher evidence-analyst evidence-auditor explorer impl-worker light-worker pr-runner researcher reviewer '
expected_claude='docs-researcher impl-worker light-worker pr-runner researcher web-operator '
[[ "$(names "${ROOT}/codex/agents" toml)" == "${expected_codex}" ]] ||
	fail "unexpected Codex agents: $(names "${ROOT}/codex/agents" toml)"
[[ "$(names "${ROOT}/claude/agents" md)" == "${expected_claude}" ]] ||
	fail "unexpected Claude agents: $(names "${ROOT}/claude/agents" md)"

# Codex discovers agent files from $CODEX_HOME/agents on its own. Registering them
# again as [agents.*] in the same config layer makes Codex reject each role as a
# duplicate ("duplicate agent role name ... declared in the same config layer").
if rg -n '^\[agents\.[a-z-]+\]' "${ROOT}/codex/config.toml"; then
	fail "codex/config.toml must not register agent files that Codex auto-discovers"
fi

# Codex ignores an agent file without these keys ("malformed agent role definition"),
# and `personality` / `sandbox_mode` in an agent file have no effect.
for file in "${ROOT}"/codex/agents/*.toml; do
	for key in name description developer_instructions; do
		rg -q "^${key} = " "${file}" || fail "$(basename "${file}") must define ${key}"
	done
	if rg -q '^(personality|sandbox_mode) = ' "${file}"; then
		fail "$(basename "${file}") sets a key that agent files cannot override"
	fi
done

# Feature flags and keys the CLI has removed or deprecated must not come back.
removed_keys='^(personality|js_repl|js_repl_tools_only|realtime_conversation|remote_control|shell_zsh_fork|skill_env_var_dependency_prompt|tool_search|tool_search_always_defer_mcp_tools|unavailable_dummy_tools|undo|workspace_owner_usage_nudge|child_agents_md|multi_agent) = '
if rg -n "${removed_keys}" "${ROOT}/codex/config.toml"; then
	fail "codex/config.toml sets removed or deprecated keys"
fi

# Lightweight scans pin the fast model; everything else inherits the parent.
for agent in explorer light-worker docs-researcher researcher; do
	rg -Fxq 'model = "gpt-6-luna"' "${ROOT}/codex/agents/${agent}.toml" ||
		fail "${agent} must run on gpt-6-luna"
done
for agent in architect reviewer evidence-analyst evidence-auditor impl-worker pr-runner; do
	if rg -q '^model\s*=' "${ROOT}/codex/agents/${agent}.toml"; then
		fail "${agent} must inherit the parent model"
	fi
done

# Claude agents use aliases that track the newest model, and always state effort
# (a subagent on a different model does not inherit the session's effort).
for file in "${ROOT}"/claude/agents/*.md; do
	rg -q '^model: (opus|sonnet|haiku|fable|inherit)$' "${file}" || fail "$(basename "${file}") must use a model alias"
	rg -q '^effort: (low|medium|high|xhigh|max)$' "${file}" || fail "$(basename "${file}") must set effort"
done

# Read-only or command-running agents skip CLAUDE.md to save tokens on every spawn;
# agents that edit code keep it so they follow the target repository's conventions.
for agent in researcher docs-researcher web-operator light-worker; do
	rg -Fxq 'omitClaudeMd: true' "${ROOT}/claude/agents/${agent}.md" || fail "${agent} must set omitClaudeMd"
done
for agent in impl-worker pr-runner; do
	if rg -Fq 'omitClaudeMd' "${ROOT}/claude/agents/${agent}.md"; then
		fail "${agent} edits code and must load CLAUDE.md"
	fi
done

# Retired or legacy ids must not come back.
legacy='gpt-5\.|codex-spark|claude-(fable|opus|sonnet|haiku)-[0-9]'
if rg -n "${legacy}" "${ROOT}/codex/agents" "${ROOT}/codex/config.toml" "${ROOT}/claude/agents" "${ROOT}/claude/settings.json" "${ROOT}/claude/settings.template.json"; then
	fail "legacy model ids found"
fi

if rg -Fq 'default_subagent_model' "${ROOT}/codex/config.toml"; then
	fail 'Codex config must not override the model for unspecified subagents'
fi
if rg -Fq 'default_subagent_reasoning_effort' "${ROOT}/codex/config.toml"; then
	fail 'Codex config must not override the reasoning effort for unspecified subagents'
fi

echo "PASS: subagent set and model routing contract"
