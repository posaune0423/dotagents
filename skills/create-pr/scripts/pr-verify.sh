#!/usr/bin/env bash
# Read back the saved PR. Never retry creation after a verification failure.
set -euo pipefail
pr_url="${1:?Usage: pr-verify.sh <pr-url> [body-file]}"
hostname="${pr_url#https://}"
hostname="${hostname%%/*}"
login="$(gh api user --hostname "$hostname" --jq .login)"
[[ -n "$login" ]] || {
	echo "Cannot determine authenticated GitHub user" >&2
	exit 1
}
assignees="$(gh pr view "$pr_url" --json assignees --jq '.assignees[].login')"
if ! grep -qiFx -- "$login" <<<"$assignees"; then
	echo "PR exists at $pr_url but assignee $login is missing; repair this PR, do not create another." >&2
	exit 1
fi
if [[ -n "${2:-}" ]]; then
	body="$(gh pr view "$pr_url" --json body --jq .body)"
	if [[ "$body" != "$(cat "$2")" ]]; then
		echo "PR body mismatch at $pr_url; repair this PR, do not create another." >&2
		exit 1
	fi
fi
