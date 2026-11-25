#!/usr/bin/env bash
# Picks the Claude Code and Codex config directories (CLAUDE_CONFIG_DIR /
# CODEX_HOME) for a directory, from the owner of its repository. The fish hook
# in dotfiles and the Orca account-router plugin both call this, so the mapping
# lives in one machine-local file:
#
#   route acme client            # owner (GitHub user/org) -> account
#   route * personal               # every other directory
#   dir client claude /path/to/home  # account tool directory (rest of the line)
#   dir client codex /path/to/home
#
# The owner comes from the origin remote, else from a <ghq root>/<host>/<owner>/
# path. Owners match case-insensitively. Prints `account=`, `claude=` and
# `codex=` lines for the tools the account defines; prints nothing when the
# file or a matching route is missing.
set -euo pipefail

FILE="${AGENT_ACCOUNTS_FILE:-${XDG_CONFIG_HOME:-${HOME}/.config}/agent-accounts/config}"
GHQ_ROOT="${GHQ_ROOT:-${HOME}/ghq}"

usage() {
	cat <<'USAGE'
Usage: agent-account.sh [--dir <path>]

Prints the account and the Claude Code / Codex config directories for <path>
(default: the current directory).
USAGE
}

dir="${PWD}"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--dir)
		[[ $# -ge 2 ]] || {
			usage >&2
			exit 1
		}
		dir="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown arg: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

[[ -f "${FILE}" ]] || exit 0

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Owner from the origin remote: git@host:owner/repo, ssh://host/owner/repo, https://host/owner/repo.
owner_from_remote() {
	local url
	url="$(git -C "${dir}" remote get-url origin 2>/dev/null || true)"
	[[ -n "${url}" ]] || return 0
	case "${url}" in
	*://*)
		url="${url#*://}"
		url="${url#*/}"
		;;
	*:*) url="${url##*:}" ;;
	*) return 0 ;;
	esac
	[[ "${url}" == */* ]] && printf '%s\n' "${url%%/*}"
	return 0
}

# Owner from a <ghq root>/<host>/<owner>/... path, for clones without a remote yet.
owner_from_ghq_path() {
	local rest="${dir%/}/"
	[[ "${rest}" == "${GHQ_ROOT%/}/"* ]] || return 0
	rest="${rest#"${GHQ_ROOT%/}/"}"
	rest="${rest#*/}"
	[[ "${rest}" == */* ]] && printf '%s\n' "${rest%%/*}"
	return 0
}

owner="$(owner_from_remote)"
[[ -n "${owner}" ]] || owner="$(owner_from_ghq_path)"
owner_lc="$(lc "${owner}")"

account=""
fallback=""
while read -r kind key value _ || [[ -n "${kind}" ]]; do
	[[ "${kind}" == "route" && -n "${value}" ]] || continue
	if [[ "${key}" == "*" ]]; then
		fallback="${value}"
	elif [[ -n "${owner_lc}" && "$(lc "${key}")" == "${owner_lc}" ]]; then
		account="${value}"
	fi
done <"${FILE}"
account="${account:-${fallback}}"
[[ -n "${account}" ]] || exit 0

claude=""
codex=""
dir_line='^[[:space:]]*dir[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*[^[:space:]])[[:space:]]*$'
while IFS= read -r line || [[ -n "${line}" ]]; do
	[[ "${line}" =~ ${dir_line} ]] || continue
	[[ "${BASH_REMATCH[1]}" == "${account}" ]] || continue
	tool="${BASH_REMATCH[2]}"
	path="${BASH_REMATCH[3]}"
	if [[ "${path}" == *"'"* ]]; then
		echo "agent-account: directory must not contain a single quote: ${path}" >&2
		exit 1
	fi
	case "${tool}" in
	claude) claude="${path}" ;;
	codex) codex="${path}" ;;
	esac
done <"${FILE}"

printf 'account=%s\n' "${account}"
[[ -z "${claude}" ]] || printf 'claude=%s\n' "${claude}"
[[ -z "${codex}" ]] || printf 'codex=%s\n' "${codex}"
