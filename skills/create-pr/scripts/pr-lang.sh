#!/usr/bin/env bash
# Per-repository language for PR titles and bodies. Default is English, so
# only non-English repos need an entry. Entries live in a machine-local,
# gitignored file next to this skill (shared by every project through the
# ~/.agents/skills link):
#
#   owner ja          # every repo of that user or org
#   owner/repo ja     # one repo; wins over the owner line
#
# Matching is case-insensitive. Prints the language tag; `en` when nothing matches.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="${PR_LANG_FILE:-${SCRIPT_DIR}/../pr-lang.local}"

usage() {
	cat <<'USAGE'
Usage: pr-lang.sh [--repo owner/repo]
       pr-lang.sh --set <lang> [--for owner | --for owner/repo]

Prints the PR language for the current repository (default: en).
--set stores <lang> for the current repository, or for --for's owner or owner/repo.
USAGE
}

set_lang=""
target=""
repo=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--set)
		[[ $# -ge 2 ]] || {
			usage >&2
			exit 1
		}
		set_lang="$2"
		shift 2
		;;
	--for)
		[[ $# -ge 2 ]] || {
			usage >&2
			exit 1
		}
		target="$2"
		shift 2
		;;
	--repo)
		[[ $# -ge 2 ]] || {
			usage >&2
			exit 1
		}
		repo="$2"
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

# owner/repo from the origin remote; empty when there is none.
detect_repo() {
	local url
	url="$(git remote get-url origin 2>/dev/null || true)"
	[[ -n "${url}" ]] || return 0
	url="${url%.git}"
	url="${url%/}"
	case "${url}" in
	*://*)
		url="${url#*://}" # host/owner/repo
		url="${url#*/}"
		;;
	*:*) url="${url##*:}" ;; # git@host:owner/repo
	esac
	local owner="${url%%/*}"
	local name="${url##*/}"
	[[ -n "${owner}" && -n "${name}" && "${owner}" != "${name}" ]] && printf '%s/%s\n' "${owner}" "${name}"
	return 0
}

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

if [[ -z "${repo}" ]]; then
	repo="$(detect_repo)"
fi

if [[ -n "${set_lang}" ]]; then
	[[ "${set_lang}" =~ ^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$ ]] || {
		echo "Language must be a tag like en, ja, zh-TW (got: ${set_lang})" >&2
		exit 1
	}
	key="${target:-${repo}}"
	[[ -n "${key}" ]] || {
		echo "Cannot determine the repository; pass --for owner/repo." >&2
		exit 1
	}
	[[ "${key}" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?$ ]] || {
		echo "Key must be owner or owner/repo (got: ${key})" >&2
		exit 1
	}
	mkdir -p "$(dirname "${FILE}")"
	touch "${FILE}"
	tmp="$(mktemp)"
	key_lc="$(lc "${key}")"
	while IFS= read -r line || [[ -n "${line}" ]]; do
		entry="${line%% *}"
		if [[ -n "${entry}" && "${entry}" != \#* && "$(lc "${entry}")" == "${key_lc}" ]]; then
			continue
		fi
		printf '%s\n' "${line}"
	done <"${FILE}" >"${tmp}"
	printf '%s %s\n' "${key}" "${set_lang}" >>"${tmp}"
	mv "${tmp}" "${FILE}"
	echo "PR language for ${key}: ${set_lang} (${FILE})"
	exit 0
fi

lang="en"
if [[ -n "${repo}" && -f "${FILE}" ]]; then
	repo_lc="$(lc "${repo}")"
	owner_lc="${repo_lc%%/*}"
	owner_hit=""
	repo_hit=""
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ -n "${line}" && "${line}" != \#* ]] || continue
		entry="$(lc "${line%% *}")"
		value="${line#* }"
		value="${value%% *}"
		[[ -n "${value}" && "${value}" != "${line}" ]] || continue
		if [[ "${entry}" == "${repo_lc}" ]]; then
			repo_hit="${value}"
		elif [[ "${entry}" == "${owner_lc}" ]]; then
			owner_hit="${value}"
		fi
	done <"${FILE}"
	if [[ -n "${repo_hit}" ]]; then
		lang="${repo_hit}"
	elif [[ -n "${owner_hit}" ]]; then
		lang="${owner_hit}"
	fi
fi
printf '%s\n' "${lang}"
