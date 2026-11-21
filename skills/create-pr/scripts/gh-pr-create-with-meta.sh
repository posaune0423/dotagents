#!/usr/bin/env bash
# Validates the template, assigns self plus configured assignees, and verifies the saved PR.
# New PRs open as drafts unless CREATE_PR_DRAFT=0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../pr-defaults.env"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/infer-github-default-label.sh"

body_file=""
template_name=""
caller_args=()
while [[ $# -gt 0 ]]; do
	case "$1" in
	--body-file | -F | --template-name)
		[[ $# -ge 2 && -n "$2" ]] || {
			echo "Missing value for $1" >&2
			exit 1
		}
		if [[ "$1" == --template-name ]]; then
			template_name="$2"
		else
			body_file="$2"
		fi
		shift 2
		;;
	--body-file=*)
		body_file="${1#*=}"
		shift
		;;
	--body | --body=* | -b* | --fill* | --template | --template=* | -T* | --web | -w | --editor | -e | --dry-run)
		echo "$1 is unsupported: use --body-file with the resolved PR template." >&2
		exit 1
		;;
	--help | -h)
		echo 'Usage: gh-pr-create-with-meta.sh --body-file <file> [--template-name <name.md>] [gh pr create options]'
		exit 0
		;;
	*)
		caller_args+=("$1")
		shift
		;;
	esac
done
[[ -n "$body_file" ]] || {
	echo "--body-file is required" >&2
	exit 1
}
bash "${SCRIPT_DIR}/pr-body-validate.sh" "$body_file" "$template_name"

if [[ -f "$DEFAULTS_FILE" ]]; then
	set -a
	# shellcheck disable=SC1090
	source "$DEFAULTS_FILE"
	set +a
fi

assignees_raw="${CREATE_PR_ASSIGNEES:-}"

create_args=(--assignee '@me')
if [[ "${CREATE_PR_DRAFT:-1}" != "0" ]]; then
	create_args+=(--draft)
fi

if [[ -n "$assignees_raw" ]]; then
	IFS=',' read -ra parts <<<"$assignees_raw"
	for p in "${parts[@]}"; do
		p="${p#"${p%%[![:space:]]*}"}"
		p="${p%"${p##*[![:space:]]}"}"
		[[ -z "$p" || "$p" == '@me' ]] && continue
		create_args+=(--assignee "$p")
	done
fi

if [[ "${CREATE_PR_NO_LABEL:-}" != "1" ]]; then
	labels_raw=""
	if [[ -n "${CREATE_PR_LABELS:-}" ]]; then
		labels_raw="$CREATE_PR_LABELS"
	else
		labels_raw="$(infer_github_default_label_from_git)"
	fi
	if [[ -n "$labels_raw" ]]; then
		IFS=',' read -ra labs <<<"$labels_raw"
		for l in "${labs[@]}"; do
			l="${l#"${l%%[![:space:]]*}"}"
			l="${l%"${l##*[![:space:]]}"}"
			[[ -z "$l" ]] && continue
			create_args+=(--label "$l")
		done
	fi
fi

pr_url="$(gh pr create "${create_args[@]}" "${caller_args[@]}" --body-file "$body_file")"
printf '%s\n' "$pr_url"
bash "${SCRIPT_DIR}/pr-verify.sh" "$pr_url" "$body_file"
