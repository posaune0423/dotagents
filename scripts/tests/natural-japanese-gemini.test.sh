#!/usr/bin/env bash
# Exercise the Orca worker launcher with a stubbed orca: no Orca runtime, no model call.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/skills/natural-japanese-gemini/scripts/start-worker.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${TMP}"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); }
fail_msg() {
	fail=$((fail + 1))
	echo "FAIL: $*" >&2
}
# expect <message> <command...>: the command must succeed.
expect() {
	local msg="$1"
	shift
	if "$@" >/dev/null; then ok; else fail_msg "$msg"; fi
}
assert_contains() {
	if grep -qF -- "$2" "$1"; then ok; else fail_msg "$3: '$2' not in $1"; fi
}

# Stub orca: record the arguments, keep a copy of the spec file, answer like a receipt.
mkdir -p "${TMP}/bin" "${TMP}/docs dir"
cat >"${TMP}/bin/orca" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${STUB_DIR}/orca-args"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--spec-file) cp "$2" "${STUB_DIR}/spec" && shift 2 ;;
	*) shift ;;
	esac
done
[[ -z "${ORCA_FAIL:-}" ]] || {
	echo "worker-start failed: agent_readiness" >&2
	exit 3
}
echo '{"ok":true,"result":{"dispatchId":"ctx_test"}}'
STUB
chmod +x "${TMP}/bin/orca"
printf '# 元の文書\n\n元の本文です。\n' >"${TMP}/docs dir/draft.md"

run() {
	rm -f "${TMP}/orca-args" "${TMP}/spec"
	(cd "${TMP}/docs dir" && PATH="${TMP}/bin:${PATH}" STUB_DIR="${TMP}" \
		"${BASH_BIN:-bash}" "${SCRIPT}" "$@" >"${TMP}/out" 2>"${TMP}/err")
}
has_arg_pair() { grep -qxF -- "$1" "${TMP}/orca-args" && grep -A1 -xF -- "$1" "${TMP}/orca-args" | grep -qxF -- "$2"; }

# Happy path: one Antigravity worker on Gemini 4 Hydrogen, in the caller's workspace, on this machine.
if run --out revised.md draft.md; then ok; else fail_msg "valid start must succeed: $(cat "${TMP}/err")"; fi
assert_contains "${TMP}/out" '"dispatchId":"ctx_test"' "orca receipt is passed through"
expect "worker-start subcommand" grep -qxF worker-start "${TMP}/orca-args"
expect "agent" has_arg_pair --agent antigravity
expect "default model" has_arg_pair --model gemini-4-hydrogen-high
expect "local Orca" has_arg_pair --environment local
expect "caller workspace" has_arg_pair --worktree current
# The worker starts in the workspace root, so every path in the spec is absolute.
assert_contains "${TMP}/spec" "${TMP}/docs dir/draft.md" "absolute source path"
assert_contains "${TMP}/spec" "${TMP}/docs dir/revised.md" "absolute output path"
assert_contains "${TMP}/spec" "${ROOT}/skills/natural-japanese/SKILL.md" "skill path"
assert_contains "${TMP}/spec" "newfacts.py" "report asks for the added-facts check"
expect "source untouched" grep -qF "元の本文です" "${TMP}/docs dir/draft.md"

# Options: model override and a note from the requester.
if NATURAL_JAPANESE_GEMINI_MODEL=gemini-4-neon-high run --note "社内向けの議事録" --out revised.md draft.md; then ok; else fail_msg "options run failed: $(cat "${TMP}/err")"; fi
expect "model override" has_arg_pair --model gemini-4-neon-high
assert_contains "${TMP}/spec" "社内向けの議事録" "note in spec"

# Refusals happen before any worker is started.
if run --out revised.md missing.md; then fail_msg "missing file must fail"; else ok; fi
if run draft.md; then fail_msg "--out is required"; else ok; fi
if run --out draft.md draft.md; then fail_msg "--out must not be the source"; else ok; fi
if run --out "${TMP}/no-such-dir/revised.md" draft.md; then fail_msg "output directory must exist"; else ok; fi
expect "no worker after a refusal" test ! -e "${TMP}/orca-args"

# A failed start is reported as is; the script never retries it.
if ORCA_FAIL=1 run --out revised.md draft.md; then fail_msg "failed start must fail"; else ok; fi
assert_contains "${TMP}/err" "agent_readiness" "orca error surfaced"

# macOS still ships bash 3.2 as /bin/bash; agents with a minimal PATH run it.
if [[ -x /bin/bash ]] && ! /bin/bash -c '[[ ${BASH_VERSINFO[0]} -ge 5 ]]'; then
	if BASH_BIN=/bin/bash run --out revised.md draft.md; then ok; else fail_msg "must run under /bin/bash: $(cat "${TMP}/err")"; fi
fi

echo "natural-japanese-gemini tests: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
