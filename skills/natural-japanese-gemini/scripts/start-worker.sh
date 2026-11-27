#!/usr/bin/env bash
# Start one Orca worker (Antigravity on a Gemini model) that rewrites a Japanese
# document by following the natural-japanese skill, and print Orca's receipt.
# Orca wakes the caller with the worker's report; this script does not wait.
#
# Bash 3.2 compatible: macOS /bin/bash runs this when PATH is minimal.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${NATURAL_JAPANESE_GEMINI_MODEL:-gemini-4-hydrogen-high}"

usage() {
	echo 'Usage: start-worker.sh --out <revised-file> [--note <text>] <source-file>'
}
die() {
	echo "start-worker.sh: $*" >&2
	exit 1
}
# Absolute path of a file whose directory exists; the file itself may not.
abs_path() {
	local dir
	dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
	printf '%s/%s\n' "$dir" "$(basename "$1")"
}

out=""
note=""
src=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--out | --note)
		[[ $# -ge 2 ]] || die "$1 needs a value"
		if [[ "$1" == --out ]]; then out="$2"; else note="$2"; fi
		shift 2
		;;
	--help | -h)
		usage
		exit 0
		;;
	-*) die "unknown option: $1" ;;
	*)
		[[ -z "$src" ]] || die "only one source file is supported"
		src="$1"
		shift
		;;
	esac
done

[[ -n "$src" && -n "$out" ]] || {
	usage >&2
	exit 1
}
[[ -f "$src" && -s "$src" ]] || die "source file is missing or empty: $src"
nj_dir="$(cd "${NATURAL_JAPANESE_DIR:-${SCRIPT_DIR}/../../natural-japanese}" 2>/dev/null && pwd -P)" ||
	die "natural-japanese skill not found next to this skill"
[[ -f "${nj_dir}/SKILL.md" ]] || die "natural-japanese skill not found at ${nj_dir}"
src_abs="$(abs_path "$src")"
out_abs="$(abs_path "$out")" || die "directory of --out does not exist: $out"
[[ "$out_abs" != "$src_abs" && ! "$out" -ef "$src" ]] ||
	die "--out must not be the source file; the original is needed to check for added facts"
command -v orca >/dev/null 2>&1 || die "orca CLI is required"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

{
	cat <<EOF
natural-japanese スキルで、日本語の文書を1つ直してください。

- スキル: ${nj_dir}/SKILL.md を最初に全部読み、その手順どおりに進める(write モード、既存の文書を直す)。スクリプトは \`uv run ${nj_dir}/scripts/<名前>.py\` で実行する
- 元の文書: ${src_abs}
- 直した文書の出力先: ${out_abs}
EOF
	if [[ -n "$note" ]]; then
		printf -- '- 依頼者からの補足: %s\n' "$note"
	fi
	cat <<EOF

制約:

- 編集してよいのは出力先のファイルだけ。元の文書も、ほかのファイルも書き換えない。コミットもしない
- 元の文書にない事実・数値・意見・方針を足さない。確信の度合いも変えない

完了の報告(worker_done)に含めるもの:

1. 出力先のパス
2. 直す前と直した後の \`lint.py\` の検出件数
3. \`uv run ${nj_dir}/scripts/newfacts.py ${src_abs} ${out_abs}\` の結果
4. 直さずに残した指摘と、その理由

スクリプトが実行できないなど、手順を進められないときは、推測で続けずに失敗として報告する。
EOF
} >"${tmp}/spec.md"

orca orchestration worker-start --environment local \
	--spec-file "${tmp}/spec.md" \
	--task-title "natural-japanese: $(basename "$src")" \
	--worktree current --agent antigravity --model "$MODEL" --json
