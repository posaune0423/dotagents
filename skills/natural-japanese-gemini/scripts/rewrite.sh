#!/usr/bin/env bash
# Rewrite a Japanese document with a Gemini model, using the natural-japanese
# skill as the system instruction. The deterministic checks (lint, calques,
# newfacts) run locally; only the rewriting is sent to the model.
#
#   stdout  the rewritten document (or nothing with --out)
#   stderr  progress, then the added-facts report and a re-lint of the result
#
# Bash 3.2 compatible: macOS /bin/bash runs this when PATH is minimal.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NJ_DIR="${NATURAL_JAPANESE_DIR:-${SCRIPT_DIR}/../../natural-japanese}"
MODEL="${NATURAL_JAPANESE_GEMINI_MODEL:-gemini-4-neon}"
API_BASE="${GEMINI_API_BASE:-https://generativelanguage.googleapis.com/v1beta}"

usage() {
	echo 'Usage: rewrite.sh [--out <file>] [--genre business|essay|tech] [--note <text>] <file>'
}
die() {
	echo "rewrite.sh: $*" >&2
	exit 1
}

out=""
genre=""
note=""
src=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--out | --genre | --note)
		[[ $# -ge 2 ]] || die "$1 needs a value"
		case "$1" in
		--out) out="$2" ;;
		--genre) genre="$2" ;;
		--note) note="$2" ;;
		esac
		shift 2
		;;
	--help | -h)
		usage
		exit 0
		;;
	-*) die "unknown option: $1" ;;
	*)
		[[ -z "$src" ]] || die "only one input file is supported"
		src="$1"
		shift
		;;
	esac
done

[[ -n "$src" ]] || {
	usage >&2
	exit 1
}
[[ -f "$src" && -s "$src" ]] || die "input file is missing or empty: $src"
[[ -f "${NJ_DIR}/SKILL.md" ]] || die "natural-japanese skill not found at ${NJ_DIR}"
[[ -n "${GEMINI_API_KEY:-}" ]] || die "GEMINI_API_KEY is not set"
for tool in curl jq; do
	command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done
if [[ -n "$out" && -e "$out" && "$out" -ef "$src" ]]; then
	die "--out must not be the input file; the original is needed to check for added facts"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A failed check must not block the rewrite; the model is told it is missing.
check() {
	local name="$1"
	shift
	if command -v uv >/dev/null 2>&1 && uv run "${NJ_DIR}/scripts/${name}" "$@" 2>"${tmp}/check.err"; then
		return 0
	fi
	echo "rewrite.sh: ${name} did not run; continuing without it" >&2
	echo "(${name} を実行できなかった)"
}
lint() {
	if [[ -n "$genre" ]]; then
		check lint.py --genre "$genre" --reading-load "$1"
	else
		check lint.py --reading-load "$1"
	fi
}

lint "$src" >"${tmp}/lint.txt"
check calques.py "$src" >"${tmp}/calques.txt"

cat >"${tmp}/preface.md" <<'EOF'
あなたは、下の natural-japanese スキルに従って日本語の文書を直す。

このスキルはツールを使えるエージェント向けに書かれているが、あなたはツールを使えない。次のように読み替える。

- スクリプトは実行できない。`scripts/lint.py --reading-load` と `scripts/calques.py` の結果は、依頼の中に添えてある。指摘は候補であり、直すかどうかは文脈を見て決める
- 「いちばん大事な規則:元にない内容を足さない」を最優先にする。事実・数値・意見・方針を足さず、確信の度合いも変えない
- `score` モード、文体プロファイルの作成、後片付けは行わない。別ファイル(`references/` など)は読めないので、このスキル本文だけで判断する
- 出力は、直した文書の全文だけにする。前置き、説明、変更点の一覧、文書全体を囲むコードフェンスは付けない

---

EOF
cat "${tmp}/preface.md" "${NJ_DIR}/SKILL.md" >"${tmp}/system.md"

{
	echo "次の文書を、スキルの規則に従って直してください。"
	if [[ -n "$note" ]]; then
		printf '\n依頼者からの補足:\n%s\n' "$note"
	fi
	printf '\n## lint.py --reading-load の結果\n\n'
	cat "${tmp}/lint.txt"
	printf '\n## calques.py の結果\n\n'
	cat "${tmp}/calques.txt"
	printf '\n## 文書(ここから末尾まで)\n\n'
	cat "$src"
} >"${tmp}/user.md"

jq -n --rawfile system "${tmp}/system.md" --rawfile user "${tmp}/user.md" '{
	systemInstruction: {parts: [{text: $system}]},
	contents: [{role: "user", parts: [{text: $user}]}]
}' >"${tmp}/request.json"

echo "rewrite.sh: asking ${MODEL}..." >&2
status="$(curl -sS --max-time "${NATURAL_JAPANESE_GEMINI_TIMEOUT:-900}" \
	-o "${tmp}/response.json" -w '%{http_code}' \
	-H "x-goog-api-key: ${GEMINI_API_KEY}" -H 'content-type: application/json' \
	--data-binary "@${tmp}/request.json" \
	"${API_BASE}/models/${MODEL}:generateContent")" || die "request to ${MODEL} failed"

api_error="$(jq -r '.error.message // empty' "${tmp}/response.json" 2>/dev/null || true)"
if [[ "$status" != 200 || -n "$api_error" ]]; then
	die "${MODEL} returned HTTP ${status}: ${api_error:-$(head -c 300 "${tmp}/response.json")}"
fi
finish="$(jq -r '.candidates[0].finishReason // "NONE"' "${tmp}/response.json")"
[[ "$finish" == STOP ]] || die "${MODEL} stopped with ${finish}; no rewrite was written"
jq -r '[.candidates[0].content.parts[]? | select(.thought != true) | .text // empty] | join("")' \
	"${tmp}/response.json" >"${tmp}/revised.md"
[[ -s "${tmp}/revised.md" ]] || die "${MODEL} returned an empty rewrite"

if [[ -n "$out" ]]; then
	cp "${tmp}/revised.md" "$out"
	revised="$out"
else
	cat "${tmp}/revised.md"
	revised="${tmp}/revised.md"
fi

# The model cannot verify its own output; hand the caller what it needs to.
{
	printf '\n== newfacts.py: 直した文書にだけある数値・固有名詞 ==\n'
	check newfacts.py "$src" "$revised"
	printf '\n== lint.py: 直した文書に残っている指摘 ==\n'
	lint "$revised"
} >&2
