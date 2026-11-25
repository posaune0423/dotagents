#!/usr/bin/env bash
# Integration tests for scripts/agent-account.sh: picks the Claude Code and
# Codex config directories for a directory from its repository owner, backed by
# a machine-local mapping file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/agent-account.sh"

pass=0
fail=0
fail_msg() {
	echo "FAIL: $*" >&2
	fail=$((fail + 1))
}
ok() { pass=$((pass + 1)); }
assert_eq() {
	if [[ "$1" == "$2" ]]; then ok; else fail_msg "$3 (expected '$2', got '$1')"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Every case points the script at its own mapping and ghq root, never the real ones.
export AGENT_ACCOUNTS_FILE="${TMP}/config"
export GHQ_ROOT="${TMP}/ghq"

new_repo() {
	local dir
	dir="$(mktemp -d "${TMP}/repo.XXXXXX")"
	git -C "${dir}" init -q
	git -C "${dir}" remote add origin "$1"
	printf '%s\n' "${dir}"
}

resolve() { bash "${SCRIPT}" --dir "$1"; }

[[ -x "${SCRIPT}" ]] || {
	echo "FAIL: script is missing or not executable: ${SCRIPT}" >&2
	exit 1
}

work_ssh="$(new_repo git@github.com:acme/widget.git)"
work_https="$(new_repo https://github.com/Acme/widget-web)"
mine="$(new_repo git@github.com:posaune0423/dotagents.git)"
no_remote="$(mktemp -d "${TMP}/bare.XXXXXX")"
git -C "${no_remote}" init -q
ghq_clone="${GHQ_ROOT}/github.com/acme/not-yet-pushed"
mkdir -p "${ghq_clone}"
plain_dir="$(mktemp -d "${TMP}/plain.XXXXXX")"

# --- no mapping file: print nothing, succeed -------------------------------------
assert_eq "$(resolve "${work_ssh}")" "" "missing mapping file prints nothing"

cat >"${AGENT_ACCOUNTS_FILE}" <<'EOF'
# owner -> account; * is every other directory
route acme client
route * personal

# account tool directory (the directory is the rest of the line)
dir client claude /profiles/claude client/home
dir client codex /profiles/codex-client/home
dir personal claude /profiles/claude-personal/home
dir personal codex /profiles/codex-personal/home
EOF

client_out=$'account=client\nclaude=/profiles/claude client/home\ncodex=/profiles/codex-client/home'
personal_out=$'account=personal\nclaude=/profiles/claude-personal/home\ncodex=/profiles/codex-personal/home'

# --- owner from the origin remote, ssh and https, case-insensitive ---------------
assert_eq "$(resolve "${work_ssh}")" "${client_out}" "ssh remote of the mapped owner"
assert_eq "$(resolve "${work_https}")" "${client_out}" "https remote, owner case differs"

# --- a subdirectory and a linked worktree outside the owner folder ---------------
mkdir -p "${work_ssh}/apps/api"
assert_eq "$(resolve "${work_ssh}/apps/api")" "${client_out}" "subdirectory of a mapped repo"
# CI runners have no git identity; give this throwaway commit one.
git -C "${work_ssh}" -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m init
git -C "${work_ssh}" worktree add -q "${TMP}/elsewhere/be-2" -b be-2
assert_eq "$(resolve "${TMP}/elsewhere/be-2")" "${client_out}" "worktree outside the owner folder"

# --- everything else falls to the * route ------------------------------------------
assert_eq "$(resolve "${mine}")" "${personal_out}" "other owner uses the default route"
assert_eq "$(resolve "${no_remote}")" "${personal_out}" "repo without a remote uses the default"
assert_eq "$(resolve "${plain_dir}")" "${personal_out}" "non-repository directory uses the default"

# --- no remote but under <ghq root>/<host>/<owner>/ -----------------------------------
assert_eq "$(resolve "${ghq_clone}")" "${client_out}" "ghq path is the fallback owner"

# --- without a * route, unmapped directories print nothing ---------------------------
sed -i.bak '/^route \*/d' "${AGENT_ACCOUNTS_FILE}"
assert_eq "$(resolve "${mine}")" "" "no default route prints nothing"
assert_eq "$(resolve "${work_ssh}")" "${client_out}" "explicit route still resolves"

# --- an account missing one tool prints only the tool it has --------------------------
printf 'route acme partial\ndir partial codex /only/codex\n' >"${AGENT_ACCOUNTS_FILE}"
assert_eq "$(resolve "${work_ssh}")" $'account=partial\ncodex=/only/codex' "partial account"

# --- an account named after a tool still splits its fields correctly ----------------
printf 'route * claude-team\ndir claude-team claude  /x/claude home \n' >"${AGENT_ACCOUNTS_FILE}"
assert_eq "$(resolve "${mine}")" $'account=claude-team\nclaude=/x/claude home' "account named like a tool"

# --- a directory containing a single quote is refused (it is spliced into commands) --
printf "route * bad\ndir bad claude /it's/here\n" >"${AGENT_ACCOUNTS_FILE}"
if out="$(resolve "${mine}" 2>&1)"; then
	fail_msg "single-quoted directory should fail (got '${out}')"
else
	ok
fi

# --- default --dir is the current directory ---------------------------------------
cat >"${AGENT_ACCOUNTS_FILE}" <<'EOF'
route acme client
dir client codex /profiles/codex-client/home
EOF
assert_eq "$(cd "${work_ssh}" && bash "${SCRIPT}")" $'account=client\ncodex=/profiles/codex-client/home' "defaults to PWD"

echo "agent-account: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
