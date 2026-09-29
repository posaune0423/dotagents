#!/usr/bin/env bash
# Provider adapter: Google Antigravity CLI (agy).
#
# Replaces the gemini-cli adapter: Gemini Code Assist's OAuth tier for
# individuals was discontinued and now answers IneligibleTierError telling you
# to migrate here. Free access covers Gemini Flash/Pro, Claude Sonnet/Opus 4.6,
# and GPT-OSS under rate limits Google does not publish.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HERE}/../lib/common.sh"

PROVIDER=antigravity

cmd_capabilities() { printf 'agentic\n'; }

resolve() { piggyback_resolve_bin "${PIGGYBACK_AGY_BIN:-}" agy; }

# `agy models` needs auth but spends no agent request, so it is a real
# availability check rather than the credentials-on-disk guess the gemini
# adapter had to make.
cmd_probe() {
	piggyback_parse_probe_args "$@" || return $?
	local bin
	bin="$(resolve)" || {
		echo "agy is not installed (see https://antigravity.google/docs/cli)" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	}
	echo "binary: ${bin}"

	local models rc=0
	models="$("${bin}" models 2>&1)" || rc=$?
	if [[ "${rc}" -ne 0 ]]; then
		printf '%s\n' "${models}" >&2
		return "$(piggyback_classify_exit "${models}")"
	fi
	# A model listing that came back empty means the account resolves but
	# exposes nothing usable, which is an entitlement problem, not a task one.
	if ! printf '%s' "${models}" | grep -qE '^[a-z0-9][a-z0-9.-]*[[:space:]]'; then
		echo "agy returned no usable models; run 'agy login'" >&2
		return "${PIGGYBACK_EXIT_AUTH}"
	fi
	# A model the account cannot see is the failure probing exists to catch.
	if [[ -n "${PIGGYBACK_PROBE_MODEL}" ]] &&
		! printf '%s' "${models}" | cut -f1 | grep -Fxq -- "${PIGGYBACK_PROBE_MODEL}"; then
		echo "agy does not offer '${PIGGYBACK_PROBE_MODEL}' on this account" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	fi
	echo "models: $(printf '%s' "${models}" | grep -cE '^[a-z0-9][a-z0-9.-]*[[:space:]]') available${PIGGYBACK_PROBE_MODEL:+, ${PIGGYBACK_PROBE_MODEL} ok}"
	return "${PIGGYBACK_EXIT_OK}"
}

cmd_run() {
	piggyback_parse_run_args "$@" || return $?
	local bin
	bin="$(resolve)" || return "${PIGGYBACK_EXIT_MISSING}"

	# --print takes the prompt as its value, so it must be attached with '='.
	# Passing it bare makes agy swallow the next flag as the prompt and silently
	# ignore the real one.
	local args=(--output-format json --print-timeout "${PIGGYBACK_TIMEOUT}s")
	if [[ "${PIGGYBACK_WRITE}" -eq 1 ]]; then
		# accept-edits still gates shell commands behind approval prompts that
		# nobody is present to answer, so headless writes need both.
		args+=(--mode accept-edits --dangerously-skip-permissions)
	else
		args+=(--mode plan)
	fi
	# Left unset by default: the free tier's model mix changes, and the session
	# default is whatever the account is actually entitled to.
	[[ -n "${PIGGYBACK_MODEL}" ]] && args+=(--model "${PIGGYBACK_MODEL}")
	[[ -n "${PIGGYBACK_WORKSPACE}" ]] && args+=(--add-dir "${PIGGYBACK_WORKSPACE}")
	args+=("--print=$(cat "${PIGGYBACK_PROMPT_FILE}")")

	# stdout and stderr are kept apart: agy prints its JSON envelope on stdout and
	# diagnostics on stderr, and merging them makes the envelope unparseable.
	local out_file err_file
	out_file="$(mktemp)"
	err_file="$(mktemp)"
	local rc=0
	(
		[[ -n "${PIGGYBACK_WORKSPACE}" ]] && cd "${PIGGYBACK_WORKSPACE}"
		exec "${bin}" "${args[@]}"
	) >"${out_file}" 2>"${err_file}" &
	local pid=$!
	wait "${pid}" || rc=$?

	local output diagnostics
	output="$(cat "${out_file}")"
	diagnostics="$(cat "${err_file}")"
	rm -f "${out_file}" "${err_file}"

	# Classified only on a non-zero exit: a transcript can mention a rate limit
	# it already retried past, and cooling down a working provider for an hour
	# over that is worse than missing the signal.
	if [[ "${rc}" -ne 0 ]]; then
		printf '%s\n%s\n' "${output}" "${diagnostics}" >&2
		return "$(piggyback_classify_exit "${output}${diagnostics}")"
	fi

	if command -v jq >/dev/null 2>&1; then
		local answer
		answer="$(printf '%s' "${output}" | jq -r '.response // .structured_output // ""' 2>/dev/null || printf '')"
		if [[ -n "${answer//[[:space:]]/}" ]]; then
			printf '%s\n' "${answer}"
			return "${PIGGYBACK_EXIT_OK}"
		fi

		# An empty response is not an answer, whatever the status field says.
		# It usually means headless mode auto-denied a tool agy wanted to use.
		local denied
		denied="$(printf '%s' "${output}" | jq -r '[.denied_actions[]?.display_name] | join(", ")' 2>/dev/null || printf '')"
		if [[ -n "${denied}" ]]; then
			echo "agy produced no answer: headless mode denied ${denied}" >&2
		else
			echo "agy produced no answer" >&2
		fi
		printf '%s\n%s\n' "${output}" "${diagnostics}" >&2
		return "${PIGGYBACK_EXIT_FAILED}"
	fi

	if [[ -z "${output//[[:space:]]/}" ]]; then
		echo "agy produced no output" >&2
		return "${PIGGYBACK_EXIT_FAILED}"
	fi
	printf '%s\n' "${output}"
	return "${PIGGYBACK_EXIT_OK}"
}

case "${1:-}" in
capabilities) cmd_capabilities ;;
probe)
	shift
	cmd_probe "$@"
	;;
run)
	shift
	cmd_run "$@"
	;;
*)
	echo "usage: ${PROVIDER} {capabilities|probe|run [options]}" >&2
	exit "${PIGGYBACK_EXIT_USAGE}"
	;;
esac
