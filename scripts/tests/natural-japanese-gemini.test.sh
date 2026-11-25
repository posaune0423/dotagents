#!/usr/bin/env bash
# Exercise the Gemini rewrite wrapper with stubbed curl and uv: no network, no API key.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/skills/natural-japanese-gemini/scripts/rewrite.sh"
TMP="$(mktemp -d)"
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
same_text() { [[ "$(cat "$1")" == "$2" ]]; }
assert_contains() {
	if grep -qF -- "$2" "$1"; then ok; else fail_msg "$3: '$2' not in $1"; fi
}
assert_not_contains() {
	if grep -qF -- "$2" "$1"; then fail_msg "$3: '$2' found in $1"; else ok; fi
}

# Stubs. curl records its arguments and request body, then answers from CURL_RESPONSE.
mkdir -p "${TMP}/bin"
cat >"${TMP}/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
printf '%s\n' "$@" >"${STUB_DIR}/curl-args"
while [[ $# -gt 0 ]]; do
	case "$1" in
	-o) out="$2" && shift 2 ;;
	--data-binary) cp "${2#@}" "${STUB_DIR}/curl-body" && shift 2 ;;
	*) shift ;;
	esac
done
cp "${CURL_RESPONSE}" "${out}"
printf '%s' "${CURL_STATUS:-200}"
EOF
cat >"${TMP}/bin/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_DIR}/uv-calls"
case "$*" in
*lint.py*) echo "LINT-FINDING: 太字が多い" ;;
*calques.py*) echo "CALQUE-CANDIDATE: 拾う" ;;
*newfacts.py*) echo "NEWFACT: 42" ;;
esac
EOF
chmod +x "${TMP}/bin/curl" "${TMP}/bin/uv"

cat >"${TMP}/ok.json" <<'EOF'
{"candidates":[{"content":{"parts":[{"thought":true,"text":"THINKING"},{"text":"直した本文。\n"}]},"finishReason":"STOP"}]}
EOF
cat >"${TMP}/truncated.json" <<'EOF'
{"candidates":[{"content":{"parts":[{"text":"途中まで"}]},"finishReason":"MAX_TOKENS"}]}
EOF
cat >"${TMP}/error.json" <<'EOF'
{"error":{"code":429,"message":"Resource has been exhausted"}}
EOF
printf '# 元の文書\n\n**重要**なのは元の本文です。\n' >"${TMP}/draft.md"
cp "${TMP}/draft.md" "${TMP}/draft.orig"

run() {
	rm -f "${TMP}/curl-args" "${TMP}/curl-body" "${TMP}/uv-calls"
	PATH="${TMP}/bin:${PATH}" STUB_DIR="${TMP}" CURL_RESPONSE="${CURL_RESPONSE:-${TMP}/ok.json}" \
		GEMINI_API_KEY="${TEST_KEY-test-key}" "${BASH_BIN:-bash}" "${SCRIPT}" "$@" >"${TMP}/out" 2>"${TMP}/err"
}

# Happy path: the rewrite goes to stdout, thinking parts are dropped, the source is untouched.
if run "${TMP}/draft.md"; then ok; else fail_msg "valid rewrite must succeed: $(cat "${TMP}/err")"; fi
expect "stdout must be the rewrite only" same_text "${TMP}/out" "直した本文。"
expect "source file must not change" cmp -s "${TMP}/draft.md" "${TMP}/draft.orig"
assert_contains "${TMP}/curl-args" "models/gemini-4-neon:generateContent" "default model"
assert_contains "${TMP}/curl-args" "x-goog-api-key: test-key" "key sent as header"
assert_contains "${TMP}/curl-body" "いちばん大事な規則" "natural-japanese SKILL.md is the system instruction"
assert_contains "${TMP}/curl-body" "元の本文です" "document in request"
assert_contains "${TMP}/curl-body" "LINT-FINDING" "lint findings in request"
assert_contains "${TMP}/curl-body" "CALQUE-CANDIDATE" "calque candidates in request"
assert_not_contains "${TMP}/curl-body" "test-key" "key stays out of the body"
expect "request shape" jq -e '.systemInstruction.parts[0].text and .contents[0].parts[0].text' "${TMP}/curl-body"
# The caller needs the added-facts report and a re-lint of the result, off stdout.
assert_contains "${TMP}/err" "NEWFACT: 42" "newfacts report on stderr"
assert_contains "${TMP}/uv-calls" "newfacts.py ${TMP}/draft.md" "newfacts compares against the source"

# Options: model override, genre, caller note, output file.
if NATURAL_JAPANESE_GEMINI_MODEL=gemini-4-carbon run --genre tech --note "社内向けに" --out "${TMP}/revised.md" "${TMP}/draft.md"; then ok; else fail_msg "options run failed: $(cat "${TMP}/err")"; fi
assert_contains "${TMP}/curl-args" "models/gemini-4-carbon:generateContent" "model override"
assert_contains "${TMP}/uv-calls" "--genre tech" "genre forwarded to lint"
assert_contains "${TMP}/curl-body" "社内向けに" "note in request"
expect "--out must receive the rewrite" same_text "${TMP}/revised.md" "直した本文。"
expect "--out keeps stdout empty" test ! -s "${TMP}/out"

# Refusals happen before any request.
if TEST_KEY="" run "${TMP}/draft.md"; then fail_msg "missing key must fail"; else ok; fi
expect "no request without a key" test ! -e "${TMP}/curl-args"
if run "${TMP}/missing.md"; then fail_msg "missing file must fail"; else ok; fi
if run --out "${TMP}/draft.md" "${TMP}/draft.md"; then fail_msg "--out must not overwrite the source"; else ok; fi
expect "source file must survive a refused --out" cmp -s "${TMP}/draft.md" "${TMP}/draft.orig"

# API failures and truncated output are errors, never a partial rewrite.
if CURL_RESPONSE="${TMP}/error.json" CURL_STATUS=429 run "${TMP}/draft.md"; then fail_msg "API error must fail"; else ok; fi
assert_contains "${TMP}/err" "Resource has been exhausted" "API error message surfaced"
expect "no stdout on API error" test ! -s "${TMP}/out"
if CURL_RESPONSE="${TMP}/truncated.json" run "${TMP}/draft.md"; then fail_msg "truncated output must fail"; else ok; fi
assert_contains "${TMP}/err" "MAX_TOKENS" "finish reason surfaced"
expect "no stdout on truncated output" test ! -s "${TMP}/out"

# macOS still ships bash 3.2 as /bin/bash; agents with a minimal PATH run it.
if [[ -x /bin/bash ]] && ! /bin/bash -c '[[ ${BASH_VERSINFO[0]} -ge 5 ]]'; then
	if BASH_BIN=/bin/bash run "${TMP}/draft.md"; then ok; else fail_msg "must run under /bin/bash: $(cat "${TMP}/err")"; fi
fi

echo "natural-japanese-gemini tests: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
