#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
link-project-agents.sh --target <project-root> [--no-import-global] [--cursor] [--codex] [--claude]

Project layout:
  <project>/.agents/        project-specific config (you may edit/commit this)
  ~/.agents/               global config managed by dotagents (SSoT)

This script:
  - Ensures <project>/.agents/{skills,commands,rules} exist
  - (default) Imports global entries by symlinking missing items from ~/.agents into <project>/.agents
    - local entries win (if <project>/.agents already has a name, it is not replaced)
  - Symlinks each agent tool dir to <project>/.agents:
      <project>/.cursor/{skills,commands,rules} -> <project>/.agents/{...}
      <project>/.codex/{skills,commands,rules}  -> <project>/.agents/{...}
      <project>/.claude/{skills,commands,rules} -> <project>/.agents/{...}

Options:
  --target <dir>        Project root (required)
  --no-import-global    Do not import from ~/.agents
  --cursor              Link .cursor (default on when --target given)
  --codex               Link .codex  (default on when --target given)
  --claude              Link .claude (default on when --target given)
EOF
}

timestamp() { date +"%Y%m%d-%H%M%S"; }

ensure_dir() { mkdir -p "$1"; }

safe_link() {
	local src="$1"
	local dst="$2"

	mkdir -p "$(dirname -- "${dst}")"

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

import_global_dir() {
	local global_dir="$1"
	local project_dir="$2"

	if [[ ! -d "${global_dir}" ]]; then
		return 0
	fi

	shopt -s nullglob
	for p in "${global_dir}"/*; do
		local name
		name="$(basename -- "${p}")"

		# Skip if project already has that name (local wins).
		if [[ -e "${project_dir}/${name}" || -L "${project_dir}/${name}" ]]; then
			continue
		fi

		ln -s -- "${p}" "${project_dir}/${name}"
	done
	shopt -u nullglob
}

TARGET=""
IMPORT_GLOBAL=true
DO_CURSOR=false
DO_CODEX=false
DO_CLAUDE=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--target)
		if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
			echo "ERROR: --target requires a directory path" >&2
			usage >&2
			exit 2
		fi
		TARGET="$2"
		shift 2
		;;
	--no-import-global)
		IMPORT_GLOBAL=false
		shift
		;;
	--cursor)
		DO_CURSOR=true
		shift
		;;
	--codex)
		DO_CODEX=true
		shift
		;;
	--claude)
		DO_CLAUDE=true
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

if [[ -z "${TARGET}" ]]; then
	echo "ERROR: --target is required" >&2
	usage >&2
	exit 2
fi

TARGET="$(cd -- "${TARGET}" && pwd)"

if [[ "${DO_CURSOR}" == "false" && "${DO_CODEX}" == "false" && "${DO_CLAUDE}" == "false" ]]; then
	DO_CURSOR=true
	DO_CODEX=true
	DO_CLAUDE=true
fi

PROJECT_AGENTS="${TARGET}/.agents"
ensure_dir "${PROJECT_AGENTS}/skills"
ensure_dir "${PROJECT_AGENTS}/commands"
ensure_dir "${PROJECT_AGENTS}/rules"

if [[ "${IMPORT_GLOBAL}" == "true" ]]; then
	import_global_dir "${HOME}/.agents/skills" "${PROJECT_AGENTS}/skills"
	import_global_dir "${HOME}/.agents/commands" "${PROJECT_AGENTS}/commands"
	import_global_dir "${HOME}/.agents/rules" "${PROJECT_AGENTS}/rules"
fi

link_tool() {
	local tool_dir="$1"
	ensure_dir "${TARGET}/${tool_dir}"
	safe_link "${PROJECT_AGENTS}/skills" "${TARGET}/${tool_dir}/skills"
	safe_link "${PROJECT_AGENTS}/commands" "${TARGET}/${tool_dir}/commands"
	safe_link "${PROJECT_AGENTS}/rules" "${TARGET}/${tool_dir}/rules"
}

if [[ "${DO_CURSOR}" == "true" ]]; then link_tool ".cursor"; fi
if [[ "${DO_CODEX}" == "true" ]]; then link_tool ".codex"; fi
if [[ "${DO_CLAUDE}" == "true" ]]; then link_tool ".claude"; fi

echo "Project linked to ${PROJECT_AGENTS}"
