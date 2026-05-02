#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
relink-codex-prompts.sh

Reconfigure ~/.codex so:
  - ~/.codex/commands is removed
  - ~/.codex/prompts points to ~/.agents/commands

This is designed to make the current Codex-specific layout
reproducible on demand.
EOF
}

timestamp() { date +%Y%m%d-%H%M%S; }

CODEx_DIR="${HOME}/.codex"
HOME_COMMANDS="${CODEx_DIR}/commands"
HOME_PROMPTS="${CODEx_DIR}/prompts"
SOURCE_COMMANDS="${HOME}/.agents/commands"

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

	if [[ ! -d "${CODEx_DIR}" ]]; then
		mkdir -p "${CODEx_DIR}"
	fi

	if [[ ! -d "${SOURCE_COMMANDS}" ]]; then
		echo "ERROR: expected source directory missing: ${SOURCE_COMMANDS}" >&2
		exit 1
	fi

	if [[ -e "${HOME_COMMANDS}" || -L "${HOME_COMMANDS}" ]]; then
		rm -rf -- "${HOME_COMMANDS}"
		echo "Removed: ${HOME_COMMANDS}"
	fi

	safe_link "${SOURCE_COMMANDS}" "${HOME_PROMPTS}"
}

main "$@"
