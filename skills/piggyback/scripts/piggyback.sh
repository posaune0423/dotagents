#!/usr/bin/env bash
# piggyback router: run one task on the first free-tier provider that can
# serve it, falling through the chain as allowances run out.
#
# The router knows nothing about any specific model. It only knows the adapter
# contract (capabilities | probe | run) and the exit-code contract, which is
# what lets a new provider be added by dropping one file into providers/.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${HERE}/lib/common.sh"

# Overridable so the integration tests can route a stub chain through the real
# router instead of re-implementing the routing logic in the test.
PROVIDER_DIR="${PIGGYBACK_PROVIDER_DIR:-${HERE}/providers}"

# Ordered cheapest-allowance-first within each capability class.
#
# Inference requests deliberately try the inference-only providers before the
# agentic ones: an agentic allowance can answer a question, but spending it on
# something Groq could have done wastes the only quota that can edit files.
CHAIN_INFERENCE_DEFAULT='groq,openrouter,mistral,antigravity,cursor,copilot'
CHAIN_AGENTIC_DEFAULT='antigravity,cursor,copilot'

usage() {
	cat <<'USAGE'
Usage:
  piggyback.sh [options] --prompt <text>
  piggyback.sh [options] --prompt-file <path>
  piggyback.sh --probe
  piggyback.sh --status
  piggyback.sh --list-profiles
  piggyback.sh --clear-cooldown [provider]

Options:
  --prompt <text>         The task. Must be self-contained: no provider sees your conversation.
  --prompt-file <path>    Read the task from a file instead.
  --capability <class>    inference (default) or agentic. agentic means the provider can
                          read the workspace, edit files, and run commands.
  --write                 Allow file edits. Implies --capability agentic.
  --provider <name>       Pin one provider and do not fall back.
  --chain <a,b=model,c>   Override the provider order. An entry may carry the model for
                          that provider, written provider=model.
  --profile <name>        Use a named use-case profile: it sets the capability and an
                          ordered provider=model chain. See --list-profiles.
  --list-profiles         Print the available profiles and exit.
  --model <id>            Model id for the chosen provider. Usually leave unset.
  --workspace <path>      Working directory for agentic providers.
  --timeout <seconds>     Per-provider wall-clock limit (default 900).
  --max-failures <n>      Give up after this many providers fail on the task itself
                          (default 2). Availability skips are not counted.
  --no-cooldown           Ignore and do not write cooldown state.
  --json                  Emit {"provider":...,"exit":...,"answer":...} instead of bare text.
  -h, --help              Show this help.

Exit codes: 0 ok, 1 providers failed on the task, 2 usage,
            7 no provider in the chain could serve.
USAGE
}

die_usage() {
	echo "piggyback: $*" >&2
	echo >&2
	usage >&2
	exit "${PIGGYBACK_EXIT_USAGE}"
}

# --- arguments ---------------------------------------------------------------
prompt=''
prompt_file=''
capability='inference'
write=0
pinned=''
chain_override=''
profile=''
model=''
workspace=''
timeout_secs="${PIGGYBACK_TIMEOUT:-900}"
no_cooldown=0
max_failures="${PIGGYBACK_MAX_FAILURES:-2}"
as_json=0
mode='run'
clear_target=''

while [[ $# -gt 0 ]]; do
	case "$1" in
	--prompt)
		[[ $# -ge 2 ]] || die_usage "--prompt needs a value"
		prompt="$2"
		shift 2
		;;
	--prompt-file)
		[[ $# -ge 2 ]] || die_usage "--prompt-file needs a value"
		prompt_file="$2"
		shift 2
		;;
	--capability)
		[[ $# -ge 2 ]] || die_usage "--capability needs a value"
		capability="$2"
		shift 2
		;;
	--write)
		write=1
		capability='agentic'
		shift
		;;
	--provider)
		[[ $# -ge 2 ]] || die_usage "--provider needs a value"
		pinned="$2"
		shift 2
		;;
	--chain)
		[[ $# -ge 2 ]] || die_usage "--chain needs a value"
		chain_override="$2"
		shift 2
		;;
	--profile)
		[[ $# -ge 2 ]] || die_usage "--profile needs a value"
		profile="$2"
		shift 2
		;;
	--list-profiles)
		mode='profiles'
		shift
		;;
	--model)
		[[ $# -ge 2 ]] || die_usage "--model needs a value"
		model="$2"
		shift 2
		;;
	--workspace)
		[[ $# -ge 2 ]] || die_usage "--workspace needs a value"
		workspace="$2"
		shift 2
		;;
	--timeout)
		[[ $# -ge 2 ]] || die_usage "--timeout needs a value"
		timeout_secs="$2"
		shift 2
		;;
	--max-failures)
		[[ $# -ge 2 ]] || die_usage "--max-failures needs a value"
		max_failures="$2"
		shift 2
		;;
	--no-cooldown)
		no_cooldown=1
		shift
		;;
	--json)
		as_json=1
		shift
		;;
	--probe)
		mode='probe'
		shift
		;;
	--status)
		mode='status'
		shift
		;;
	--clear-cooldown)
		mode='clear'
		if [[ $# -ge 2 && "$2" != -* ]]; then
			clear_target="$2"
			shift
		fi
		shift
		;;
	-h | --help)
		usage
		exit "${PIGGYBACK_EXIT_OK}"
		;;
	*)
		die_usage "unknown argument: $1"
		;;
	esac
done

case "${capability}" in
inference | agentic) ;;
*) die_usage "--capability must be inference or agentic" ;;
esac

[[ "${timeout_secs}" =~ ^[0-9]+$ ]] || die_usage "--timeout must be a whole number of seconds"
[[ "${max_failures}" =~ ^[0-9]+$ ]] || die_usage "--max-failures must be a whole number"

if [[ "${as_json}" -eq 1 ]] && ! command -v jq >/dev/null 2>&1; then
	die_usage "--json needs jq, which is not installed"
fi

# A chain entry is `provider` or `provider=model`. `=` separates them because
# model ids routinely contain both colons and slashes, so neither works.
entry_provider() { printf '%s' "${1%%=*}"; }
entry_model() {
	if [[ "$1" == *=* ]]; then
		printf '%s' "${1#*=}"
	fi
}

adapter_for() { printf '%s/%s.sh' "${PROVIDER_DIR}" "$1"; }

provider_exists() { [[ -x "$(adapter_for "$1")" ]]; }

provider_capability() {
	local adapter
	adapter="$(adapter_for "$1")"
	"${adapter}" capabilities 2>/dev/null | head -1
}

# agentic ⊇ inference: a provider that can drive a workspace can also just
# answer a question, but not the other way round.
provider_satisfies() {
	local have="$1" need="$2"
	[[ "${need}" == 'inference' ]] && return 0
	[[ "${have}" == 'agentic' ]]
}

# A profile names the "which model for this kind of work" decision once, so a
# caller never has to carry provider-specific model ids. One per line:
#   name|capability|provider[=model],provider[=model],...
profiles_file() {
	printf '%s' "${PIGGYBACK_PROFILES_FILE:-${HERE}/../profiles.conf}"
}

# Echoes "capability|chain" for a profile name, or fails if it is not defined.
profile_lookup() {
	local want="$1" file name capability chain
	file="$(profiles_file)"
	[[ -f "${file}" ]] || return 1

	while IFS='|' read -r name capability chain || [[ -n "${name}" ]]; do
		[[ "${name}" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${name// /}" ]] && continue
		if [[ "${name}" == "${want}" ]]; then
			printf '%s|%s' "${capability}" "${chain}"
			return 0
		fi
	done <"${file}"
	return 1
}

profile_chain=''
if [[ -n "${profile}" ]]; then
	if ! profile_resolved="$(profile_lookup "${profile}")"; then
		die_usage "unknown profile: ${profile} (see --list-profiles)"
	fi
	profile_capability="${profile_resolved%%|*}"
	profile_chain="${profile_resolved#*|}"
	case "${profile_capability}" in
	inference | agentic) ;;
	*) die_usage "profile ${profile} declares an invalid capability: ${profile_capability}" ;;
	esac
	# --write is a stronger statement than the profile's capability, so it wins.
	if [[ "${write}" -eq 0 ]]; then
		capability="${profile_capability}"
	fi
fi

resolve_chain() {
	local raw
	if [[ -n "${pinned}" ]]; then
		printf '%s' "${pinned}"
		return
	fi
	if [[ -n "${chain_override}" ]]; then
		raw="${chain_override}"
	elif [[ -n "${profile_chain}" ]]; then
		raw="${profile_chain}"
	elif [[ -n "${PIGGYBACK_CHAIN:-}" ]]; then
		raw="${PIGGYBACK_CHAIN}"
	elif [[ "${capability}" == 'agentic' ]]; then
		raw="${PIGGYBACK_CHAIN_AGENTIC:-${CHAIN_AGENTIC_DEFAULT}}"
	else
		raw="${PIGGYBACK_CHAIN_INFERENCE:-${CHAIN_INFERENCE_DEFAULT}}"
	fi
	printf '%s' "${raw}"
}

# --- status / clear ----------------------------------------------------------
if [[ "${mode}" == 'clear' ]]; then
	piggyback_cooldown_clear "${clear_target}"
	echo "cleared cooldown: ${clear_target:-all providers}"
	exit "${PIGGYBACK_EXIT_OK}"
fi

if [[ "${mode}" == 'profiles' ]]; then
	file="$(profiles_file)"
	if [[ ! -f "${file}" ]]; then
		echo "no profiles file at ${file}" >&2
		exit "${PIGGYBACK_EXIT_FAILED}"
	fi
	printf '%-14s %-10s %s\n' PROFILE CAPABILITY CHAIN
	while IFS='|' read -r name capability chain || [[ -n "${name}" ]]; do
		[[ "${name}" =~ ^[[:space:]]*# ]] && continue
		[[ -z "${name// /}" ]] && continue
		printf '%-14s %-10s %s\n' "${name}" "${capability}" "${chain}"
	done <"${file}"
	exit "${PIGGYBACK_EXIT_OK}"
fi

if [[ "${mode}" == 'status' ]]; then
	printf '%-16s %-10s %s\n' PROVIDER CAPABILITY COOLDOWN
	for adapter in "${PROVIDER_DIR}"/*.sh; do
		name="$(basename "${adapter}" .sh)"
		cd_info="$(piggyback_cooldown_active "${name}" || true)"
		if [[ -n "${cd_info}" ]]; then
			# shellcheck disable=SC2086 # Deliberate split into seconds and reason.
			set -- ${cd_info}
			cd_text="$2, ${1}s left"
		else
			cd_text='-'
		fi
		printf '%-16s %-10s %s\n' "${name}" "$(provider_capability "${name}")" "${cd_text}"
	done
	exit "${PIGGYBACK_EXIT_OK}"
fi

# --- probe -------------------------------------------------------------------
if [[ "${mode}" == 'probe' ]]; then
	printf '%-16s %-10s %-9s %s\n' PROVIDER CAPABILITY STATUS DETAIL
	rc_any=1
	IFS=',' read -r -a probe_chain <<<"$(resolve_chain)"
	for probe_entry in "${probe_chain[@]}"; do
		[[ -n "${probe_entry}" ]] || continue
		name="$(entry_provider "${probe_entry}")"
		if ! provider_exists "${name}"; then
			printf '%-16s %-10s %-9s %s\n' "${name}" '?' 'unknown' 'no adapter'
			continue
		fi
		probe_args=(probe)
		probe_model="${model:-$(entry_model "${probe_entry}")}"
		[[ -n "${probe_model}" ]] && probe_args+=(--model "${probe_model}")
		rc=0
		detail="$("$(adapter_for "${name}")" "${probe_args[@]}" 2>&1)" || rc=$?
		if [[ "${rc}" -eq 0 ]]; then
			rc_any=0
		fi
		printf '%-16s %-10s %-9s %s\n' \
			"${name}" "$(provider_capability "${name}")" "$(piggyback_exit_name "${rc}")" \
			"$(printf '%s' "${detail}" | tr '\n' ' ' | cut -c1-70)"
	done
	exit "${rc_any}"
fi

# --- prompt ------------------------------------------------------------------
tmp_prompt=''
if [[ -n "${prompt_file}" ]]; then
	[[ -f "${prompt_file}" ]] || die_usage "--prompt-file does not exist: ${prompt_file}"
else
	[[ -n "${prompt}" ]] || die_usage "a prompt is required (--prompt or --prompt-file)"
	tmp_prompt="$(mktemp)"
	printf '%s' "${prompt}" >"${tmp_prompt}"
	prompt_file="${tmp_prompt}"
fi
# shellcheck disable=SC2329 # Invoked through the EXIT trap below.
cleanup() { [[ -n "${tmp_prompt}" ]] && rm -f "${tmp_prompt}"; }
trap cleanup EXIT

# --- routing -----------------------------------------------------------------
base_run_args=(run --prompt-file "${prompt_file}" --timeout "${timeout_secs}")
[[ "${write}" -eq 1 ]] && base_run_args+=(--write)
[[ -n "${workspace}" ]] && base_run_args+=(--workspace "${workspace}")

IFS=',' read -r -a chain <<<"$(resolve_chain)"
attempt=0
failures=0
retry_after=''
skipped=()
last_failure_rc=0
last_failure_detail=''

for entry in "${chain[@]}"; do
	[[ -n "${entry}" ]] || continue
	name="$(entry_provider "${entry}")"
	# An explicit --model is the caller being specific about this one call, so
	# it outranks whatever the chain entry or profile suggested.
	chosen_model="${model:-$(entry_model "${entry}")}"

	run_args=("${base_run_args[@]}")
	[[ -n "${chosen_model}" ]] && run_args+=(--model "${chosen_model}")

	if ! provider_exists "${name}"; then
		skipped+=("${name}:no-adapter")
		continue
	fi

	have="$(provider_capability "${name}")"
	if ! provider_satisfies "${have}" "${capability}"; then
		skipped+=("${name}:needs-${capability}")
		continue
	fi

	model_key="$(piggyback_cooldown_key "${name}" "${chosen_model}")"

	if [[ "${no_cooldown}" -eq 0 ]]; then
		# Both scopes are consulted: a provider-wide problem must hide every one
		# of its entries, and a model-specific one only its own.
		cooling="$(piggyback_cooldown_active "${name}" || true)"
		[[ -z "${cooling}" && "${model_key}" != "${name}" ]] &&
			cooling="$(piggyback_cooldown_active "${model_key}" || true)"
		if [[ -n "${cooling}" ]]; then
			# shellcheck disable=SC2086 # Deliberate split into seconds and reason.
			set -- ${cooling}
			skipped+=("${name}:cooling-$2-${1}s")
			continue
		fi
	fi

	attempt=$((attempt + 1))
	out_file="$(mktemp)"
	err_file="$(mktemp)"
	rc=0
	"$(adapter_for "${name}")" "${run_args[@]}" >"${out_file}" 2>"${err_file}" || rc=$?

	if [[ "${rc}" -eq "${PIGGYBACK_EXIT_OK}" ]]; then
		piggyback_log "served by ${name} (attempt ${attempt})"
		[[ ${#skipped[@]} -gt 0 ]] && piggyback_log "skipped: ${skipped[*]}"
		if [[ "${as_json}" -eq 1 ]]; then
			jq -n --arg p "${name}" --rawfile a "${out_file}" \
				'{provider: $p, exit: 0, answer: $a}'
		else
			cat "${out_file}"
		fi
		rm -f "${out_file}" "${err_file}"
		exit "${PIGGYBACK_EXIT_OK}"
	fi

	reason="$(piggyback_exit_name "${rc}")"
	detail="$(head -c 400 "${err_file}" | tr '\n' ' ')"
	# A provider that names its own backoff overrides the per-outcome default.
	retry_after="$(sed -n 's/^piggyback-retry-after: \([0-9][0-9]*\)$/\1/p' "${err_file}" | head -1)"
	rm -f "${out_file}" "${err_file}"

	if piggyback_is_unavailable "${rc}"; then
		piggyback_log "${name}: ${reason} -- trying the next provider"
		# A stale model id is not an availability problem with the provider, so
		# it only cools down that model. Anything else is provider-wide.
		cooldown_target="${name}"
		if [[ "${rc}" -eq "${PIGGYBACK_EXIT_MISSING}" ]] &&
			[[ "$(piggyback_classify_failure "${detail}")" == 'stale-model' ]]; then
			cooldown_target="${model_key}"
		fi
		[[ "${no_cooldown}" -eq 0 ]] && piggyback_cooldown_set "${cooldown_target}" "${rc}" "${retry_after}"
		skipped+=("${name}:${reason}")
		continue
	fi

	# The provider answered about the task rather than refusing to serve. That
	# might mean the prompt is bad, or just that this provider is broken in a
	# way the classifier does not recognise, so keep going but bound it.
	failures=$((failures + 1))
	last_failure_rc="${rc}"
	last_failure_detail="${detail}"
	skipped+=("${name}:${reason}")
	if [[ "${failures}" -ge "${max_failures}" ]]; then
		piggyback_log "${name}: ${reason} -- stopping after ${failures} task failure(s)"
		printf '%s\n' "${detail}" >&2
		exit "${rc}"
	fi
	piggyback_log "${name}: ${reason} -- trying the next provider (${failures}/${max_failures})"
done

if [[ "${failures}" -gt 0 ]]; then
	piggyback_log "every provider that could serve failed on the task"
	[[ ${#skipped[@]} -gt 0 ]] && piggyback_log "chain: ${skipped[*]}"
	printf '%s\n' "${last_failure_detail}" >&2
	exit "${last_failure_rc}"
fi

piggyback_log "no provider could serve a ${capability} request"
[[ ${#skipped[@]} -gt 0 ]] && piggyback_log "chain: ${skipped[*]}"
exit "${PIGGYBACK_EXIT_NO_ROUTE}"
