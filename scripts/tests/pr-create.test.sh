#!/usr/bin/env bash
# Exercise the actual PR helpers with isolated repos and a stub GitHub boundary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pass=0
fail=0
fail_msg() {
	echo "FAIL: $*" >&2
	fail=$((fail + 1))
}
ok() { pass=$((pass + 1)); }
assert_contains() {
	if grep -qxF -- "$2" <<<"$1"; then ok; else fail_msg "$3 (missing '$2')"; fi
}
assert_not_contains() {
	if grep -qxF -- "$2" <<<"$1"; then fail_msg "$3 (unexpected '$2')"; else ok; fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/bin" "${TMP}/repo"
cp -R "${ROOT}/skills/create-pr" "${TMP}/skill"
SCRIPT="${TMP}/skill/scripts/gh-pr-create-with-meta.sh"
git -C "${TMP}/repo" init -q
cd "${TMP}/repo"
export GH_ARGS_FILE="${TMP}/gh-args"
export GH_BODY_FILE="${TMP}/posted-body"
export GH_CALLS_FILE="${TMP}/gh-calls"
export CREATE_PR_NO_LABEL=1
cat >"${TMP}/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"${GH_CALLS_FILE}"
case "$1 $2" in
'pr create')
	printf '%s\n' "$@" >"${GH_ARGS_FILE}"
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--body-file) cp "$2" "${GH_BODY_FILE}"; shift ;;
		--body-file=*) cp "${1#*=}" "${GH_BODY_FILE}" ;;
		esac
		shift
	done
	printf 'https://github.com/example/repo/pull/1\n'
	;;
'api user') printf 'self-user\n' ;;
'api graphql')
	for arg in "$@"; do
		case "$arg" in body=*) printf '%s\n' "${arg#body=}" >"${GH_BODY_FILE}" ;; esac
	done
	;;
'pr edit') printf '%s\n' "$@" >"${GH_ARGS_FILE}" ;;
'pr view')
	case " $* " in
	*' --json id '*) printf 'PR_example\n' ;;
	*' --json url '*) printf 'https://github.com/example/repo/pull/1\n' ;;
	*' --json body '*)
		if [[ "${GH_WRONG_BODY:-0}" == 1 ]]; then printf 'unexpected body\n'; else cat "${GH_BODY_FILE}"; fi ;;
	*' --json assignees '*)
		printf 'other-user\n'
		if [[ "${GH_MISSING_SELF:-0}" != 1 ]]; then printf 'self-user\n'; fi ;;
	*) echo "Unexpected view: $*" >&2; exit 2 ;;
	esac
	;;
*) echo "Unexpected gh call: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "${TMP}/bin/gh"
export PATH="${TMP}/bin:${PATH}"
cat >"${TMP}/body.md" <<'BODY'
## Why

A caller needs a fix.

## What changed

The failure is handled.

## Review guide

Start with the handler.

## Verification

Integration test passed.

## Risk / rollout

None.
BODY

run_create() {
	rm -f "${GH_ARGS_FILE}" "${GH_CALLS_FILE}"
	bash "${SCRIPT}" --base main --title t --body-file "${TMP}/body.md" >"${TMP}/out" 2>"${TMP}/err"
}
expect_rejected() {
	local expected="$1"
	shift
	rm -f "${GH_ARGS_FILE}" "${GH_CALLS_FILE}"
	if bash "${SCRIPT}" --title t "$@" >"${TMP}/out" 2>"${TMP}/err"; then
		fail_msg "expected rejection: ${expected}"
	elif [[ -e "${GH_ARGS_FILE}" ]]; then
		fail_msg "must reject before creating PR: ${expected}"
	elif ! grep -qF -- "${expected}" "${TMP}/err"; then
		fail_msg "missing diagnostic: ${expected} ($(cat "${TMP}/err"))"
	else
		ok
	fi
}

if run_create; then ok; else fail_msg "valid default body must succeed: $(cat "${TMP}/err")"; fi
args="$(cat "${GH_ARGS_FILE}")"
assert_contains "${args}" "--draft" "draft by default"
assert_contains "${args}" "--assignee" "assignee flag"
assert_contains "${args}" "@me" "self assigned"
if CREATE_PR_DRAFT=0 run_create; then ok; else fail_msg "draft opt-out failed"; fi
assert_not_contains "$(cat "${GH_ARGS_FILE}")" "--draft" "draft opt-out"

# Empty or custom defaults may add assignees but must never remove self.
for configured in '' other-user; do
	printf 'CREATE_PR_ASSIGNEES=%s\n' "${configured}" >"${TMP}/skill/pr-defaults.env"
	if run_create; then ok; else fail_msg "configured assignee failed"; fi
	assert_contains "$(cat "${GH_ARGS_FILE}")" "@me" "self retained with '${configured}' defaults"
	if [[ -n "${configured}" ]]; then assert_contains "$(cat "${GH_ARGS_FILE}")" "${configured}" "additional assignee retained"; fi
	if bash "${TMP}/skill/scripts/pr-meta-sync.sh" --pr 1 >"${TMP}/out" 2>"${TMP}/err"; then ok; else fail_msg "metadata sync failed"; fi
	assert_contains "$(cat "${GH_ARGS_FILE}")" "@me" "metadata sync includes self"
done

printf 'Freeform body\n' >"${TMP}/bad.md"
expect_rejected '## Why' --body-file "${TMP}/bad.md"
expect_rejected '--body-file' --body 'Freeform body'
expect_rejected '--fill' --body-file "${TMP}/body.md" --fill
expect_rejected 'empty' --body-file /dev/null
# Headings inside code fences must not satisfy required sections.
{
	printf '\140\140\140markdown\n'
	cat "${TMP}/body.md"
	printf '\140\140\140\n'
} >"${TMP}/fenced.md"
expect_rejected '## Why' --body-file "${TMP}/fenced.md"
{
	printf '\140\140\140\140markdown\n\140\140\140\n'
	cat "${TMP}/body.md"
	printf '\140\140\140\140\n'
} >"${TMP}/long-fenced.md"
expect_rejected '## Why' --body-file "${TMP}/long-fenced.md"
sed '/## Verification/,$d' "${TMP}/body.md" >"${TMP}/incomplete.md"
expect_rejected '## Verification' --body-file "${TMP}/incomplete.md"
# The helper is invoked by path, so the Bash hook's `gh pr create` match never sees it.
{
	cat "${TMP}/body.md"
	printf '\n\360\237\244\226 Generated with [Claude Code](https://claude.com/claude-code)\n'
} >"${TMP}/attributed.md"
expect_rejected 'Generated with Claude Code' --body-file "${TMP}/attributed.md"

# Repository templates take precedence and are validated instead of default sections.
mkdir .github
printf '## Summary\n\n<!-- details -->\n' >.github/pull_request_template.md
printf '## Summary\n\nLocal fix.\n' >"${TMP}/body.md"
if run_create; then ok; else fail_msg "repository template should override default"; fi
expect_rejected '## Summary' --body-file "${TMP}/bad.md"
{
	cat "${TMP}/body.md"
	printf '\n## Unrelated section\n\nExtra.\n'
} >"${TMP}/extra.md"
expect_rejected 'Unexpected PR heading' --body-file "${TMP}/extra.md"
rm .github/pull_request_template.md
mkdir .github/PULL_REQUEST_TEMPLATE
printf '## Summary\n' >.github/PULL_REQUEST_TEMPLATE/feature.md
printf '## Bug\n' >.github/PULL_REQUEST_TEMPLATE/bug.md
expect_rejected 'Several PR templates' --body-file "${TMP}/body.md"
if bash "${SCRIPT}" --title t --body-file "${TMP}/body.md" --template-name feature.md >"${TMP}/out" 2>"${TMP}/err"; then ok; else fail_msg "explicit template selection failed"; fi
assert_not_contains "$(cat "${GH_ARGS_FILE}")" "--template-name" "helper-only selector is not forwarded to gh"
rm -r .github/PULL_REQUEST_TEMPLATE
printf '## Summary\n' >.github/pull_request_template.md

# A successful create response alone is not proof: check the saved body and self.
if GH_MISSING_SELF=1 run_create; then fail_msg "missing persisted self must fail"; else ok; fi
if GH_WRONG_BODY=1 run_create; then fail_msg "mismatched persisted body must fail"; else ok; fi
if GH_MISSING_SELF=1 bash "${TMP}/skill/scripts/pr-meta-sync.sh" --pr 1 >"${TMP}/out" 2>"${TMP}/err"; then fail_msg "sync must verify self"; else ok; fi

# Updating an existing PR must not bypass the template requirement either.
if bash "${TMP}/skill/scripts/pr-body-update.sh" --pr 1 --repo example/repo --file "${TMP}/bad.md" >"${TMP}/out" 2>"${TMP}/err"; then
	fail_msg "update must reject a body missing template headings"
elif ! grep -qF '## Summary' "${TMP}/err"; then
	fail_msg "update must report the missing template heading"
else
	ok
fi
if bash "${TMP}/skill/scripts/pr-body-update.sh" --pr 1 --repo example/repo --file "${TMP}/body.md" >"${TMP}/out" 2>"${TMP}/err"; then ok; else fail_msg "valid update failed"; fi

echo "pr-create tests: ${pass} passed, ${fail} failed"
[[ ${fail} -eq 0 ]]
