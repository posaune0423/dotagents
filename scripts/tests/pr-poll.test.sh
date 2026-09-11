#!/usr/bin/env bash
# Integration tests for skills/create-pr/scripts/{poll-pr,triage-pr}.sh using a
# stub `gh` on PATH. The stub mirrors the real CLI's contract closely enough to
# catch the failures that matter: `--slurp` rejects `--jq`, checks come back as
# tab-separated rows, and API pages arrive as an array of arrays.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="${ROOT}/skills/create-pr/scripts"

pass=0
fail=0
fail_msg() {
	echo "FAIL: $*" >&2
	fail=$((fail + 1))
}
ok() { pass=$((pass + 1)); }

# assert_contains <haystack> <needle> <message>; assert_excludes is the inverse.
assert_contains() {
	if [[ "$1" == *"$2"* ]]; then ok; else fail_msg "$3: $1"; fi
}
assert_excludes() {
	if [[ "$1" != *"$2"* ]]; then ok; else fail_msg "$3: $1"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/bin"

# Scenario is driven by files so a case can swap the check table.
CHECKS_FILE="${TMP}/checks.tsv"
printf 'CodeRabbit\tpass\t0\t\tReview completed\nbun-check\tpass\t5s\thttps://example.test/run/1\t\n' >"${CHECKS_FILE}"

cat >"${TMP}/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
has() { local a; for a in "${args[@]}"; do [[ "$a" == "$1" ]] && return 0; done; return 1; }

case "${1:-}" in
auth) exit 0 ;;
pr)
	if [[ "${2:-}" == "checks" ]]; then
		cat "${STUB_CHECKS_FILE}"
		# Real gh exits non-zero when any check failed.
		if grep -q $'\tfail\t' "${STUB_CHECKS_FILE}"; then exit 1; fi
		exit 0
	fi
	echo "stub gh: unsupported pr subcommand: $*" >&2
	exit 1
	;;
api)
	if has --slurp && { has --jq || has -q; }; then
		echo 'the `--slurp` option is not supported with `--jq` or `--template`' >&2
		exit 1
	fi
	endpoint=""
	for a in "${args[@]}"; do [[ "$a" == repos/* ]] && endpoint="$a"; done
	case "${endpoint}" in
	*/pulls/*/reviews*)
		printf '[[{"id":901,"state":"COMMENTED","user":{"login":"reviewer-a"},"submitted_at":"2026-09-10T06:29:29Z","html_url":"https://example.test/r/901","body":"first"},{"id":902,"state":"APPROVED","user":{"login":"reviewer-b"},"submitted_at":"2026-09-10T07:00:00Z","html_url":"https://example.test/r/902","body":"LGTM\\nship it"}]]\n'
		;;
	*/issues/*/comments*)
		printf '[[{"id":701,"user":{"login":"bot"},"created_at":"2026-09-10T06:24:39Z","html_url":"https://example.test/c/701","body":"summary\\tcomment"}]]\n'
		;;
	*/pulls/*/comments*)
		printf '[[]]\n'
		;;
	*)
		echo "stub gh: unsupported endpoint: ${endpoint}" >&2
		exit 1
		;;
	esac
	;;
*)
	echo "stub gh: unsupported: $*" >&2
	exit 1
	;;
esac
STUB
chmod +x "${TMP}/bin/gh"

export STUB_CHECKS_FILE="${CHECKS_FILE}"
export PATH="${TMP}/bin:${PATH}"

command -v jq >/dev/null || {
	echo "FAIL: jq is required for these tests" >&2
	exit 1
}

# --- triage: latest review and latest comment must surface --------------------
out="$(bash "${SCRIPTS}/triage-pr.sh" --pr 24 --repo owner/repo 2>&1)" || out="<exit $?> ${out}"
assert_contains "${out}" "CI: total=2 pending=0 failed=0 success=2" "triage CI summary"
assert_contains "${out}" "REVIEW: APPROVED reviewer-b 2026-09-10T07:00:00Z https://example.test/r/902" "triage should print the newest review"
assert_contains "${out}" "COMMENT: conversation bot 2026-09-10T06:24:39Z https://example.test/c/701 summary comment" "triage should print the newest conversation comment"
assert_excludes "${out}" "COMMENT: inline" "triage must not invent inline comments"

# --- poll: one iteration reports checks, new review, new comment ----------------
out="$(POLL_ONCE=1 bash "${SCRIPTS}/poll-pr.sh" --pr 24 --repo owner/repo --exit-when-green 2>&1)" || out="<exit $?> ${out}"
assert_contains "${out}" "Checks: total=2 pending=0 failed=0 success=2" "poll checks summary"
assert_contains "${out}" "Checks green; exiting early." "poll should exit early when green"
assert_contains "${out}" "New review (APPROVED) by @reviewer-b at 2026-09-10T07:00:00Z" "poll should report the newest review"
assert_contains "${out}" "LGTM ship it" "poll should flatten newlines in the review body"
assert_contains "${out}" "New conversation comment by @bot" "poll should report the newest conversation comment"

# --- poll: a failed check is counted and listed ------------------------------
printf 'bun-check\tfail\t5s\thttps://example.test/run/2\t\nbun-lint\tpending\t\t\t\n' >"${CHECKS_FILE}"
out="$(POLL_ONCE=1 bash "${SCRIPTS}/poll-pr.sh" --pr 24 --repo owner/repo --exit-when-green 2>&1)" || out="<exit $?> ${out}"
assert_contains "${out}" "Checks: total=2 pending=1 failed=1 success=0" "poll should count fail and pending"
assert_contains "${out}" "- bun-check (fail) https://example.test/run/2" "poll should list the failed check with its url"
assert_excludes "${out}" "Checks green" "poll must not report green with failures"

echo "pr-poll tests: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
