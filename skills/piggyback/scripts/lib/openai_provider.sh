#!/usr/bin/env bash
# Reusable body for any provider that speaks the OpenAI chat-completions shape.
#
# This is the extensibility surface: a new hosted model that exposes an
# OpenAI-compatible endpoint needs only a ten-line adapter that sets the four
# variables below and calls piggyback_openai_provider_main.
#
# Required before sourcing:
#   PROVIDER          - provider id, must match the adapter filename
#   PIGGYBACK_BASE_URL       - endpoint root, e.g. https://api.groq.com/openai/v1
#   PIGGYBACK_KEY_VAR        - name of the env var holding the API key ('' if none)
#   PIGGYBACK_DEFAULT_MODEL  - model id used when the caller does not pass --model

piggyback_openai_key() {
	[[ -n "${PIGGYBACK_KEY_VAR}" ]] || return 0
	printf '%s' "${!PIGGYBACK_KEY_VAR:-}"
}

piggyback_openai_provider_capabilities() { printf 'inference\n'; }

piggyback_openai_provider_probe() {
	piggyback_parse_probe_args "$@" || return $?
	local want_model="${PIGGYBACK_PROBE_MODEL:-${PIGGYBACK_DEFAULT_MODEL}}"
	command -v curl >/dev/null 2>&1 || {
		echo "curl is required" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	}
	command -v jq >/dev/null 2>&1 || {
		echo "jq is required" >&2
		return "${PIGGYBACK_EXIT_MISSING}"
	}

	if [[ -n "${PIGGYBACK_KEY_VAR}" && -z "$(piggyback_openai_key)" ]]; then
		echo "${PROVIDER} has no API key; set ${PIGGYBACK_KEY_VAR}" >&2
		return "${PIGGYBACK_EXIT_AUTH}"
	fi

	# Listing models is free everywhere that implements it, so the probe never
	# spends an inference request.
	local key http_code body_file
	key="$(piggyback_openai_key)"
	body_file="$(mktemp)"
	http_code="$(curl -sS --max-time "${PIGGYBACK_PROBE_TIMEOUT:-10}" \
		-o "${body_file}" -w '%{http_code}' \
		${key:+-H "Authorization: Bearer ${key}"} \
		"${PIGGYBACK_BASE_URL%/}/models" 2>/dev/null || true)"
	local body
	body="$(cat "${body_file}")"
	rm -f "${body_file}"
	[[ -n "${http_code}" ]] || http_code='000'

	case "${http_code}" in
	2??)
		echo "endpoint: ${PIGGYBACK_BASE_URL}"
		# Provider model rosters change without notice. Checking the configured
		# default against the live list here costs nothing, whereas discovering
		# it during a run costs a request from a small allowance.
		if [[ -n "${want_model}" ]] && command -v jq >/dev/null 2>&1; then
			local ids
			ids="$(printf '%s' "${body}" | jq -r '.data[]?.id' 2>/dev/null || true)"
			if [[ -z "${ids//[[:space:]]/}" ]]; then
				echo "${PROVIDER}: could not read a model list from ${PIGGYBACK_BASE_URL%/}/models" >&2
				return "${PIGGYBACK_EXIT_MISSING}"
			fi
			if ! grep -Fxq -- "${want_model}" <<<"${ids}"; then
				echo "${PROVIDER}: model '${want_model}' is not available; pick one of: $(tr '\n' ' ' <<<"${ids}")" >&2
				return "${PIGGYBACK_EXIT_MISSING}"
			fi
		fi
		return "${PIGGYBACK_EXIT_OK}"
		;;
	401 | 403)
		echo "${PROVIDER} rejected the key (${http_code}); check ${PIGGYBACK_KEY_VAR}" >&2
		return "${PIGGYBACK_EXIT_AUTH}"
		;;
	429)
		echo "${PROVIDER} is rate limited" >&2
		return "${PIGGYBACK_EXIT_QUOTA}"
		;;
	000)
		echo "${PROVIDER} endpoint is unreachable: ${PIGGYBACK_BASE_URL}" >&2
		return "${PIGGYBACK_EXIT_TIMEOUT}"
		;;
	5??)
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_TIMEOUT}"
		;;
	*)
		printf '%s\n' "${body}" >&2
		return "${PIGGYBACK_EXIT_FAILED}"
		;;
	esac
}

piggyback_openai_provider_run() {
	piggyback_parse_run_args "$@" || return $?
	piggyback_reject_write "${PROVIDER}" || return $?

	if [[ -n "${PIGGYBACK_KEY_VAR}" && -z "$(piggyback_openai_key)" ]]; then
		echo "${PROVIDER} has no API key; set ${PIGGYBACK_KEY_VAR}" >&2
		return "${PIGGYBACK_EXIT_AUTH}"
	fi

	piggyback_openai_chat \
		"${PIGGYBACK_BASE_URL}" \
		"$(piggyback_openai_key)" \
		"${PIGGYBACK_MODEL:-${PIGGYBACK_DEFAULT_MODEL}}" \
		"${PIGGYBACK_PROMPT_FILE}" \
		"${PIGGYBACK_TIMEOUT}"
}

piggyback_openai_provider_main() {
	case "${1:-}" in
	capabilities) piggyback_openai_provider_capabilities ;;
	probe)
		shift
		piggyback_openai_provider_probe "$@"
		;;
	run)
		shift
		piggyback_openai_provider_run "$@"
		;;
	*)
		echo "usage: ${PROVIDER} {capabilities|probe|run [options]}" >&2
		return "${PIGGYBACK_EXIT_USAGE}"
		;;
	esac
}
