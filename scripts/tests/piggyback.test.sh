#!/usr/bin/env bash
# Integration tests for the piggyback router, its provider-adapter contract,
# and the piggyback-worker subagent definitions shared by Claude Code and Codex.
# shellcheck disable=SC2016,SC2028 # The stub bodies below are literal scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="${ROOT}/skills/piggyback"
ROUTER="${SKILL_DIR}/scripts/piggyback.sh"
PROVIDERS="${SKILL_DIR}/scripts/providers"

pass=0
fail=0

fail_msg() {
	echo "FAIL: $*" >&2
	fail=$((fail + 1))
}

ok() { pass=$((pass + 1)); }

WORKDIR="$(mktemp -d)"
STUB_DIR="${WORKDIR}/providers"
STATE_DIR="${WORKDIR}/state"
mkdir -p "${STUB_DIR}" "${STATE_DIR}"
trap 'rm -rf "${WORKDIR}"' EXIT

# Build a stub adapter that honours the same three-verb contract as a real one.
# Routing is tested through the real router so the test cannot drift from it.
make_adapter() {
	local name="$1" capability="$2" run_exit="$3" answer="$4"
	local path="${STUB_DIR}/${name}.sh"

	cat >"${path}" <<STUB
#!/usr/bin/env bash
case "\$1" in
capabilities) echo '${capability}' ;;
probe)
	printf '%s\n' "\$@" >>"\${ADAPTER_PROBE_LOG:-/dev/null}"
	exit ${run_exit}
	;;
run)
	echo "${name}" >>"\${ADAPTER_CALL_LOG:-/dev/null}"
	printf '%s\n' "\$@" >>"\${ADAPTER_ARGS_LOG:-/dev/null}"
	if [ ${run_exit} -eq 0 ]; then
		printf '%s\n' '${answer}'
	else
		echo '${name} unavailable' >&2
	fi
	exit ${run_exit}
	;;
esac
STUB
	chmod +x "${path}"
}

route() {
	ADAPTER_CALL_LOG="${WORKDIR}/calls.log" \
		ADAPTER_ARGS_LOG="${WORKDIR}/args.log" \
		ADAPTER_PROBE_LOG="${WORKDIR}/probe.log" \
		PIGGYBACK_PROVIDER_DIR="${STUB_DIR}" \
		PIGGYBACK_STATE_DIR="${STATE_DIR}" \
		bash "${ROUTER}" "$@"
}

assert_exit() {
	local expected="$1" label="$2"
	shift 2
	local rc=0
	"$@" >"${WORKDIR}/out.txt" 2>"${WORKDIR}/err.txt" || rc=$?
	if [[ "${rc}" != "${expected}" ]]; then
		fail_msg "${label}: expected exit ${expected}, got ${rc}"
		return
	fi
	ok
}

assert_out() {
	local expected="$1" label="$2"
	if ! grep -Fq -- "${expected}" "${WORKDIR}/out.txt"; then
		fail_msg "${label}: stdout missing '${expected}' (got: $(head -c 200 "${WORKDIR}/out.txt"))"
		return
	fi
	ok
}

assert_err() {
	local expected="$1" label="$2"
	if ! grep -Fq -- "${expected}" "${WORKDIR}/err.txt"; then
		fail_msg "${label}: stderr missing '${expected}'"
		return
	fi
	ok
}

assert_called() {
	local expected="$1" label="$2"
	if ! grep -Fxq -- "${expected}" "${WORKDIR}/calls.log"; then
		fail_msg "${label}: ${expected} was never invoked"
		return
	fi
	ok
}

assert_not_called() {
	local unexpected="$1" label="$2"
	if grep -Fxq -- "${unexpected}" "${WORKDIR}/calls.log"; then
		fail_msg "${label}: ${unexpected} must not have been invoked"
		return
	fi
	ok
}

assert_file_contains() {
	local file="$1" expected="$2" label="$3"
	if [[ ! -f "${file}" ]]; then
		fail_msg "${label}: missing file ${file}"
		return
	fi
	if ! grep -Fq -- "${expected}" "${file}"; then
		fail_msg "${label}: ${file} missing '${expected}'"
		return
	fi
	ok
}

reset_run() {
	: >"${WORKDIR}/calls.log"
	: >"${WORKDIR}/args.log"
	: >"${WORKDIR}/probe.log"
	rm -f "${STATE_DIR}"/*.cooldown 2>/dev/null || true
}

[[ -x "${ROUTER}" ]] || {
	echo "FAIL: router is missing or not executable: ${ROUTER}" >&2
	exit 1
}

# 3 = quota, 4 = auth, 5 = missing, 1 = failed
make_adapter dead-quota inference 3 ''
make_adapter dead-auth inference 4 ''
make_adapter good-inference inference 0 'INFERENCE_ANSWER'
make_adapter good-agentic agentic 0 'AGENTIC_ANSWER'
make_adapter broken inference 1 ''

# --- fallthrough -------------------------------------------------------------
# The core promise: an exhausted allowance is not an error, it is a reason to
# move to the next provider.
reset_run
assert_exit 0 'fallthrough' route --chain dead-quota,dead-auth,good-inference --prompt 'hi'
assert_out 'INFERENCE_ANSWER' 'fallthrough'
assert_called 'dead-quota' 'fallthrough'
assert_called 'good-inference' 'fallthrough'
assert_err 'served by good-inference' 'fallthrough'

# --- cooldown ----------------------------------------------------------------
# Without this, every later task pays the latency of the dead half of the chain.
reset_run
assert_exit 0 'cooldown write' route --chain dead-quota,good-inference --prompt 'hi'
if [[ ! -f "${STATE_DIR}/dead-quota.cooldown" ]]; then
	fail_msg 'cooldown write: no cooldown recorded for the exhausted provider'
else
	ok
fi

: >"${WORKDIR}/calls.log"
assert_exit 0 'cooldown skip' route --chain dead-quota,good-inference --prompt 'hi'
assert_not_called 'dead-quota' 'cooldown skip'
assert_called 'good-inference' 'cooldown skip'

: >"${WORKDIR}/calls.log"
assert_exit 0 'no-cooldown override' route --no-cooldown --chain dead-quota,good-inference --prompt 'hi'
assert_called 'dead-quota' 'no-cooldown override'

# A successful provider must never be put on cooldown.
reset_run
assert_exit 0 'success leaves no cooldown' route --chain good-inference --prompt 'hi'
if [[ -f "${STATE_DIR}/good-inference.cooldown" ]]; then
	fail_msg 'success leaves no cooldown: a working provider was cooled down'
else
	ok
fi

# --- capability gate ---------------------------------------------------------
# The safety property. Routing an "edit these files" task to a text-only
# endpoint would return a confident description of work that never happened.
reset_run
assert_exit 7 'agentic never uses inference-only' route \
	--capability agentic --chain good-inference --prompt 'edit'
assert_not_called 'good-inference' 'agentic never uses inference-only'

reset_run
assert_exit 0 'inference may use agentic' route \
	--capability inference --chain good-agentic --prompt 'ask'
assert_out 'AGENTIC_ANSWER' 'inference may use agentic'

reset_run
assert_exit 7 '--write implies agentic' route --write --chain good-inference --prompt 'edit'

# --- task failures advance the chain, but only so far ------------------------
# A live run proved that halting on any exit 1 is wrong: gemini-cli returned an
# unrecognised tier error and blocked every remaining provider. The router
# cannot reliably tell "the task is bad" from "this provider is broken", so it
# keeps going -- bounded, so a genuinely bad prompt cannot burn the whole chain.
reset_run
assert_exit 0 'one task failure advances' route --chain broken,good-inference --prompt 'hi'
assert_called 'good-inference' 'one task failure advances'
assert_out 'INFERENCE_ANSWER' 'one task failure advances'

make_adapter broken2 inference 1 ''
reset_run
assert_exit 1 'max-failures stops the chain' route \
	--chain broken,broken2,good-inference --prompt 'hi'
assert_not_called 'good-inference' 'max-failures stops the chain'

reset_run
assert_exit 0 '--max-failures raises the bound' route --max-failures 3 \
	--chain broken,broken2,good-inference --prompt 'hi'
assert_called 'good-inference' '--max-failures raises the bound'

# A task failure must not put the provider on cooldown: nothing is wrong with
# its availability, and cooling it down would hide it from later, different work.
reset_run
route --chain broken,good-inference --prompt 'hi' >/dev/null 2>&1 || true
if [[ -f "${STATE_DIR}/broken.cooldown" ]]; then
	fail_msg 'task failure must not set a cooldown'
else
	ok
fi

# --- exhausted chain ---------------------------------------------------------
reset_run
assert_exit 7 'no route' route --chain dead-quota,dead-auth --prompt 'hi'
assert_err 'no provider could serve' 'no route'

# --- pinning -----------------------------------------------------------------
reset_run
assert_exit 7 'pinned provider does not fall back' route \
	--provider dead-quota --chain dead-quota,good-inference --prompt 'hi'
assert_not_called 'good-inference' 'pinned provider does not fall back'

# --- the local model is deliberately not a provider here ---------------------
# A local server costs no allowance but costs the machine's thermal budget.
# Those are different budgets, so it lives outside this chain entirely.
if [[ -e "${PROVIDERS}/lmstudio.sh" ]]; then
	fail_msg 'lmstudio must not be a piggyback provider; local models belong elsewhere'
else
	ok
fi

reset_run
assert_exit 2 'no --allow-local option' route --allow-local --chain good-inference --prompt 'hi'

# --- json output -------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
	reset_run
	assert_exit 0 'json output' route --json --chain good-inference --prompt 'hi'
	if ! jq -e '.provider == "good-inference" and .exit == 0' <"${WORKDIR}/out.txt" >/dev/null 2>&1; then
		fail_msg 'json output: unexpected shape'
	else
		ok
	fi
fi

# --- status and clear --------------------------------------------------------
reset_run
assert_exit 0 'status' route --status
assert_out 'PROVIDER' 'status'

route --chain dead-quota --prompt 'hi' >/dev/null 2>&1 || true
assert_exit 0 'clear cooldown' route --clear-cooldown dead-quota
if [[ -f "${STATE_DIR}/dead-quota.cooldown" ]]; then
	fail_msg 'clear cooldown: state file survived'
else
	ok
fi

# --- usage -------------------------------------------------------------------
reset_run
assert_exit 2 'missing prompt' route --chain good-inference

# --- real adapters honour the contract ---------------------------------------
# Every adapter must answer `capabilities` and must report a missing binary as
# exit 5 rather than as a failure, or the router cannot classify it.
for adapter in "${PROVIDERS}"/*.sh; do
	name="$(basename "${adapter}" .sh)"

	capability="$("${adapter}" capabilities 2>/dev/null || true)"
	case "${capability}" in
	agentic | inference) ok ;;
	*) fail_msg "adapter ${name}: capabilities must print agentic or inference, got '${capability}'" ;;
	esac
done

# Inference-only adapters must refuse a write request outright.
printf 'hello\n' >"${WORKDIR}/prompt.txt"
for name in groq openrouter mistral; do
	rc=0
	"${PROVIDERS}/${name}.sh" run --write --prompt-file "${WORKDIR}/prompt.txt" \
		>/dev/null 2>&1 || rc=$?
	if [[ "${rc}" != "2" ]]; then
		fail_msg "adapter ${name}: --write must be rejected with exit 2, got ${rc}"
	else
		ok
	fi
done

# Adapters that shell out must report an absent binary as exit 5.
rc=0
PIGGYBACK_AGY_BIN="${WORKDIR}/not-here" "${PROVIDERS}/antigravity.sh" run \
	--prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || rc=$?
if [[ "${rc}" == "5" ]]; then ok; else fail_msg "antigravity adapter: missing binary must exit 5, got ${rc}"; fi

rc=0
PIGGYBACK_CURSOR_BIN="${WORKDIR}/not-here" "${PROVIDERS}/cursor.sh" run \
	--prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || rc=$?
if [[ "${rc}" == "5" ]]; then ok; else fail_msg "cursor adapter: missing binary must exit 5, got ${rc}"; fi

# --- cursor classification ---------------------------------------------------
# Observed verbatim from cursor-agent 2026.06.04 with a stale token on disk.
make_binary_stub() {
	local path="$1" code="$2" payload="$3"
	cat >"${path}" <<BINSTUB
#!/usr/bin/env bash
cat <<'BINPAYLOAD'
${payload}
BINPAYLOAD
exit ${code}
BINSTUB
	chmod +x "${path}"
}

cursor_case() {
	local label="$1" code="$2" payload="$3" expected="$4"
	make_binary_stub "${WORKDIR}/cursor-stub" "${code}" "${payload}"
	local rc=0
	PIGGYBACK_CURSOR_BIN="${WORKDIR}/cursor-stub" "${PROVIDERS}/cursor.sh" run \
		--prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || rc=$?
	if [[ "${rc}" == "${expected}" ]]; then
		ok
	else
		fail_msg "cursor ${label}: expected exit ${expected}, got ${rc}"
	fi
}

# --trust is required even read-only: without it a headless run dies on the
# workspace-trust prompt in any untrusted directory.
: >"${WORKDIR}/cursor-argv"
cat >"${WORKDIR}/cursor-argv-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"${STUB_ARGV:-/dev/null}"
echo '{"type":"result","is_error":false,"result":"OK"}'
STUB
chmod +x "${WORKDIR}/cursor-argv-stub"
STUB_ARGV="${WORKDIR}/cursor-argv" PIGGYBACK_CURSOR_BIN="${WORKDIR}/cursor-argv-stub" \
	"${PROVIDERS}/cursor.sh" run --prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || true
if grep -Fxq -- '--trust' "${WORKDIR}/cursor-argv"; then ok; else fail_msg 'cursor read-only run must pass --trust'; fi
if grep -Fxq -- '--force' "${WORKDIR}/cursor-argv"; then
	fail_msg 'cursor must not pass --force without --write'
else
	ok
fi
# cursor-agent persists --model account-side, so leaving it off inherits
# whatever a previous call pinned. On a Free plan a stale named model fails
# every run until something resets it, so the adapter always sends one.
if grep -Fxq -- 'auto' "${WORKDIR}/cursor-argv" && grep -Fxq -- '--model' "${WORKDIR}/cursor-argv"; then
	ok
else
	fail_msg 'cursor must always send an explicit --model (auto by default)'
fi

: >"${WORKDIR}/cursor-argv"
STUB_ARGV="${WORKDIR}/cursor-argv" PIGGYBACK_CURSOR_BIN="${WORKDIR}/cursor-argv-stub" \
	"${PROVIDERS}/cursor.sh" run --write --prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || true
if grep -Fxq -- '--force' "${WORKDIR}/cursor-argv"; then ok; else fail_msg 'cursor --write must pass --force'; fi

cursor_case 'auth' 1 \
	"Error: Authentication required. Please run 'agent login' first." 4
cursor_case 'no models' 1 'No models available for this account.' 4
cursor_case 'rate limit' 1 'Error: You have hit your rate limit.' 3
cursor_case 'json error body' 0 \
	'{"type":"result","is_error":true,"result":"usage limit exceeded"}' 3
cursor_case 'success' 0 \
	'{"type":"result","subtype":"success","is_error":false,"result":"OK"}' 0

# --- classification gaps found on live providers -----------------------------
# Each of these was observed verbatim and was originally misread as a task
# failure, which halted the whole chain.
classify_case() {
	local label="$1" payload="$2" expected="$3"
	local rc=0
	PIGGYBACK_CLASSIFY_INPUT="${payload}" bash -c '
		source "$1/skills/piggyback/scripts/lib/common.sh"
		exit "$(piggyback_classify_exit "${PIGGYBACK_CLASSIFY_INPUT}")"
	' _ "${ROOT}" || rc=$?
	if [[ "${rc}" == "${expected}" ]]; then
		ok
	else
		fail_msg "classify ${label}: expected ${expected}, got ${rc}"
	fi
}

# gemini-cli 2026-09, personal Google account: the OAuth free tier for
# individuals was discontinued in favour of Antigravity.
classify_case 'gemini ineligible tier' \
	'Error authenticating: IneligibleTierError: This client is no longer supported for Gemini Code Assist for individuals.' 4
# `gh models run` before the provider was dropped; still covers any 410.
classify_case 'github models retirement' \
	'unexpected response from the server: 410 Gone {"code":"github_models_retirement_brownout"}' 6
# Groq dropped the Llama chat models without notice.
classify_case 'stale model id' \
	'{"error":{"message":"The model `llama-3.3-70b-versatile` does not exist","code":"model_not_found"}}' 5
# cursor-agent on a Free plan, after any named model has been selected.
classify_case 'plan restricts named models' \
	'ActionRequiredError: Named models unavailable Free plans can only use Auto.' 4
classify_case 'plain rate limit' 'Error: rate limit exceeded' 3
classify_case 'genuine task failure' 'Error: could not parse the file you asked about' 1

# --- a successful run is never classified ------------------------------------
# An agent transcript can mention a rate limit it already retried past. Cooling
# down a working provider for an hour over that is worse than missing a signal,
# so classification runs only on a non-zero exit.
make_binary_stub "${WORKDIR}/agy-stub" 0 \
	'{"response":"AGY_OK","note":"you have exhausted your quota, retrying"}'
rc=0
PIGGYBACK_AGY_BIN="${WORKDIR}/agy-stub" "${PROVIDERS}/antigravity.sh" run \
	--prompt-file "${WORKDIR}/prompt.txt" >"${WORKDIR}/out.txt" 2>&1 || rc=$?
if [[ "${rc}" == "0" ]]; then ok; else fail_msg "antigravity: a successful run containing quota text must exit 0, got ${rc}"; fi
assert_out 'AGY_OK' 'antigravity success'

make_binary_stub "${WORKDIR}/agy-stub" 1 'Error: 429 RESOURCE_EXHAUSTED'
rc=0
PIGGYBACK_AGY_BIN="${WORKDIR}/agy-stub" "${PROVIDERS}/antigravity.sh" run \
	--prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || rc=$?
if [[ "${rc}" == "3" ]]; then ok; else fail_msg "antigravity: a failed run with 429 must exit 3, got ${rc}"; fi

# agy answers {"status":"SUCCESS","response":""} when headless mode auto-denies a
# tool it wanted. Treating that as success made the router announce the provider
# as having served the task and stop the chain, with nothing produced.
make_binary_stub "${WORKDIR}/agy-empty" 0 \
	'{"status":"SUCCESS","response":"","denied_actions":[{"display_name":"RunCommand"}]}'
rc=0
PIGGYBACK_AGY_BIN="${WORKDIR}/agy-empty" "${PROVIDERS}/antigravity.sh" run \
	--prompt-file "${WORKDIR}/prompt.txt" >"${WORKDIR}/out.txt" 2>"${WORKDIR}/err.txt" || rc=$?
if [[ "${rc}" == "1" ]]; then ok; else fail_msg "antigravity: an empty response must not be success, got ${rc}"; fi
if grep -Fq 'RunCommand' "${WORKDIR}/err.txt"; then ok; else fail_msg 'antigravity must name the denied tool'; fi
if [[ -s "${WORKDIR}/out.txt" ]]; then
	fail_msg 'antigravity must not print an empty answer to stdout'
else
	ok
fi

# A whitespace-only response is just as empty.
make_binary_stub "${WORKDIR}/agy-empty" 0 '{"status":"SUCCESS","response":"   \n  "}'
rc=0
PIGGYBACK_AGY_BIN="${WORKDIR}/agy-empty" "${PROVIDERS}/antigravity.sh" run \
	--prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || rc=$?
if [[ "${rc}" == "1" ]]; then ok; else fail_msg "antigravity: a whitespace-only response must not be success, got ${rc}"; fi

# agy's --print takes the prompt as its value. Passing it bare makes agy
# swallow the next flag as the prompt and silently answer the wrong question.
: >"${WORKDIR}/agy-argv"
cat >"${WORKDIR}/agy-argv-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"${STUB_ARGV:-/dev/null}"
echo '{"response":"OK"}'
STUB
chmod +x "${WORKDIR}/agy-argv-stub"
STUB_ARGV="${WORKDIR}/agy-argv" PIGGYBACK_AGY_BIN="${WORKDIR}/agy-argv-stub" \
	"${PROVIDERS}/antigravity.sh" run --prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || true
if grep -q -- '^--print=' "${WORKDIR}/agy-argv"; then ok; else fail_msg 'antigravity must attach the prompt to --print='; fi
if grep -Fxq -- '--print' "${WORKDIR}/agy-argv"; then
	fail_msg 'antigravity must not pass a bare --print'
else
	ok
fi
if grep -Fxq -- 'plan' "${WORKDIR}/agy-argv"; then ok; else fail_msg 'antigravity read-only run must use --mode plan'; fi
if grep -Fxq -- '--dangerously-skip-permissions' "${WORKDIR}/agy-argv"; then
	fail_msg 'antigravity must not skip permissions without --write'
else
	ok
fi

: >"${WORKDIR}/agy-argv"
STUB_ARGV="${WORKDIR}/agy-argv" PIGGYBACK_AGY_BIN="${WORKDIR}/agy-argv-stub" \
	"${PROVIDERS}/antigravity.sh" run --write --prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || true
if grep -Fxq -- '--dangerously-skip-permissions' "${WORKDIR}/agy-argv"; then ok; else fail_msg 'antigravity --write must skip permissions'; fi

# --- per-use-case model selection --------------------------------------------
# The point of the skill is not only availability fallback; it is calling each
# agent CLI with the right model for the job. A chain entry therefore carries an
# optional model, written provider=model. `=` rather than `:` because model ids
# contain colons and slashes (nvidia/nemotron-3.5-lightning:free).
assert_arg_pair() {
	local flag="$1" value="$2" label="$3"
	if grep -Fxq -- "${flag}" "${WORKDIR}/args.log" && grep -Fxq -- "${value}" "${WORKDIR}/args.log"; then
		ok
	else
		fail_msg "${label}: expected ${flag} ${value} in adapter argv (got: $(tr '\n' ' ' <"${WORKDIR}/args.log"))"
	fi
}

reset_run
assert_exit 0 'chain entry carries a model' route \
	--chain 'good-inference=some-model' --prompt 'hi'
assert_arg_pair '--model' 'some-model' 'chain entry carries a model'

reset_run
assert_exit 0 'bare chain entry passes no model' route --chain good-inference --prompt 'hi'
if grep -Fxq -- '--model' "${WORKDIR}/args.log"; then
	fail_msg 'a bare chain entry must not pass --model'
else
	ok
fi

# Model ids are not simple words; parsing must not break on their punctuation.
reset_run
assert_exit 0 'model id with slash and colon' route \
	--chain 'good-inference=nvidia/nemotron-3.5-lightning:free' --prompt 'hi'
assert_arg_pair '--model' 'nvidia/nemotron-3.5-lightning:free' 'model id with slash and colon'

# An explicit --model is the caller being specific; it wins over the chain's.
reset_run
assert_exit 0 '--model overrides the chain entry' route \
	--model caller-choice --chain 'good-inference=chain-choice' --prompt 'hi'
assert_arg_pair '--model' 'caller-choice' '--model overrides the chain entry'

# --- profiles ----------------------------------------------------------------
# A profile is the "which model for this kind of work" decision, made once and
# named, so a caller does not have to know any provider's model ids.
PROFILES="${WORKDIR}/profiles.conf"
cat >"${PROFILES}" <<'PROF'
# name|capability|provider[=model],...
tiny|inference|good-inference=small-model,dead-quota
brainy|agentic|good-agentic=big-model
PROF

profile_route() {
	PIGGYBACK_PROFILES_FILE="${PROFILES}" route "$@"
}

reset_run
assert_exit 0 'profile sets chain and model' profile_route --profile tiny --prompt 'hi'
assert_arg_pair '--model' 'small-model' 'profile sets chain and model'
assert_out 'INFERENCE_ANSWER' 'profile sets chain and model'

# A profile also carries the capability, so the caller cannot accidentally send
# an editing profile through a text-only provider.
reset_run
assert_exit 0 'profile sets capability' profile_route --profile brainy --prompt 'hi'
assert_out 'AGENTIC_ANSWER' 'profile sets capability'
assert_arg_pair '--model' 'big-model' 'profile sets capability'

# Availability fallback still applies inside a profile.
reset_run
assert_exit 0 'profile still falls through' profile_route \
	--profile tiny --chain 'dead-quota,good-inference=small-model' --prompt 'hi'
assert_called 'good-inference' 'profile still falls through'

reset_run
assert_exit 2 'unknown profile is a usage error' profile_route --profile nope --prompt 'hi'

reset_run
assert_exit 0 'list-profiles' profile_route --list-profiles
assert_out 'tiny' 'list-profiles'
assert_out 'brainy' 'list-profiles'

# The shipped profiles must name providers that actually exist, or the feature
# is a list of dead ends.
SHIPPED_PROFILES="${SKILL_DIR}/profiles.conf"
if [[ -f "${SHIPPED_PROFILES}" ]]; then
	ok
	while IFS='|' read -r pname pcap pchain; do
		[[ "${pname}" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${pname// /}" ]] && continue
		case "${pcap}" in
		inference | agentic) ok ;;
		*) fail_msg "profile ${pname}: capability must be inference or agentic, got '${pcap}'" ;;
		esac
		IFS=',' read -r -a entries <<<"${pchain}"
		for entry in "${entries[@]}"; do
			pprov="${entry%%=*}"
			if [[ -x "${PROVIDERS}/${pprov}.sh" ]]; then
				ok
			else
				fail_msg "profile ${pname}: no adapter for provider '${pprov}'"
			fi
		done
	done <"${SHIPPED_PROFILES}"
else
	fail_msg "shipped profiles.conf is missing"
fi

# --- a model-specific failure must not sideline the whole provider -----------
# Profiles routinely list the same provider twice with different models
# (antigravity=claude-opus-4-6-thinking, antigravity=gemini-3.1-pro-high). If a
# stale model id cooled down the provider, the second entry would be skipped
# even though its own model is fine.
cat >"${STUB_DIR}/model-picky.sh" <<'STUB'
#!/usr/bin/env bash
model=''
verb="$1"
shift || true
while [[ $# -gt 0 ]]; do
	[[ "$1" == --model ]] && model="$2"
	shift
done
case "${verb}" in
capabilities) echo inference ;;
probe) exit 0 ;;
run)
	echo "model-picky:${model}" >>"${ADAPTER_CALL_LOG:-/dev/null}"
	if [[ "${model}" == good ]]; then
		echo PICKY_ANSWER
		exit 0
	fi
	echo 'The model does not exist or you do not have access to it' >&2
	exit 5
	;;
esac
STUB
chmod +x "${STUB_DIR}/model-picky.sh"

reset_run
assert_exit 0 'stale model does not sideline the provider' route \
	--chain 'model-picky=bad,model-picky=good' --prompt 'hi'
assert_out 'PICKY_ANSWER' 'stale model does not sideline the provider'
assert_called 'model-picky:good' 'stale model does not sideline the provider'

if [[ -f "${STATE_DIR}/model-picky.cooldown" ]]; then
	fail_msg 'a model-specific failure must not write a provider-wide cooldown'
else
	ok
fi

# A provider-wide problem still sidelines every entry for that provider.
reset_run
assert_exit 7 'auth failure writes a provider-wide cooldown' route \
	--chain dead-auth --prompt 'hi'
if [[ -f "${STATE_DIR}/dead-auth.cooldown" ]]; then ok; else fail_msg 'auth failure must write a provider-wide cooldown'; fi

: >"${WORKDIR}/calls.log"
assert_exit 7 'provider cooldown also skips its model-scoped entries' route \
	--chain 'dead-auth=some-model' --prompt 'hi'
assert_not_called 'dead-auth' 'provider cooldown also skips its model-scoped entries'

# --- probe validates the model the chain actually names ----------------------
# Without this, `--probe --profile reasoning` reports ok for a provider whose
# configured model the account cannot see -- the exact failure probing exists
# to catch.
reset_run
route --probe --chain 'good-inference=some-model' >/dev/null 2>&1 || true
if grep -Fxq -- '--model' "${WORKDIR}/probe.log" && grep -Fxq -- 'some-model' "${WORKDIR}/probe.log"; then
	ok
else
	fail_msg "probe must pass the chain entry's model (got: $(tr '\n' ' ' <"${WORKDIR}/probe.log"))"
fi

# --- --json must never emit non-JSON -----------------------------------------
# A PATH that still has a usable shell but no jq at all. Dropping PATH entirely
# breaks the router before it ever reaches the check being tested.
NOJQ_BIN="${WORKDIR}/nojq-bin"
mkdir -p "${NOJQ_BIN}"
for tool in bash sh dirname basename date mktemp cat sed grep head tail cut tr rm mkdir find sort uniq wc chmod env sleep kill printf; do
	src="$(command -v "${tool}" 2>/dev/null || true)"
	[[ -n "${src}" ]] && ln -sf "${src}" "${NOJQ_BIN}/${tool}"
done

reset_run
rc=0
env PATH="${NOJQ_BIN}" ADAPTER_CALL_LOG="${WORKDIR}/calls.log" \
	PIGGYBACK_PROVIDER_DIR="${STUB_DIR}" PIGGYBACK_STATE_DIR="${STATE_DIR}" \
	"${NOJQ_BIN}/bash" "${ROUTER}" --json --chain good-inference --prompt 'hi' >/dev/null 2>&1 || rc=$?
if [[ "${rc}" == "2" ]]; then ok; else fail_msg "--json without jq must be refused with exit 2, got ${rc}"; fi

# --- HTTP layer, against a real server ---------------------------------------
# Stub adapters prove the routing; they say nothing about whether an adapter
# builds a correct request or reads the answer out of the right field. This
# drives the shared OpenAI-compatible body over real HTTP, where the status
# returned is chosen by the model id so one server covers every branch.
if command -v python3 >/dev/null 2>&1; then
	cat >"${WORKDIR}/mock_openai.py" <<'MOCK'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

MODELS = ["mock-ok", "mock-429", "mock-429-retry", "mock-401", "mock-404", "mock-503", "mock-badjson"]
BODIES = {
    "mock-429": (429, {"error": {"message": "rate limit exceeded"}}),
    "mock-429-retry": (429, {"error": {"message": "rate limited", "metadata": {"retry_after_seconds": 5}}}),
    "mock-401": (401, {"error": {"message": "invalid api key"}}),
    "mock-404": (404, {"error": {"message": "model_not_found"}}),
    "mock-503": (503, {"error": {"message": "service unavailable"}}),
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, payload):
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if "empty-roster" in self.path:
            self._send(200, {"object": "list"})
            return
        self._send(200, {"data": [{"id": m} for m in MODELS]})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        model = body.get("model", "")
        if model in BODIES:
            self._send(*BODIES[model])
            return
        if model == "mock-badjson":
            self._send(200, {"unexpected": "shape"})
            return
        # Echoing the prompt proves the request body was assembled correctly.
        self._send(200, {"choices": [{"message": {"content": "ECHO:" + body["messages"][0]["content"].strip()}}]})


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w") as fh:
    fh.write(str(server.server_port))
server.serve_forever()
MOCK

	python3 "${WORKDIR}/mock_openai.py" "${WORKDIR}/port" &
	MOCK_PID=$!
	trap 'kill "${MOCK_PID}" 2>/dev/null || true; rm -rf "${WORKDIR}"' EXIT

	for _ in 1 2 3 4 5 6 7 8 9 10; do
		[[ -s "${WORKDIR}/port" ]] && break
		sleep 0.3
	done

	if [[ -s "${WORKDIR}/port" ]]; then
		MOCK_URL="http://127.0.0.1:$(cat "${WORKDIR}/port")/v1"
		printf 'hello world\n' >"${WORKDIR}/http-prompt.txt"

		http_case() {
			local adapter="$1" base_var="$2" key_var="$3" model="$4" expected="$5"
			local rc=0 out
			out="$(env "${base_var}=${MOCK_URL}" "${key_var}=dummy" \
				"${PROVIDERS}/${adapter}.sh" run --model "${model}" \
				--prompt-file "${WORKDIR}/http-prompt.txt" 2>&1)" || rc=$?
			if [[ "${rc}" != "${expected}" ]]; then
				fail_msg "${adapter} over HTTP (${model}): expected ${expected}, got ${rc}"
				return
			fi
			ok
			if [[ "${expected}" == "0" && "${out}" != *'ECHO:hello world'* ]]; then
				fail_msg "${adapter} over HTTP: answer not extracted (got: ${out:0:80})"
			else
				ok
			fi
		}

		http_case openrouter PIGGYBACK_OPENROUTER_BASE_URL OPENROUTER_API_KEY mock-ok 0
		http_case openrouter PIGGYBACK_OPENROUTER_BASE_URL OPENROUTER_API_KEY mock-429 3
		http_case openrouter PIGGYBACK_OPENROUTER_BASE_URL OPENROUTER_API_KEY mock-401 4
		http_case openrouter PIGGYBACK_OPENROUTER_BASE_URL OPENROUTER_API_KEY mock-404 5
		http_case openrouter PIGGYBACK_OPENROUTER_BASE_URL OPENROUTER_API_KEY mock-503 6
		http_case openrouter PIGGYBACK_OPENROUTER_BASE_URL OPENROUTER_API_KEY mock-badjson 1
		http_case openrouter PIGGYBACK_OPENROUTER_BASE_URL OPENROUTER_API_KEY mock-429-retry 3
		http_case groq PIGGYBACK_GROQ_BASE_URL GROQ_API_KEY mock-ok 0
		http_case mistral PIGGYBACK_MISTRAL_BASE_URL MISTRAL_API_KEY mock-ok 0

		# A 200 whose body carries no usable roster must not pass as ok: silently
		# skipping validation is the outcome probing exists to prevent.
		rc=0
		env "PIGGYBACK_OPENROUTER_BASE_URL=${MOCK_URL}/empty-roster" OPENROUTER_API_KEY=dummy \
			"${PROVIDERS}/openrouter.sh" probe --model mock-ok >/dev/null 2>&1 || rc=$?
		if [[ "${rc}" == "5" ]]; then ok; else fail_msg "probe must reject an unreadable model roster, got ${rc}"; fi

		# Probing must validate the model the chain named, not just the adapter's
		# own default, or `--probe --profile X` reports ok for a model the
		# account cannot use.
		rc=0
		env "PIGGYBACK_OPENROUTER_BASE_URL=${MOCK_URL}" OPENROUTER_API_KEY=dummy \
			"${PROVIDERS}/openrouter.sh" probe --model not-on-this-account >/dev/null 2>&1 || rc=$?
		if [[ "${rc}" == "5" ]]; then ok; else fail_msg "probe --model must reject an unavailable model, got ${rc}"; fi

		rc=0
		env "PIGGYBACK_OPENROUTER_BASE_URL=${MOCK_URL}" OPENROUTER_API_KEY=dummy \
			"${PROVIDERS}/openrouter.sh" probe --model mock-ok >/dev/null 2>&1 || rc=$?
		if [[ "${rc}" == "0" ]]; then ok; else fail_msg "probe --model must accept an available model, got ${rc}"; fi

		# A provider that says how long to wait must not be sidelined for the
		# flat quota hour. OpenRouter's free pool answers 429 with
		# retry_after_seconds: 5, which is contention, not an exhausted quota.
		rm -f "${STATE_DIR}"/*.cooldown 2>/dev/null || true
		env "PIGGYBACK_OPENROUTER_BASE_URL=${MOCK_URL}" OPENROUTER_API_KEY=dummy \
			PIGGYBACK_STATE_DIR="${STATE_DIR}" PIGGYBACK_PROVIDER_DIR="${PROVIDERS}" \
			bash "${ROUTER}" --chain openrouter --model mock-429-retry \
			--prompt 'hi' >/dev/null 2>&1 || true
		if [[ -f "${STATE_DIR}/openrouter.cooldown" ]]; then
			read -r cd_until _ <"${STATE_DIR}/openrouter.cooldown"
			cd_left=$((cd_until - $(date +%s)))
			if [[ "${cd_left}" -le 30 ]]; then
				ok
			else
				fail_msg "retry-after ignored: cooldown is ${cd_left}s, expected <= 30s"
			fi
		else
			fail_msg 'retry-after case recorded no cooldown at all'
		fi
		rm -f "${STATE_DIR}"/*.cooldown 2>/dev/null || true

		# A default the account cannot see must surface at probe time, where
		# listing models is free, rather than costing a request to discover.
		rc=0
		env "PIGGYBACK_OPENROUTER_BASE_URL=${MOCK_URL}" OPENROUTER_API_KEY=dummy \
			PIGGYBACK_OPENROUTER_MODEL=not-on-this-account \
			"${PROVIDERS}/openrouter.sh" probe >/dev/null 2>&1 || rc=$?
		if [[ "${rc}" == "5" ]]; then ok; else fail_msg "probe must reject a stale default model, got ${rc}"; fi
	else
		fail_msg 'mock OpenAI server did not start'
	fi
fi

# --- CLI-backed adapters build the right command line ------------------------
# Copilot has no auth-status command and can authenticate from the keychain, so
# probing must not report a missing token as an auth failure: that would sideline
# a working provider for the entire auth cooldown on nothing but a guess.
cat >"${WORKDIR}/copilot-probe-stub" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "${WORKDIR}/copilot-probe-stub"
rc=0
env -u GH_TOKEN -u GITHUB_TOKEN -u COPILOT_GITHUB_TOKEN HOME="${WORKDIR}/empty-home" \
	PIGGYBACK_COPILOT_BIN="${WORKDIR}/copilot-probe-stub" \
	"${PROVIDERS}/copilot.sh" probe >/dev/null 2>&1 || rc=$?
if [[ "${rc}" == "0" ]]; then ok; else fail_msg "copilot probe must not guess auth failure, got ${rc}"; fi

cat >"${WORKDIR}/copilot-stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"${STUB_ARGV:-/dev/null}"
echo COPILOT_ANSWER
STUB
chmod +x "${WORKDIR}/copilot-stub"

: >"${WORKDIR}/copilot-argv"
rc=0
STUB_ARGV="${WORKDIR}/copilot-argv" PIGGYBACK_COPILOT_BIN="${WORKDIR}/copilot-stub" \
	"${PROVIDERS}/copilot.sh" run --prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || rc=$?
if [[ "${rc}" == "0" ]]; then ok; else fail_msg "copilot read-only run: expected 0, got ${rc}"; fi
# --no-ask-user is what stops the agent blocking on a question nobody can answer.
if grep -Fxq -- '--no-ask-user' "${WORKDIR}/copilot-argv"; then ok; else fail_msg 'copilot must pass --no-ask-user'; fi
if grep -Fxq -- '--allow-all-tools' "${WORKDIR}/copilot-argv"; then
	fail_msg 'copilot must not pass --allow-all-tools without --write'
else
	ok
fi

: >"${WORKDIR}/copilot-argv"
STUB_ARGV="${WORKDIR}/copilot-argv" PIGGYBACK_COPILOT_BIN="${WORKDIR}/copilot-stub" \
	"${PROVIDERS}/copilot.sh" run --write --prompt-file "${WORKDIR}/prompt.txt" >/dev/null 2>&1 || true
if grep -Fxq -- '--allow-all-tools' "${WORKDIR}/copilot-argv"; then ok; else fail_msg 'copilot --write must pass --allow-all-tools'; fi

# --- shared contract across both hosts ---------------------------------------
SKILL="${SKILL_DIR}/SKILL.md"
CLAUDE_AGENT="${ROOT}/claude/agents/piggyback-worker.md"
CODEX_AGENT="${ROOT}/codex/agents/piggyback-worker.toml"

assert_file_contains "${SKILL}" 'name: piggyback' 'skill frontmatter'
assert_file_contains "${SKILL}" 'piggyback.sh' 'skill references the router'
assert_file_contains "${SKILL}" 'capabilities' 'skill documents the adapter contract'

assert_file_contains "${CLAUDE_AGENT}" 'name: piggyback-worker' 'claude agent name'
assert_file_contains "${CODEX_AGENT}" 'name = "piggyback-worker"' 'codex agent name'
assert_file_contains "${CLAUDE_AGENT}" 'piggyback.sh' 'claude agent uses the router'
assert_file_contains "${CODEX_AGENT}" 'piggyback.sh' 'codex agent uses the router'
assert_file_contains "${CLAUDE_AGENT}" 'BLOCKED' 'claude agent reports BLOCKED'
assert_file_contains "${CODEX_AGENT}" 'BLOCKED' 'codex agent reports BLOCKED'

assert_file_contains "${ROOT}/codex/config.toml" '[agents.piggyback-worker]' 'codex registration'
assert_file_contains "${ROOT}/codex/config.toml" 'agents/piggyback-worker.toml' 'codex registration path'

# --- summary -----------------------------------------------------------------
echo "piggyback: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]] || exit 1
echo 'PASS: piggyback router, adapter contract, and piggyback-worker definitions'
