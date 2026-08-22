#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
relink-codex-prompts.sh

Reconfigure ~/.codex so:
  - ~/.codex/commands is removed
  - ~/.codex/prompts points to ~/.agents/commands
  - ~/.codex/hooks.json is linked to this repository's codex/hooks.json
  - ~/.codex/hooks is linked to this repository's codex/hooks

This is designed to make the current Codex-specific layout
reproducible on demand.
EOF
}

timestamp() { date +%Y%m%d-%H%M%S; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

main_checkout_root() {
	local common
	if common="$(git -C "${REPO_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
		dirname -- "${common}"
	else
		printf '%s\n' "${REPO_ROOT}"
	fi
}

SOURCE_ROOT="$(main_checkout_root)"

CODEX_DIR="${HOME}/.codex"
HOME_COMMANDS="${CODEX_DIR}/commands"
HOME_PROMPTS="${CODEX_DIR}/prompts"
HOME_HOOKS_JSON="${CODEX_DIR}/hooks.json"
HOME_HOOKS_DIR="${CODEX_DIR}/hooks"
SOURCE_COMMANDS="${HOME}/.agents/commands"
SOURCE_HOOKS_JSON="${SOURCE_ROOT}/codex/hooks.json"
SOURCE_HOOKS_DIR="${SOURCE_ROOT}/codex/hooks"

safe_link() {
	local src="$1"
	local dst="$2"

	if [[ -L "${dst}" ]]; then
		rm -f -- "${dst}"
		echo "Removed existing symlink: ${dst}"
	elif [[ -e "${dst}" ]]; then
		local backup
		backup="${dst}.bak.$(timestamp)"
		mv -- "${dst}" "${backup}"
		echo "Backed up existing path to ${backup}"
	fi

	mkdir -p "$(dirname -- "${dst}")"
	ln -s -- "${src}" "${dst}"
	echo "Linked: ${dst} -> ${src}"
}

main() {
	if [[ $# -gt 0 ]]; then
		if [[ "$1" == "-h" || "$1" == "--help" ]]; then
			usage
			exit 0
		fi
		usage >&2
		exit 2
	fi

	if [[ ! -d "${CODEX_DIR}" ]]; then
		mkdir -p "${CODEX_DIR}"
	fi

	if [[ ! -d "${SOURCE_COMMANDS}" ]]; then
		echo "ERROR: expected source directory missing: ${SOURCE_COMMANDS}" >&2
		exit 1
	fi
	if [[ ! -f "${SOURCE_HOOKS_JSON}" ]]; then
		echo "ERROR: expected source hooks config missing: ${SOURCE_HOOKS_JSON}" >&2
		exit 1
	fi
	if [[ ! -d "${SOURCE_HOOKS_DIR}" ]]; then
		echo "ERROR: expected source hooks directory missing: ${SOURCE_HOOKS_DIR}" >&2
		exit 1
	fi

	if [[ -e "${HOME_COMMANDS}" || -L "${HOME_COMMANDS}" ]]; then
		rm -rf -- "${HOME_COMMANDS}"
		echo "Removed: ${HOME_COMMANDS}"
	fi

	safe_link "${SOURCE_COMMANDS}" "${HOME_PROMPTS}"
	safe_link "${SOURCE_HOOKS_JSON}" "${HOME_HOOKS_JSON}"
	safe_link "${SOURCE_HOOKS_DIR}" "${HOME_HOOKS_DIR}"
}

main "$@"
