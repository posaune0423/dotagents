#!/usr/bin/env bash
# Integration tests for skills/create-pr/scripts/gh-pr-create-with-meta.sh:
# new PRs open as drafts unless CREATE_PR_DRAFT=0 (stub gh records its argv).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/skills/create-pr/scripts/gh-pr-create-with-meta.sh"

pass=0
fail=0
fail_msg() {
	echo "FAIL: $*" >&2
	fail=$((fail + 1))
}
ok() { pass=$((pass + 1)); }
assert_contains() {
	if grep -qxF -- "$2" <<<"$1"; then ok; else fail_msg "$3 (missing '$2' in: $(tr '\n' ' ' <<<"$1"))"; fi
}
assert_not_contains() {
	if grep -qxF -- "$2" <<<"$1"; then fail_msg "$3 (unexpected '$2' in: $(tr '\n' ' ' <<<"$1"))"; else ok; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${GH_ARGS_FILE}"
EOF
chmod +x "${TMP}/bin/gh"
export PATH="${TMP}/bin:${PATH}"
export GH_ARGS_FILE="${TMP}/gh-args"
export CREATE_PR_NO_LABEL=1

run_create() {
	rm -f "${GH_ARGS_FILE}"
	bash "${SCRIPT}" --base main --title t --body-file /dev/null
	cat "${GH_ARGS_FILE}"
}

# --- default: new PRs start as drafts ------------------------------------------
args="$(run_create)"
assert_contains "${args}" "create" "gh pr create is invoked"
assert_contains "${args}" "--draft" "new PR is a draft by default"
assert_contains "${args}" "--title" "caller arguments are passed through"

# --- opt-out: CREATE_PR_DRAFT=0 opens a ready-for-review PR -----------------------
args="$(CREATE_PR_DRAFT=0 run_create)"
assert_not_contains "${args}" "--draft" "CREATE_PR_DRAFT=0 skips --draft"

echo "pr-create tests: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
