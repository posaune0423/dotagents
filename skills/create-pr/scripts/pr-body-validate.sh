#!/usr/bin/env bash
# Check required template headings, in order, before sending a body to GitHub.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
body_file="${1:?Usage: pr-body-validate.sh <body-file> [template-name]}"
template_args=()
[[ -z "${2:-}" ]] || template_args=(--name "$2")
[[ -s "$body_file" && -f "$body_file" ]] || {
	echo "PR body file is missing or empty: $body_file" >&2
	exit 1
}
if grep -qE 'Generated with \[?Claude Code\]?|claude\.com/claude-code' "$body_file"; then
	echo 'PR body must not contain the "Generated with Claude Code" footer; remove that line.' >&2
	exit 1
fi
template="$(bash "${SCRIPT_DIR}/pr-template.sh" --path "${template_args[@]}")"
is_default=0
[[ "$template" != "${SCRIPT_DIR%/scripts}/assets/default-pr-template.md" ]] || is_default=1

# Ignore fenced examples and HTML comments. Only the bundled default can mark
# sections optional; repository headings remain mandatory.
awk -v default_template="$is_default" '
FNR == 1 { fence = ""; comment = 0; heading = 0 }
{
    line = $0
    sub(/\r$/, "", line)
    if (!comment && match(line, /^ ? ? ?(```+|~~~+)/)) {
        marker = substr(line, 1, RLENGTH); sub(/^ */, "", marker)
        tail = substr(line, RLENGTH + 1)
        if (fence == "") {
            fence = substr(marker, 1, 1); fence_length = length(marker)
        } else if (fence == substr(marker, 1, 1) && length(marker) >= fence_length && tail ~ /^[ \t]*$/) {
            fence = ""
        }
        next
    }
    if (fence != "") next
    if (NR == FNR && default_template && line ~ /<!-- optional:/) optional[heading] = 1
    clean = ""
    while (length(line)) {
        if (comment) {
            end = index(line, "-->")
            if (!end) break
            line = substr(line, end + 3); comment = 0
        } else {
            start = index(line, "<!--")
            if (!start) { clean = clean line; break }
            clean = clean substr(line, 1, start - 1)
            line = substr(line, start + 4); comment = 1
        }
    }
    sub(/[ \t]+$/, "", clean)
    if (clean !~ /^#+[ \t]+/) next
    if (NR == FNR) required[++heading_count] = clean
    else actual[++actual_count] = clean
    heading = heading_count
}
END {
    cursor = 1
    for (i = 1; i <= heading_count; i++) {
        if (actual[cursor] != required[i] && optional[i]) continue
        if (cursor > actual_count || actual[cursor] != required[i]) {
            print "Missing or out-of-order PR heading: " required[i] > "/dev/stderr"
            exit 1
        }
        cursor++
    }
    if (cursor <= actual_count) {
        print "Unexpected PR heading: " actual[cursor] > "/dev/stderr"
        exit 1
    }
}' "$template" "$body_file"
