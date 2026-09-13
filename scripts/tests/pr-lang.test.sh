#!/usr/bin/env bash
# Integration tests for skills/create-pr/scripts/pr-lang.sh: per-repository PR
# language lookup backed by a machine-local, gitignored file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/skills/create-pr/scripts/pr-lang.sh"

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

# Every case points the script at its own config file, never at the real one.
export PR_LANG_FILE="${TMP}/pr-lang.local"

new_repo() {
	local dir
	dir="$(mktemp -d "${TMP}/repo.XXXXXX")"
	git -C "${dir}" init -q
	git -C "${dir}" remote add origin "$1"
	printf '%s\n' "${dir}"
}

[[ -x "${SCRIPT}" ]] || {
	echo "FAIL: script is missing or not executable: ${SCRIPT}" >&2
	exit 1
}

ssh_repo="$(new_repo git@github.com:posaune0423/dotagents.git)"
https_repo="$(new_repo https://github.com/getozinc/myfans-web.git)"
other_repo="$(new_repo https://github.com/someone/else)"
no_remote="$(mktemp -d "${TMP}/bare.XXXXXX")"
git -C "${no_remote}" init -q

# --- default: no file, no entry -> en ------------------------------------------
assert_eq "$(cd "${ssh_repo}" && bash "${SCRIPT}")" "en" "missing config file defaults to en"
assert_eq "$(cd "${no_remote}" && bash "${SCRIPT}")" "en" "repo without a remote defaults to en"

# --- owner-level entry applies to every repo of that owner ----------------------
printf 'posaune0423 ja\n' >"${PR_LANG_FILE}"
assert_eq "$(cd "${ssh_repo}" && bash "${SCRIPT}")" "ja" "owner entry matches ssh remote"
assert_eq "$(cd "${other_repo}" && bash "${SCRIPT}")" "en" "other owner stays en"

# --- repo-level entry wins over owner-level, whichever order they appear --------
printf 'posaune0423/dotagents en\nposaune0423 ja\n' >"${PR_LANG_FILE}"
assert_eq "$(cd "${ssh_repo}" && bash "${SCRIPT}")" "en" "repo entry overrides owner entry"

# --- owner (org) match is case-insensitive -------------------------------------
org_repo="$(new_repo git@github.com:SushiTopMarketing/sushitopio_frontend.git)"
printf 'sushitopmarketing ja\n' >"${PR_LANG_FILE}"
assert_eq "$(cd "${org_repo}" && bash "${SCRIPT}")" "ja" "org entry matches regardless of case"

# --- https remote, comments and blank lines tolerated ---------------------------
printf '# comment\n\ngetozinc/myfans-web ja\n' >"${PR_LANG_FILE}"
assert_eq "$(cd "${https_repo}" && bash "${SCRIPT}")" "ja" "https remote parsed"

# --- --set writes or replaces the entry for the current repo -------------------
rm -f "${PR_LANG_FILE}"
(cd "${ssh_repo}" && bash "${SCRIPT}" --set ja)
assert_eq "$(cd "${ssh_repo}" && bash "${SCRIPT}")" "ja" "--set persists for the current repo"
assert_eq "$(cat "${PR_LANG_FILE}")" "posaune0423/dotagents ja" "--set writes a repo-level line"
(cd "${ssh_repo}" && bash "${SCRIPT}" --set ko)
assert_eq "$(grep -c 'posaune0423/dotagents' "${PR_LANG_FILE}")" "1" "--set replaces instead of appending"
assert_eq "$(cd "${ssh_repo}" && bash "${SCRIPT}")" "ko" "--set replacement is read back"

# --- --set with an explicit owner or owner/repo key ---------------------------
(cd "${other_repo}" && bash "${SCRIPT}" --set ja --for posaune0423)
assert_eq "$(cd "${https_repo}" && bash "${SCRIPT}" --repo posaune0423/anything)" "ja" "--for owner applies to that owner; --repo overrides detection"
assert_eq "$(cd "${other_repo}" && bash "${SCRIPT}")" "en" "--for does not touch the current repo"

# --- invalid input ------------------------------------------------------------
set +e
(cd "${ssh_repo}" && bash "${SCRIPT}" --set "ja; rm -rf" 2>/dev/null)
code=$?
set -e
assert_eq "${code}" "1" "language must be a short tag"

echo "pr-lang tests: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
