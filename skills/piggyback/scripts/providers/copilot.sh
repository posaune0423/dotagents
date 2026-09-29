#!/usr/bin/env bash
# Provider adapter: GitHub Copilot CLI.
# Free plan: 50 chat/agent requests per month -- the smallest allowance in the
# chain, so it sits last among agentic providers.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${HERE}/../lib/common.sh"

PROVIDER=copilot

cmd_capabilities() { printf 'agentic\n'; }

resolve() { piggyback_resolve_bin "${PIGGYBACK_COPILOT_BIN:-}" copilot; }

cmd_probe() {
	local bin
	bin="$(resolve)" || {
		echo "copilot CLI is not installed (npm i -g @github/copilot)" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	}
	echo "binary: ${bin}"

	# Copilot exposes no auth-status command, and it can authenticate from the
	# system keychain, so absence of a token or config directory proves nothing.
	# Guessing "unauthenticated" here would sideline a working provider for the
	# whole auth cooldown, so an unverifiable state is reported as available and
	# a real auth failure is classified when the run happens.
	if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}${COPILOT_GITHUB_TOKEN:-}" ]]; then
		echo "auth: token"
	elif [[ -d "${HOME}/.copilot" ]]; then
		echo "auth: local config"
	else
		echo "auth: unverified (run 'copilot login' if requests fail)"
	fi
	return "${PIGGYBACK_EXIT_OK}"
}

cmd_run() {
	piggyback_parse_run_args "$@" || return $?
	local bin
	bin="$(resolve)" || return "${PIGGYBACK_EXIT_MISSING}"

	# -s prints the response alone; --no-ask-user stops the agent from blocking
	# on a question nobody is there to answer.
	local args=(-s --no-ask-user)
	[[ "${PIGGYBACK_WRITE}" -eq 1 ]] && args+=(--allow-all-tools)
	[[ -n "${PIGGYBACK_MODEL}" ]] && args+=(--model "${PIGGYBACK_MODEL}")
	[[ -n "${PIGGYBACK_WORKSPACE}" ]] && args+=(--add-dir "${PIGGYBACK_WORKSPACE}")
	args+=(-p "$(cat "${PIGGYBACK_PROMPT_FILE}")")

	local out_file
	out_file="$(mktemp)"
	local rc=0
	piggyback_run_with_timeout "${PIGGYBACK_TIMEOUT}" "${out_file}" "${bin}" "${args[@]}" || rc=$?

	local output
	output="$(cat "${out_file}")"
	rm -f "${out_file}"

	if [[ "${PIGGYBACK_TIMED_OUT}" -eq 1 ]]; then
		echo "copilot exceeded ${PIGGYBACK_TIMEOUT}s" >&2
		return "${PIGGYBACK_EXIT_TIMEOUT}"
	fi
	if [[ "${rc}" -ne 0 ]]; then
		printf '%s\n' "${output}" >&2
		return "$(piggyback_classify_exit "${output}")"
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
