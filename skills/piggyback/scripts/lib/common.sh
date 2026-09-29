#!/usr/bin/env bash
# Shared contract for piggyback: exit codes, outcome classification, the
# timeout watchdog, and per-provider cooldown state.
#
# Sourced by the router and by every provider adapter. Nothing here calls a
# provider directly; keeping the vocabulary in one file is what lets a new
# adapter be written without touching the router.

# --- exit-code contract ------------------------------------------------------
# Every adapter and the router itself speak exactly these codes.
PIGGYBACK_EXIT_OK=0       # success; the answer is on stdout
PIGGYBACK_EXIT_FAILED=1   # the provider ran and failed for its own reasons
PIGGYBACK_EXIT_USAGE=2    # bad arguments
PIGGYBACK_EXIT_QUOTA=3    # free allowance or rate limit exhausted
PIGGYBACK_EXIT_AUTH=4     # not authenticated, or the account exposes nothing usable
PIGGYBACK_EXIT_MISSING=5  # the provider's binary or dependency is not installed
PIGGYBACK_EXIT_TIMEOUT=6  # the provider exceeded its wall-clock budget
PIGGYBACK_EXIT_NO_ROUTE=7 # router-only: every provider in the chain was unavailable
export PIGGYBACK_EXIT_OK PIGGYBACK_EXIT_FAILED PIGGYBACK_EXIT_USAGE PIGGYBACK_EXIT_QUOTA
export PIGGYBACK_EXIT_AUTH PIGGYBACK_EXIT_MISSING PIGGYBACK_EXIT_TIMEOUT PIGGYBACK_EXIT_NO_ROUTE

# Codes that mean "this provider cannot serve requests right now". The router
# advances to the next provider on these and only these; anything else is a
# genuine answer about the task and must not be retried elsewhere.
piggyback_is_unavailable() {
	case "$1" in
	"${PIGGYBACK_EXIT_QUOTA}" | "${PIGGYBACK_EXIT_AUTH}" | "${PIGGYBACK_EXIT_MISSING}" | "${PIGGYBACK_EXIT_TIMEOUT}") return 0 ;;
	*) return 1 ;;
	esac
}

piggyback_exit_name() {
	case "$1" in
	0) printf 'ok' ;;
	1) printf 'failed' ;;
	2) printf 'usage' ;;
	3) printf 'quota' ;;
	4) printf 'auth' ;;
	5) printf 'missing' ;;
	6) printf 'timeout' ;;
	7) printf 'no-route' ;;
	*) printf 'unknown' ;;
	esac
}

piggyback_log() {
	[[ -n "${PIGGYBACK_QUIET:-}" ]] && return 0
	printf 'piggyback: %s\n' "$*" >&2
}

# --- .env ---------------------------------------------------------------------
# Provider keys live in the skill's own .env, which the repository root already
# gitignores. Loaded here so every adapter and the router see the same values
# without the caller having to export anything.
#
# The file is parsed, not sourced: it is configuration, and sourcing it would
# execute whatever it contains. Anything already exported wins, so a real
# environment variable always overrides the file.
piggyback_load_env_file() {
	local file="${PIGGYBACK_ENV_FILE:-}"
	if [[ -z "${file}" ]]; then
		file="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.env"
	fi
	[[ -f "${file}" ]] || return 0

	local line key value
	while IFS= read -r line || [[ -n "${line}" ]]; do
		line="${line%%$'\r'}"
		[[ "${line}" =~ ^[[:space:]]*# ]] && continue
		[[ "${line}" =~ ^[[:space:]]*$ ]] && continue
		[[ "${line}" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue

		key="${BASH_REMATCH[2]}"
		value="${BASH_REMATCH[3]}"
		# Strip one matching pair of surrounding quotes.
		if [[ "${value}" =~ ^\"(.*)\"$ ]] || [[ "${value}" =~ ^\'(.*)\'$ ]]; then
			value="${BASH_REMATCH[1]}"
		fi

		[[ -z "${value}" ]] && continue
		[[ -n "${!key:-}" ]] && continue
		export "${key}=${value}"
	done <"${file}"
}

piggyback_load_env_file

# --- outcome classification --------------------------------------------------
# Matched case-insensitively against a provider's combined stdout/stderr.
#
# Auth markers are checked first because they are specific phrases, while the
# quota vocabulary is broad enough to appear inside an auth message.
#
# Classification runs ONLY on a failed invocation. Some CLIs log transient
# "quota exhausted" lines during successful internal retries -- Gemini CLI does
# this in headless mode -- so scanning the transcript of a successful run would
# take working providers out of the chain for hours.
PIGGYBACK_AUTH_PATTERNS=(
	'authentication required'
	'authentication failed'
	'error authenticating'
	'ineligibletier'
	'actionrequirederror'
	'named models unavailable'
	'upgrade plans'
	'no longer supported'
	'not authenticated'
	'not logged in'
	'please log in'
	'please login'
	'agent login'
	'unauthorized'
	'401'
	'403'
	'invalid api key'
	'invalid_api_key'
	'no api key'
	'api key not found'
	'no models available'
	'no access token'
	'credentials'
)

PIGGYBACK_QUOTA_PATTERNS=(
	'rate limit'
	'rate_limit'
	'ratelimit'
	'usage limit'
	'request limit'
	'requests limit'
	'free requests'
	'too many requests'
	'429'
	'quota'
	'resource_exhausted'
	'resource exhausted'
	'out of credits'
	'insufficient credits'
	'insufficient_quota'
	'reached your limit'
	'hit your limit'
	'exceeded your'
	'upgrade to pro'
	'upgrade your plan'
	'monthly limit'
	'daily limit'
)

PIGGYBACK_STALE_MODEL_PATTERNS=(
	'model_not_found'
	'model not found'
	'unknown model'
	'invalid model'
	'does not exist or you do not have access'
)

PIGGYBACK_UNAVAILABLE_PATTERNS=(
	'service unavailable'
	'temporarily unavailable'
	'currently unavailable'
	'retirement'
	'brownout'
	'bad gateway'
	'gateway timeout'
	'overloaded'
	'410'
	'502'
	'503'
	'504'
)

piggyback_matches_any() {
	local haystack="$1"
	shift
	local needle
	for needle in "$@"; do
		if [[ "${haystack}" == *"${needle}"* ]]; then
			return 0
		fi
	done
	return 1
}

# Echoes one of: stale-model | auth | quota | unavailable | failed
piggyback_classify_failure() {
	local lowered
	lowered="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

	if piggyback_matches_any "${lowered}" "${PIGGYBACK_STALE_MODEL_PATTERNS[@]}"; then
		printf 'stale-model'
	elif piggyback_matches_any "${lowered}" "${PIGGYBACK_AUTH_PATTERNS[@]}"; then
		printf 'auth'
	elif piggyback_matches_any "${lowered}" "${PIGGYBACK_QUOTA_PATTERNS[@]}"; then
		printf 'quota'
	elif piggyback_matches_any "${lowered}" "${PIGGYBACK_UNAVAILABLE_PATTERNS[@]}"; then
		printf 'unavailable'
	else
		printf 'failed'
	fi
}

# Maps classify output to the exit-code contract. 'unavailable' lands on the
# timeout code because that is the contract's short-cooldown transient bucket.
piggyback_classify_exit() {
	case "$(piggyback_classify_failure "$1")" in
	stale-model) printf '%s' "${PIGGYBACK_EXIT_MISSING}" ;;
	auth) printf '%s' "${PIGGYBACK_EXIT_AUTH}" ;;
	quota) printf '%s' "${PIGGYBACK_EXIT_QUOTA}" ;;
	unavailable) printf '%s' "${PIGGYBACK_EXIT_TIMEOUT}" ;;
	*) printf '%s' "${PIGGYBACK_EXIT_FAILED}" ;;
	esac
}

# --- timeout -----------------------------------------------------------------
# macOS ships no coreutils `timeout`, so the watchdog is inlined rather than
# depending on gtimeout being installed.
#
# Sets PIGGYBACK_TIMED_OUT=1 when it had to kill the child.
piggyback_run_with_timeout() {
	local secs="$1"
	local out_file="$2"
	shift 2

	# Read back by the caller after this returns.
	# shellcheck disable=SC2034
	PIGGYBACK_TIMED_OUT=0
	local flag_file
	flag_file="$(mktemp)"

	"$@" >"${out_file}" 2>&1 &
	local child_pid=$!

	(
		local waited=0
		while kill -0 "${child_pid}" 2>/dev/null; do
			if [[ "${waited}" -ge "${secs}" ]]; then
				printf 'timeout' >"${flag_file}"
				kill -TERM "${child_pid}" 2>/dev/null || true
				sleep 3
				kill -KILL "${child_pid}" 2>/dev/null || true
				exit 0
			fi
			sleep 1
			waited=$((waited + 1))
		done
	) &
	local watchdog_pid=$!

	local rc=0
	wait "${child_pid}" || rc=$?
	kill "${watchdog_pid}" 2>/dev/null || true
	wait "${watchdog_pid}" 2>/dev/null || true

	if [[ -s "${flag_file}" ]]; then
		# shellcheck disable=SC2034 # Read back by the calling adapter.
		PIGGYBACK_TIMED_OUT=1
	fi
	rm -f "${flag_file}"

	return "${rc}"
}

# --- cooldown state ----------------------------------------------------------
# A provider that just reported an exhausted allowance will report it again on
# the next task. Without a cooldown every request pays the latency of walking
# the dead part of the chain, which is the main cost of stitching small free
# tiers together.
#
# State is one file per provider holding an epoch-seconds expiry. No JSON, so
# no jq dependency on the hot path.
piggyback_state_dir() {
	printf '%s' "${PIGGYBACK_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/piggyback}"
}

piggyback_now() {
	printf '%s' "${PIGGYBACK_NOW:-$(date +%s)}"
}

# Cooldown length per outcome. Daily allowances reset on their own schedule, so
# these are deliberately shorter than a day: a wrong guess costs one wasted
# probe, while too long a cooldown silently removes a recovered provider.
piggyback_cooldown_seconds() {
	case "$1" in
	"${PIGGYBACK_EXIT_QUOTA}") printf '%s' "${PIGGYBACK_COOLDOWN_QUOTA:-3600}" ;;
	"${PIGGYBACK_EXIT_AUTH}") printf '%s' "${PIGGYBACK_COOLDOWN_AUTH:-900}" ;;
	"${PIGGYBACK_EXIT_MISSING}") printf '%s' "${PIGGYBACK_COOLDOWN_MISSING:-3600}" ;;
	"${PIGGYBACK_EXIT_TIMEOUT}") printf '%s' "${PIGGYBACK_COOLDOWN_TIMEOUT:-600}" ;;
	*) printf '0' ;;
	esac
}

# An explicit third argument overrides the per-outcome default. Providers that
# tell you how long to wait know better than a fixed table does.
# Builds the cooldown key. A model-scoped key is used only for failures that are
# about the model itself; everything else is a property of the provider.
piggyback_cooldown_key() {
	local provider="$1" model="${2:-}"
	if [[ -z "${model}" ]]; then
		printf '%s' "${provider}"
		return
	fi
	# Model ids carry slashes and colons, which cannot go in a filename.
	printf '%s@%s' "${provider}" "${model//[^A-Za-z0-9._-]/_}"
}

piggyback_cooldown_set() {
	local provider="$1"
	local code="$2"
	local override="${3:-}"
	local seconds
	if [[ "${override}" =~ ^[0-9]+$ ]]; then
		seconds="${override}"
	else
		seconds="$(piggyback_cooldown_seconds "${code}")"
	fi
	[[ "${seconds}" -gt 0 ]] || return 0

	local dir
	dir="$(piggyback_state_dir)"
	mkdir -p "${dir}"
	printf '%s %s\n' "$(($(piggyback_now) + seconds))" "$(piggyback_exit_name "${code}")" >"${dir}/${provider}.cooldown"
}

# Exits 0 when the provider is cooling down, and echoes the remaining seconds
# plus the reason.
piggyback_cooldown_active() {
	local provider="$1"
	local file
	file="$(piggyback_state_dir)/${provider}.cooldown"
	[[ -f "${file}" ]] || return 1

	local until reason
	read -r until reason <"${file}" || return 1
	[[ "${until}" =~ ^[0-9]+$ ]] || return 1

	local now
	now="$(piggyback_now)"
	if [[ "${now}" -ge "${until}" ]]; then
		rm -f "${file}"
		return 1
	fi

	printf '%s %s' "$((until - now))" "${reason}"
	return 0
}

piggyback_cooldown_clear() {
	local provider="${1:-}"
	local dir
	dir="$(piggyback_state_dir)"
	if [[ -n "${provider}" ]]; then
		rm -f "${dir}/${provider}.cooldown"
	else
		rm -f "${dir}"/*.cooldown 2>/dev/null || true
	fi
}

# --- OpenAI-compatible chat completion ---------------------------------------
# Every hosted inference provider worth adding speaks this shape, so the
# adapters for Groq, OpenRouter, Mistral, and a local server differ only in
# base URL, key variable, and default model.
#
# Usage: piggyback_openai_chat <base_url> <api_key> <model> <prompt_file> <timeout>
# Prints the assistant message on success; prints the raw body on failure.
piggyback_openai_chat() {
	local base_url="$1"
	local api_key="$2"
	local model="$3"
	local prompt_file="$4"
	local timeout_secs="$5"

	command -v curl >/dev/null 2>&1 || {
		echo "curl is required" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	}
	command -v jq >/dev/null 2>&1 || {
		echo "jq is required" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	}

	local body_file
	body_file="$(mktemp)"
	jq -n --arg model "${model}" --rawfile prompt "${prompt_file}" \
		'{model: $model, messages: [{role: "user", content: $prompt}]}' >"${body_file}"

	local out_file err_file
	out_file="$(mktemp)"
	err_file="$(mktemp)"
	local http_code
	http_code="$(curl -sS --max-time "${timeout_secs}" \
		-o "${out_file}" -w '%{http_code}' \
		-H 'Content-Type: application/json' \
		${api_key:+-H "Authorization: Bearer ${api_key}"} \
		-X POST "${base_url%/}/chat/completions" \
		--data-binary "@${body_file}" 2>"${err_file}" || true)"

	local body
	body="$(cat "${out_file}")$(cat "${err_file}")"
	rm -f "${body_file}" "${out_file}" "${err_file}"
	[[ -n "${http_code}" ]] || http_code='000'

	case "${http_code}" in
	2??)
		local answer
		if answer="$(printf '%s' "${body}" | jq -er '.choices[0].message.content' 2>/dev/null)"; then
			printf '%s\n' "${answer}"
			return "${PIGGYBACK_EXIT_OK}"
		fi
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_FAILED}"
		;;
	429)
		local retry_after
		retry_after="$(printf '%s' "${body}" |
			jq -er '.error.metadata.retry_after_seconds // .retry_after_seconds // empty' 2>/dev/null || true)"
		if [[ "${retry_after}" =~ ^[0-9]+$ ]]; then
			# Read back by the router to size the cooldown.
			echo "piggyback-retry-after: ${retry_after}" >&2
		fi
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_QUOTA}"
		;;
	404)
		# Almost always a model id that the account cannot see. Rosters change
		# without notice, so this has to move the router on rather than stop it.
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
		;;
	401 | 403)
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_AUTH}"
		;;
	000)
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_TIMEOUT}"
		;;
	5??)
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_TIMEOUT}"
		;;
	*)
		printf '%s\n' "${body}" >&2
		return "$(piggyback_classify_exit "${body}")"
		;;
	esac
}

# --- adapter argument parsing ------------------------------------------------
# Every adapter accepts the same `run` options, so the parsing lives here and
# an adapter only implements what actually differs: how to call its provider.
#
# Sets PIGGYBACK_PROMPT_FILE, PIGGYBACK_WRITE, PIGGYBACK_MODEL, PIGGYBACK_WORKSPACE, PIGGYBACK_TIMEOUT.
# shellcheck disable=SC2034 # Consumed by the adapter that called this.
piggyback_parse_run_args() {
	PIGGYBACK_PROMPT_FILE=''
	PIGGYBACK_WRITE=0
	PIGGYBACK_MODEL=''
	PIGGYBACK_WORKSPACE=''
	PIGGYBACK_TIMEOUT="${PIGGYBACK_TIMEOUT:-900}"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--prompt-file | --model | --workspace | --timeout)
			if [[ $# -lt 2 ]]; then
				echo "$1 needs a value" >&2
				return "${PIGGYBACK_EXIT_USAGE}"
			fi
			case "$1" in
			--prompt-file) PIGGYBACK_PROMPT_FILE="$2" ;;
			--model) PIGGYBACK_MODEL="$2" ;;
			--workspace) PIGGYBACK_WORKSPACE="$2" ;;
			--timeout) PIGGYBACK_TIMEOUT="$2" ;;
			esac
			shift 2
			;;
		--write)
			PIGGYBACK_WRITE=1
			shift
			;;
		*)
			echo "unknown run option: $1" >&2
			return "${PIGGYBACK_EXIT_USAGE}"
			;;
		esac
	done

	if [[ -z "${PIGGYBACK_PROMPT_FILE}" || ! -f "${PIGGYBACK_PROMPT_FILE}" ]]; then
		echo "--prompt-file is required and must exist" >&2
		return "${PIGGYBACK_EXIT_USAGE}"
	fi
	return 0
}

# Reads an optional `--model <id>` out of a probe's arguments. Probing is not
# obliged to look at it, but any adapter that can check cheaply should.
# shellcheck disable=SC2034 # Read back by the adapter that called this.
piggyback_parse_probe_args() {
	PIGGYBACK_PROBE_MODEL=''
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--model)
			[[ $# -ge 2 ]] || {
				echo "--model needs a value" >&2
				return "${PIGGYBACK_EXIT_USAGE}"
			}
			PIGGYBACK_PROBE_MODEL="$2"
			shift 2
			;;
		*) shift ;;
		esac
	done
	return 0
}

# Adapters that cannot edit files must refuse a write request rather than
# silently answering with a description of the change they did not make.
piggyback_reject_write() {
	if [[ "${PIGGYBACK_WRITE}" -eq 1 ]]; then
		echo "$1 cannot edit files; it is an inference-only provider" >&2
		return "${PIGGYBACK_EXIT_USAGE}"
	fi
	return 0
}

# Resolve a provider binary, honouring a per-provider override variable.
# Usage: piggyback_resolve_bin <override-value> <default-name>
piggyback_resolve_bin() {
	local override="$1"
	local default_name="$2"
	local candidate="${override}"

	if [[ -z "${candidate}" ]]; then
		candidate="$(command -v "${default_name}" 2>/dev/null || true)"
	fi
	if [[ -z "${candidate}" || ! -x "${candidate}" ]]; then
		return 1
	fi
	printf '%s' "${candidate}"
}
