#!/usr/bin/env bash
# Wraps `gh pr create` with assignees and labels from pr-defaults.env (optional env overrides).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/../pr-defaults.env"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/infer-github-default-label.sh"

if [[ -f "$DEFAULTS_FILE" ]]; then
	set -a
	# shellcheck disable=SC1090
	source "$DEFAULTS_FILE"
	set +a
fi

# Bash 3.2–compatible "is set" check (macOS /bin/bash).
if [[ -z "${CREATE_PR_ASSIGNEES+x}" ]]; then
	assignees_raw='@me'
else
	assignees_raw="$CREATE_PR_ASSIGNEES"
fi

create_args=()
if [[ -n "$assignees_raw" ]]; then
	IFS=',' read -ra parts <<<"$assignees_raw"
	for p in "${parts[@]}"; do
		p="${p#"${p%%[![:space:]]*}"}"
		p="${p%"${p##*[![:space:]]}"}"
		[[ -z "$p" ]] && continue
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

exec gh pr create "${create_args[@]}" "$@"
