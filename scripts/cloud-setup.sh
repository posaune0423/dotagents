#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
cloud-setup.sh [--refresh]

Make a Claude Code on the web session see the same global skills, commands, rules,
instructions, and subagents as a local machine. Cloud VMs never receive the local
~/.claude, so run this from the cloud environment's setup script, which runs as root
before Claude Code starts:

  git clone --depth 1 https://github.com/posaune0423/dotagents.git ~/dotagents && ~/dotagents/scripts/cloud-setup.sh

Without options:
  - runs link-dotagents.sh --home --all --tool-links
  - links ~/.claude/{skills,commands,rules} -> ~/.agents/{skills,commands,rules}
  - registers a SessionStart hook in ~/.claude/settings.json that runs --refresh

  --refresh   git pull this checkout. The environment snapshots the setup result and
              skips the setup script in later sessions, so without this the skills stay
              at the commit that was cloned first.
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

case "${1:-}" in
"") ;;
--refresh)
	# A failed pull must not block the session; the snapshot's copy is still usable.
	git -C "${REPO_ROOT}" pull --ff-only --quiet || echo "WARN: could not update ${REPO_ROOT}" >&2
	exit 0
	;;
-h | --help)
	usage
	exit 0
	;;
*)
	usage >&2
	exit 2
	;;
esac

bash "${SCRIPT_DIR}/link-dotagents.sh" --home --all --tool-links

# Claude Code reads user assets only from ~/.claude; ~/.agents is the shared layout
# that Codex and Cursor read too.
for kind in skills commands rules; do
	dst="${HOME}/.claude/${kind}"
	if [[ -e "${dst}" && ! -L "${dst}" ]]; then
		mv -- "${dst}" "${dst}.bak.$(date +"%Y%m%d-%H%M%S")"
	fi
	ln -sfn -- "${HOME}/.agents/${kind}" "${dst}"
	echo "Linked: ${dst} -> ${HOME}/.agents/${kind}"
done

settings="${HOME}/.claude/settings.json"
hook_command="bash \"${REPO_ROOT}/scripts/cloud-setup.sh\" --refresh"
[[ -s "${settings}" ]] || printf '%s\n' '{}' >"${settings}"
tmp="$(mktemp)"
jq --arg cmd "${hook_command}" '
	def refresh: (.command // "") | test("cloud-setup\\.sh\"? --refresh$");
	.hooks.SessionStart = (
		[(.hooks.SessionStart // [])[] | select(any(.hooks[]?; refresh) | not)]
		+ [{hooks: [{type: "command", command: $cmd, timeout: 60}]}]
	)
' "${settings}" >"${tmp}"
mv -- "${tmp}" "${settings}"
echo "Registered SessionStart hook in ${settings}: ${hook_command}"
