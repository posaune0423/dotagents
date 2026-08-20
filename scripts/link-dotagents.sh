#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
link-dotagents.sh --home [--all] [--tool-configs] [--verify]

Create symlinks from this repo (SSoT) into:
  - ~/.agents (global agent config)
  - optionally ~/.claude/CLAUDE.md, ~/.claude/settings.json, ~/.claude/agents,
    and ~/.gemini/GEMINI.md

Options:
  --home           Link repo skills into ~/.agents/skills
  --all            Also link commands and rules into ~/.agents (use with --home)
  --tool-configs   Symlink CLAUDE.md, settings.json, agents/ (Claude), and GEMINI.md
                   to this repo's copies
  --verify         Check that every link above exists and resolves into the MAIN
                   dotagents checkout. Verification itself writes nothing; combining
                   it with the flags above links first, then verifies. Exits non-zero
                   on drift.
  -h, --help       Show this help

At least one of --home, --tool-configs, or --verify is required.

Note: subagent definitions are NOT shared via ~/.agents. Claude Code reads Markdown
(.claude/agents/*.md) and Codex reads TOML (.codex/agents/*.toml), so each tool gets
its own symlink.

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
DO_VERIFY=false

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
	--verify)
		DO_VERIFY=true
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

link_tool_configs() {
	local claude_md_src="${REPO_ROOT}/.claude/CLAUDE.md"
	local claude_settings_src="${REPO_ROOT}/.claude/settings.json"
	local claude_agents_src="${REPO_ROOT}/.claude/agents"
	local gemini_md_src="${REPO_ROOT}/.gemini/GEMINI.md"
	if [[ ! -f "${claude_md_src}" ]]; then
		echo "ERROR: expected file missing: ${claude_md_src}" >&2
		exit 1
	fi
	if [[ ! -f "${claude_settings_src}" ]]; then
		echo "ERROR: expected file missing: ${claude_settings_src}" >&2
		exit 1
	fi
	if [[ ! -d "${claude_agents_src}" ]]; then
		echo "ERROR: expected directory missing: ${claude_agents_src}" >&2
		exit 1
	fi
	if [[ ! -f "${gemini_md_src}" ]]; then
		echo "ERROR: expected file missing: ${gemini_md_src}" >&2
		exit 1
	fi
	mkdir -p -- "${HOME}/.claude" "${HOME}/.gemini"
	safe_link "${claude_md_src}" "${HOME}/.claude/CLAUDE.md"
	safe_link "${claude_settings_src}" "${HOME}/.claude/settings.json"
	safe_link "${claude_agents_src}" "${HOME}/.claude/agents"
	safe_link "${gemini_md_src}" "${HOME}/.gemini/GEMINI.md"
}

if [[ "${DO_TOOL_CONFIGS}" == "true" ]]; then
	link_tool_configs
	did_something=true
fi

# Resolve a symlink one level, without readlink -f (unreliable on BSD/macOS).
resolve_link() {
	local dst="$1"
	local target
	target="$(readlink -- "${dst}")"
	if [[ "${target}" != /* ]]; then
		target="$(dirname -- "${dst}")/${target}"
	fi
	if [[ -d "${target}" ]]; then
		(cd -- "${target}" && pwd)
	else
		printf '%s/%s\n' "$(cd -- "$(dirname -- "${target}")" && pwd)" "$(basename -- "${target}")"
	fi
}

# Root of the MAIN working tree, even when this script runs from a git worktree.
# Links must point there: a link into a worktree breaks when that worktree is removed.
EXPECTED_ROOT=""

expected_root() {
	local common
	if common="$(git -C "${REPO_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
		dirname -- "${common}"
	else
		printf '%s\n' "${REPO_ROOT}"
	fi
}

check_link() {
	local dst="$1"
	local want="$2"
	local resolved
	local expect="${EXPECTED_ROOT}${want}"

	if [[ ! -L "${dst}" ]]; then
		if [[ -e "${dst}" ]]; then
			echo "DRIFT (not a symlink): ${dst}" >&2
		else
			echo "MISSING: ${dst}" >&2
		fi
		return 1
	fi

	resolved="$(resolve_link "${dst}")"
	if [[ ! -e "${resolved}" ]]; then
		echo "BROKEN: ${dst} -> ${resolved}" >&2
		return 1
	fi
	if [[ "${resolved}" != "${expect}" ]]; then
		echo "UNEXPECTED TARGET: ${dst} -> ${resolved} (expected ${expect})" >&2
		return 1
	fi

	echo "OK: ${dst} -> ${resolved}"
}

# Claude Code silently ignores an agent file whose frontmatter is missing, unclosed,
# or whose name does not match the filename, so check the shape here rather than
# discovering it at delegation time.
validate_agent_file() {
	local f="$1"
	local fm got want

	if [[ "$(head -n 1 -- "${f}")" != "---" ]]; then
		echo "INVALID (no YAML frontmatter): ${f}" >&2
		return 1
	fi
	if ! fm="$(awk 'NR > 1 { if ($0 == "---") { closed = 1; exit } print } END { if (!closed) exit 3 }' "${f}")"; then
		echo "INVALID (frontmatter not closed): ${f}" >&2
		return 1
	fi
	if ! grep -qE '^description:' <<<"${fm}"; then
		echo "INVALID (missing description): ${f}" >&2
		return 1
	fi

	want="$(basename -- "${f}" .md)"
	got="$(awk '/^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }' <<<"${fm}")"
	if [[ "${got}" != "${want}" ]]; then
		echo "INVALID (name '${got}' does not match filename '${want}'): ${f}" >&2
		return 1
	fi

	# The checks above only test the shape. When a YAML parser is on PATH, also confirm
	# the block actually parses: an unquoted description containing ": " is a YAML error,
	# and Claude Code then ignores the agent with no visible message. Ruby ships with
	# macOS; where it is absent the shape checks stand on their own.
	if command -v ruby >/dev/null 2>&1; then
		if ! AGENT_NAME="${want}" ruby -ryaml -e '
			d = YAML.safe_load(STDIN.read)
			abort unless d.is_a?(Hash)
			abort if d["description"].to_s.strip.empty?
			abort unless d["name"].to_s == ENV["AGENT_NAME"]
		' <<<"${fm}" 2>/dev/null; then
			echo "INVALID (frontmatter is not parseable YAML): ${f}" >&2
			return 1
		fi
	fi
}

# Assumes the flag set used by `just link-global` (--home --all --tool-configs).
verify_links() {
	local rc=0
	local f
	local count=0
	local valid=0

	EXPECTED_ROOT="$(expected_root)"
	echo "Expecting links into: ${EXPECTED_ROOT}"

	check_link "${HOME}/.agents/skills" "/skills" || rc=1
	check_link "${HOME}/.agents/commands" "/commands" || rc=1
	check_link "${HOME}/.agents/rules" "/rules" || rc=1
	check_link "${HOME}/.claude/CLAUDE.md" "/.claude/CLAUDE.md" || rc=1
	check_link "${HOME}/.claude/settings.json" "/.claude/settings.json" || rc=1
	check_link "${HOME}/.claude/agents" "/.claude/agents" || rc=1
	check_link "${HOME}/.gemini/GEMINI.md" "/.gemini/GEMINI.md" || rc=1

	shopt -s nullglob
	for f in "${HOME}/.claude/agents"/*.md; do
		count=$((count + 1))
		if validate_agent_file "${f}"; then
			valid=$((valid + 1))
		else
			rc=1
		fi
	done
	shopt -u nullglob

	if [[ "${count}" -eq 0 ]]; then
		echo "WARN: no agent definitions under ${HOME}/.claude/agents" >&2
	elif [[ "${valid}" -eq "${count}" ]]; then
		echo "OK: ${count} agent definition(s) loadable by Claude Code"
	else
		echo "INVALID: only ${valid} of ${count} agent definition(s) are loadable" >&2
	fi

	return "${rc}"
}

if [[ "${DO_VERIFY}" == "true" ]]; then
	did_something=true
	verify_links
fi

if [[ "${did_something}" == "false" ]]; then
	usage >&2
	exit 2
fi
