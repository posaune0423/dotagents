#!/usr/bin/env bash
# Provider adapter: Cursor CLI (cursor-agent).
# Free tier: Hobby plan, "limited Agent requests"; Cursor publishes no numbers.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HERE}/../lib/common.sh"

PROVIDER=cursor

cmd_capabilities() { printf 'agentic\n'; }

resolve() { piggyback_resolve_bin "${PIGGYBACK_CURSOR_BIN:-}" cursor-agent; }

# `cursor-agent status` reports isAuthenticated:true from a stale token on disk
# while every real request fails, so `models` is checked as well. Neither call
# spends an agent request.
cmd_probe() {
	local bin
	bin="$(resolve)" || {
		echo "cursor-agent is not installed" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	}
	echo "binary: ${bin}"

	local status_out models_out models_rc=0
	status_out="$("${bin}" status --format json 2>&1 || true)"
	models_out="$("${bin}" models 2>&1)" || models_rc=$?
	echo "models: ${models_out}"

	if [[ "${models_rc}" -ne 0 ]]; then
		printf '%s\n' "${models_out}" >&2
		return "$(piggyback_classify_exit "${models_out}")"
	fi

	if [[ "${status_out}" != *'"isAuthenticated"'*'true'* ]]; then
		echo "cursor-agent is not authenticated; run 'cursor-agent login'" >&2
		return "${PIGGYBACK_EXIT_AUTH}"
	fi
	case "$(piggyback_classify_failure "${models_out}")" in
	auth)
		echo "cursor-agent exposes no usable models; run 'cursor-agent login'" >&2
		return "${PIGGYBACK_EXIT_AUTH}"
		;;
	quota)
		echo "cursor quota appears exhausted" >&2
		return "${PIGGYBACK_EXIT_QUOTA}"
		;;
	esac
	return "${PIGGYBACK_EXIT_OK}"
}

cmd_run() {
	piggyback_parse_run_args "$@" || return $?
	local bin
	bin="$(resolve)" || return "${PIGGYBACK_EXIT_MISSING}"

	# --trust answers the workspace-trust prompt, which blocks any headless run
	# in an untrusted directory -- read-only ones included. It grants no write
	# capability on its own; --force is what lets print mode apply changes.
	local args=(--print --output-format json --trust)
	if [[ "${PIGGYBACK_WRITE}" -eq 1 ]]; then
		args+=(--force)
	else
		args+=(--mode plan)
	fi
	# Always explicit, and 'auto' by default. cursor-agent persists --model
	# account-side, so a single named-model call would otherwise pin that choice
	# for every later run -- and a Free plan rejects named models outright
	# ("Named models unavailable. Free plans can only use Auto"), which would
	# leave the provider permanently failing. Sending it every time also repairs
	# a selection some other client left behind.
	args+=(--model "${PIGGYBACK_MODEL:-auto}")
	[[ -n "${PIGGYBACK_WORKSPACE}" ]] && args+=(--workspace "${PIGGYBACK_WORKSPACE}")
	args+=("$(cat "${PIGGYBACK_PROMPT_FILE}")")

	local out_file
	out_file="$(mktemp)"
	local rc=0
	piggyback_run_with_timeout "${PIGGYBACK_TIMEOUT}" "${out_file}" "${bin}" "${args[@]}" || rc=$?

	local output
	output="$(cat "${out_file}")"
	rm -f "${out_file}"

	if [[ "${PIGGYBACK_TIMED_OUT}" -eq 1 ]]; then
		echo "cursor-agent exceeded ${PIGGYBACK_TIMEOUT}s" >&2
		return "${PIGGYBACK_EXIT_TIMEOUT}"
	fi

	# cursor-agent can report failure inside a zero exit status.
	if [[ "${rc}" -ne 0 || "${output}" == *'"is_error"'*'true'* ]]; then
		printf '%s\n' "${output}" >&2
		return "$(piggyback_classify_exit "${output}")"
	fi

	if command -v jq >/dev/null 2>&1; then
		local answer
		if answer="$(printf '%s' "${output}" | jq -er '.result' 2>/dev/null)"; then
			printf '%s\n' "${answer}"
			return "${PIGGYBACK_EXIT_OK}"
		fi
	fi
	printf '%s\n' "${output}"
	return "${PIGGYBACK_EXIT_OK}"
}

case "${1:-}" in
capabilities) cmd_capabilities ;;
probe) cmd_probe ;;
run)
	shift
	cmd_run "$@"
	;;
*)
	echo "usage: ${PROVIDER} {capabilities|probe|run [options]}" >&2
	exit "${PIGGYBACK_EXIT_USAGE}"
	;;
esac
