#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="${ROOT}/skills/evidence-work/scripts/eval.ts"
CASES="${ROOT}/skills/evidence-work/evals/cases.jsonl"
HOOK="${ROOT}/codex/hooks/user_prompt_submit_proactive_context.sh"
CODEX_CONFIG="${ROOT}/codex/config.toml"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[[ -f "${RUNNER}" ]] || fail "missing evidence-work eval runner"
[[ -f "${CASES}" ]] || fail "missing evidence-work eval cases"

HOOK_OUTPUT="$(printf '%s\n' '{"prompt":"test"}' | "${HOOK}")"
HOOK_CONTEXT="$(jq -r '.hookSpecificOutput.additionalContext' <<<"${HOOK_OUTPUT}")"
rg -Fq 'evidence-work' <<<"${HOOK_CONTEXT}" || fail "hook must route evidence-dependent knowledge work"
rg -Fq 'casual everyday questions' <<<"${HOOK_CONTEXT}" || fail "hook must preserve the direct path for casual questions"
if rg -Fqi 'use skills.*subagents proactively' <<<"${HOOK_CONTEXT}"; then
	fail "hook must not force proactive skill and subagent use globally"
fi

for agent in researcher evidence-analyst evidence-auditor; do
	rg -Fq "[agents.${agent}]" "${CODEX_CONFIG}" || fail "missing Codex registration for ${agent}"
	rg -Fq "config_file = \"agents/${agent}.toml\"" "${CODEX_CONFIG}" ||
		fail "wrong Codex config path for ${agent}"
	rg -Fq 'permissionMode: plan' "${ROOT}/claude/agents/${agent}.md" ||
		fail "Claude ${agent} must enforce plan permission mode"
	if rg -q '^tools:.*\bBash\b' "${ROOT}/claude/agents/${agent}.md"; then
		fail "Claude ${agent} must not expose unrestricted Bash"
	fi
done

JUST_LIST="$(just --list --unsorted)"
for recipe in test-evidence-work eval-evidence-work-smoke eval-evidence-work-full eval-evidence-work-forced eval-evidence-work-hook; do
	rg -Fq "${recipe}" <<<"${JUST_LIST}" || fail "missing just recipe ${recipe}"
done
rg -Fq 'just test-evidence-work' "${ROOT}/justfile" || fail "just check must include evidence-work regression tests"

SMOKE_PLAN="$(${RUNNER} --mode smoke --cases "${CASES}" --run-id test-smoke --dry-run)"
[[ "$(jq -r '.mode' <<<"${SMOKE_PLAN}")" == "smoke" ]] || fail "smoke plan mode mismatch"
[[ "$(jq -r '.case_count' <<<"${SMOKE_PLAN}")" == "8" ]] || fail "smoke must select 8 cases"
[[ "$(jq -r '.run_count' <<<"${SMOKE_PLAN}")" == "24" ]] || fail "smoke must plan 24 runs"
[[ "$(jq -r '[.runs[].arm] | unique | sort | join(",")' <<<"${SMOKE_PLAN}")" == "auto,control,forced" ]] ||
	fail "smoke must include control, auto, and forced arms"

CONTROL_CONFIG="$(jq -r '.runs[] | select(.arm == "control") | .skill_enabled' <<<"${SMOKE_PLAN}" | sort -u)"
[[ "${CONTROL_CONFIG}" == "false" ]] || fail "control arm must disable evidence-work"
jq -e 'all(.runs[] | select(.arm == "forced"); .prompt | startswith("Use $evidence-work.\n"))' \
	<<<"${SMOKE_PLAN}" >/dev/null || fail "forced arm must invoke evidence-work explicitly"
jq -e 'all(.runs[]; (.command_args | index("--ephemeral")) != null)' <<<"${SMOKE_PLAN}" >/dev/null ||
	fail "all runs must be ephemeral"
jq -e 'all(.runs[]; (.command_args | index("--json")) != null)' <<<"${SMOKE_PLAN}" >/dev/null ||
	fail "all runs must emit JSONL"
jq -e 'all(.runs[]; (.command_args | index("read-only")) != null)' <<<"${SMOKE_PLAN}" >/dev/null ||
	fail "all runs must use the read-only sandbox"
jq -e 'all(.runs[]; any(.command_args[]; . == "features.hooks=false"))' <<<"${SMOKE_PLAN}" >/dev/null ||
	fail "skill comparison must disable hooks in every arm"
jq -e 'all(.runs[] | select(.arm == "control"); any(.command_args[]; startswith("skills.config=")))' \
	<<<"${SMOKE_PLAN}" >/dev/null || fail "control must disable evidence-work through config"
jq -e 'all(.runs[] | select(.arm != "control"); all(.command_args[]; startswith("skills.config=") | not))' \
	<<<"${SMOKE_PLAN}" >/dev/null || fail "treatment arms must keep evidence-work enabled"
jq -e 'all(.runs[] | select(.web_access); (.command_args | index("--search")) != null)' \
	<<<"${SMOKE_PLAN}" >/dev/null || fail "web-enabled cases must expose search equally across arms"

FULL_PLAN="$(${RUNNER} --mode full --cases "${CASES}" --run-id test-full --dry-run)"
[[ "$(jq -r '.case_count' <<<"${FULL_PLAN}")" == "24" ]] || fail "full must select 24 cases"
[[ "$(jq -r '.run_count' <<<"${FULL_PLAN}")" == "144" ]] || fail "full must plan 144 runs"
[[ "$(jq -r '[.runs[].arm] | unique | sort | join(",")' <<<"${FULL_PLAN}")" == "auto,control" ]] ||
	fail "full must compare only control and auto before forced diagnostics"

HOOK_PLAN="$(${RUNNER} --mode hook --cases "${CASES}" --run-id test-hook --dry-run)"
[[ "$(jq -r '.case_count' <<<"${HOOK_PLAN}")" == "8" ]] || fail "hook comparison must use smoke cases"
[[ "$(jq -r '.run_count' <<<"${HOOK_PLAN}")" == "16" ]] || fail "hook comparison must plan 16 runs"
[[ "$(jq -r '[.runs[].arm] | unique | sort | join(",")' <<<"${HOOK_PLAN}")" == "auto,auto-hook" ]] ||
	fail "hook comparison must isolate auto and auto-hook"
jq -e 'all(.runs[] | select(.arm == "auto"); any(.command_args[]; . == "features.hooks=false"))' \
	<<<"${HOOK_PLAN}" >/dev/null || fail "auto hook-control arm must disable hooks"
jq -e 'all(.runs[] | select(.arm == "auto-hook"); any(.command_args[]; . == "features.hooks=true"))' \
	<<<"${HOOK_PLAN}" >/dev/null || fail "auto-hook arm must enable hooks"

TEST_ROOT="$(mktemp -d)"
cleanup() {
	rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

printf '%s\n' '{"id":"invalid"}' >"${TEST_ROOT}/invalid.jsonl"
if "${RUNNER}" --mode smoke --cases "${TEST_ROOT}/invalid.jsonl" --dry-run >/dev/null 2>&1; then
	fail "runner must reject incomplete eval cases"
fi

cat >"${TEST_ROOT}/fake-codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "debug" ]]; then
	if [[ " $* " == *'$evidence-work'* ]]; then
		echo 'preflight prompt leaked the skill marker' >&2
		exit 9
	fi
	if [[ " $* " == *" skills.config="* ]]; then
		echo '{"skills":[]}'
	else
		echo '{"skills":["evidence-work"]}'
	fi
	exit 0
fi

output_file=""
prompt=""
for ((index = 1; index <= $#; index++)); do
	value="${!index}"
	if [[ "${value}" == "-o" ]]; then
		next=$((index + 1))
		output_file="${!next}"
	fi
	prompt="${value}"
done

mkdir -p -- "$(dirname "${output_file}")"
printf 'Answer for: %s\n' "${prompt}" >"${output_file}"
echo '{"type":"thread.started","thread_id":"fake-thread"}'
printf '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Answer for fake run"}}\n'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":5}}'
SH
chmod +x "${TEST_ROOT}/fake-codex"

cat >"${TEST_ROOT}/one-case.jsonl" <<'JSONL'
{"id":"one","category":"direct","prompt":"Explain a specialist concept","cwd":".","read_roots":[],"expected_mode":"direct","web_access":false,"required_context":["mechanism"],"success_criteria":["Explains the mechanism"],"forbidden_claims":[],"critical_failure_conditions":[],"privacy_class":"sanitized","smoke":true}
JSONL

sed 's/"privacy_class":"sanitized"/"privacy_class":"private"/' \
	"${TEST_ROOT}/one-case.jsonl" >"${TEST_ROOT}/private-in-public.jsonl"
sed \
	-e 's/"id":"one"/"id":"secret"/' \
	-e 's/Explain a specialist concept/TOP SECRET PRIVATE PROMPT/' \
	-e 's/"privacy_class":"sanitized"/"privacy_class":"private"/' \
	"${TEST_ROOT}/one-case.jsonl" >"${TEST_ROOT}/private-case.jsonl"
if "${RUNNER}" --mode smoke --cases "${TEST_ROOT}/private-in-public.jsonl" --dry-run >/dev/null 2>&1; then
	fail "versioned cases input must reject private fixtures"
fi
if "${RUNNER}" \
	--mode smoke \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--private-cases "${TEST_ROOT}/one-case.jsonl" \
	--dry-run >/dev/null 2>&1; then
	fail "private cases input must reject sanitized fixtures"
fi
if "${RUNNER}" \
	--mode smoke \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--private-cases "${TEST_ROOT}/private-in-public.jsonl" \
	--dry-run >/dev/null 2>&1; then
	fail "public and private cases must not reuse ids"
fi

PRIVATE_PLAN="$(${RUNNER} \
	--mode smoke \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--private-cases "${TEST_ROOT}/private-case.jsonl" \
	--run-id private-plan \
	--dry-run)"
if rg -Fq 'TOP SECRET PRIVATE PROMPT' <<<"${PRIVATE_PLAN}"; then
	fail "dry-run output must redact private prompts"
fi

SELECTED_PRIVATE_PLAN="$(${RUNNER} \
	--mode smoke \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--private-cases "${TEST_ROOT}/private-case.jsonl" \
	--case-ids secret \
	--run-id selected-private-plan \
	--dry-run)"
[[ "$(jq -r '.case_count' <<<"${SELECTED_PRIVATE_PLAN}")" == "1" ]] ||
	fail "case id filter must select one private case"
[[ "$(jq -r '.run_count' <<<"${SELECTED_PRIVATE_PLAN}")" == "3" ]] ||
	fail "selected smoke case must keep all three arms"
[[ "$(jq -r '[.runs[].case_id] | unique | join(",")' <<<"${SELECTED_PRIVATE_PLAN}")" == "secret" ]] ||
	fail "case id filter selected the wrong case"
if "${RUNNER}" \
	--mode smoke \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--case-ids missing \
	--dry-run >/dev/null 2>&1; then
	fail "runner must reject unknown case ids"
fi

"${RUNNER}" \
	--mode smoke \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--run-id live-test \
	--out-dir "${TEST_ROOT}/out" \
	--codex-bin "${TEST_ROOT}/fake-codex" >/dev/null

"${RUNNER}" \
	--mode forced \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--forced-cases one \
	--run-id forced-live \
	--out-dir "${TEST_ROOT}/out" \
	--codex-bin "${TEST_ROOT}/fake-codex" >/dev/null

"${RUNNER}" \
	--mode smoke \
	--cases "${TEST_ROOT}/one-case.jsonl" \
	--private-cases "${TEST_ROOT}/private-case.jsonl" \
	--run-id private-live \
	--out-dir "${TEST_ROOT}/out" \
	--codex-bin "${TEST_ROOT}/fake-codex" >/dev/null

PRIVATE_ROOT="${TEST_ROOT}/out/private-live"
if rg -Fq 'TOP SECRET PRIVATE PROMPT' "${PRIVATE_ROOT}/plan.json" "${PRIVATE_ROOT}/comparison.md"; then
	fail "reports must redact private prompts"
fi
if fd -t f '^metadata.json$' "${PRIVATE_ROOT}/runs" -X rg -Fq 'TOP SECRET PRIVATE PROMPT'; then
	fail "metadata must redact private prompts"
fi
rg -Fq '/data/' "${ROOT}/.gitignore" || fail "evaluation output directory must remain gitignored"

RUN_ROOT="${TEST_ROOT}/out/live-test"
[[ "$(fd -t f '^metadata.json$' "${RUN_ROOT}/runs" | wc -l | tr -d ' ')" == "3" ]] ||
	fail "live smoke must write metadata for three arms"
[[ "$(fd -t f '^events.jsonl$' "${RUN_ROOT}/runs" | wc -l | tr -d ' ')" == "3" ]] ||
	fail "live smoke must preserve raw events for three arms"
[[ -f "${RUN_ROOT}/comparison.md" ]] || fail "missing blind comparison report"
[[ -f "${RUN_ROOT}/ratings.jsonl" ]] || fail "missing ratings template"
[[ -f "${RUN_ROOT}/arm-key.json" ]] || fail "missing arm key"
[[ -f "${RUN_ROOT}/summary.json" ]] || fail "missing run summary"
[[ "$(jq -r '.execution.completed' "${RUN_ROOT}/summary.json")" == "3" ]] || fail "summary completed count mismatch"
rg -q '^## Candidate [A-C]$' "${RUN_ROOT}/comparison.md" || fail "comparison must use blinded candidate labels"
for heading in 'Expected mode:' 'Required context:' 'Forbidden claims:' 'Critical failure conditions:'; do
	rg -Fq "${heading}" "${RUN_ROOT}/comparison.md" || fail "comparison missing rating contract: ${heading}"
done
if rg -qi 'control|forced|auto' "${RUN_ROOT}/comparison.md"; then
	fail "comparison report must not reveal arm names"
fi

AUTO_LABEL="$(jq -r '.["one:r1"] | to_entries[] | select(.value == "auto") | .key' "${RUN_ROOT}/arm-key.json")"
jq -e '(.candidate_scores | keys | sort) == (.candidate_labels | sort)' "${RUN_ROOT}/ratings.jsonl" >/dev/null ||
	fail "ratings must score every blinded candidate separately"
jq -c \
	--arg label "${AUTO_LABEL}" \
	'.candidate_scores |= with_entries(
	  .value.target_specific = true
	  | .value.facts_supported_or_qualified = true
	  | .value.claim_types_separated = true
	  | .value.answers_actual_question = true
	  | .value.avoids_generic_padding = true
	  | .value.quality_justifies_cost = true
	  | .value.critical_failure = false
	  | .value.notes = ""
	)
	| .overall_preference = $label
	| .notes = ""' \
	"${RUN_ROOT}/ratings.jsonl" >"${RUN_ROOT}/ratings.updated.jsonl"
mv -- "${RUN_ROOT}/ratings.updated.jsonl" "${RUN_ROOT}/ratings.jsonl"

"${RUNNER}" --summarize-run "${RUN_ROOT}" >/dev/null
[[ "$(jq -r '.ratings_status' "${RUN_ROOT}/summary.json")" == "complete" ]] || fail "ratings must summarize"
[[ "$(jq -r '.human_ratings.comparisons' "${RUN_ROOT}/summary.json")" == "1" ]] ||
	fail "human ratings comparison count mismatch"
[[ "$(jq -r '.human_ratings.preference_by_arm.auto' "${RUN_ROOT}/summary.json")" == "1" ]] ||
	fail "human preference must decode through the private arm key"
[[ "$(jq -r '.human_ratings.critical_failures_by_arm.auto' "${RUN_ROOT}/summary.json")" == "0" ]] ||
	fail "critical failure count mismatch for auto"
[[ "$(jq -r '.human_ratings.auto_vs_control.preference_rate' "${RUN_ROOT}/summary.json")" == "1" ]] ||
	fail "auto preference rate mismatch"
[[ "$(jq -r '.human_ratings.auto_vs_control.loss_rate' "${RUN_ROOT}/summary.json")" == "0" ]] ||
	fail "auto loss rate mismatch"

jq -c 'del(.candidate_scores[.candidate_labels[0]])' \
	"${RUN_ROOT}/ratings.jsonl" >"${RUN_ROOT}/ratings.incomplete.jsonl"
mv -- "${RUN_ROOT}/ratings.incomplete.jsonl" "${RUN_ROOT}/ratings.jsonl"
"${RUNNER}" --summarize-run "${RUN_ROOT}" >/dev/null
[[ "$(jq -r '.ratings_status' "${RUN_ROOT}/summary.json")" == "partial" ]] ||
	fail "missing candidate ratings must not be marked complete"

echo "PASS: evidence-work eval planning"
