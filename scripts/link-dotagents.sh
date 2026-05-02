#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
link-dotagents.sh --home [--all] [--tool-configs]

Create symlinks from this repo (SSoT) into:
  - ~/.agents (global agent config)
  - optionally ~/.claude/CLAUDE.md, ~/.claude/settings.json, and ~/.gemini/GEMINI.md

Options:
  --home           Link repo skills into ~/.agents/skills
  --all            Also link commands and rules into ~/.agents (use with --home)
  --tool-configs   Symlink CLAUDE.md, settings.json (Claude), and GEMINI.md to this repo's copies
  -h, --help       Show this help

At least one of --home or --tool-configs is required.

Behavior:
  - If destination exists and is not a symlink, it is moved aside as a timestamped backup.
  - If destination is a symlink, it is replaced.
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

DO_HOME=false
HOME_ALL=false
DO_TOOL_CONFIGS=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--home)
		DO_HOME=true
		shift
		;;
	--all)
		HOME_ALL=true
		shift
		;;
	--tool-configs)
		DO_TOOL_CONFIGS=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

timestamp() { date +"%Y%m%d-%H%M%S"; }

ensure_parent_dir() {
	local path="$1"
	mkdir -p "$(dirname -- "${path}")"
}

safe_link() {
	local src="$1"
	local dst="$2"

	if [[ ! -e "${src}" ]]; then
		echo "ERROR: source missing: ${src}" >&2
		exit 1
	fi

	ensure_parent_dir "${dst}"

	if [[ -L "${dst}" ]]; then
		rm -f -- "${dst}"
	elif [[ -e "${dst}" ]]; then
		local backup
		backup="${dst}.bak.$(timestamp)"
		mv -- "${dst}" "${backup}"
		echo "Moved existing path to backup: ${backup}"
	fi

	ln -s -- "${src}" "${dst}"
	echo "Linked: ${dst} -> ${src}"
}

link_home() {
	local base="${HOME}/.agents"
	mkdir -p "${base}"

	safe_link "${REPO_ROOT}/skills" "${base}/skills"
	if [[ "${HOME_ALL}" == "true" ]]; then
		safe_link "${REPO_ROOT}/commands" "${base}/commands"
		safe_link "${REPO_ROOT}/rules" "${base}/rules"
	fi
}

did_something=false

if [[ "${DO_HOME}" == "true" ]]; then
	link_home
	did_something=true
fi

link_tool_instruction_files() {
	local claude_md_src="${REPO_ROOT}/.claude/CLAUDE.md"
	local claude_settings_src="${REPO_ROOT}/.claude/settings.json"
	local gemini_md_src="${REPO_ROOT}/.gemini/GEMINI.md"
	if [[ ! -f "${claude_md_src}" ]]; then
		echo "ERROR: expected file missing: ${claude_md_src}" >&2
		exit 1
	fi
	if [[ ! -f "${claude_settings_src}" ]]; then
		echo "ERROR: expected file missing: ${claude_settings_src}" >&2
		exit 1
	fi
	if [[ ! -f "${gemini_md_src}" ]]; then
		echo "ERROR: expected file missing: ${gemini_md_src}" >&2
		exit 1
	fi
	mkdir -p -- "${HOME}/.claude" "${HOME}/.gemini"
	safe_link "${claude_md_src}" "${HOME}/.claude/CLAUDE.md"
	safe_link "${claude_settings_src}" "${HOME}/.claude/settings.json"
	safe_link "${gemini_md_src}" "${HOME}/.gemini/GEMINI.md"
}

if [[ "${DO_TOOL_CONFIGS}" == "true" ]]; then
	link_tool_instruction_files
	did_something=true
fi

if [[ "${did_something}" == "false" ]]; then
	usage >&2
	exit 2
fi
