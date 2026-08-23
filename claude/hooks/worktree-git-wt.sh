#!/bin/bash
# WorktreeCreate / WorktreeRemove hook: hand Claude Code's worktree lifecycle to
# git-wt so every worktree follows the same rules as a manual `git wt`, wherever
# it was started from (CLI, subagent isolation, or the desktop app).
#
# Contract (Claude Code):
#   WorktreeCreate  stdin {"name": "<slug>"}          -> print the absolute path
#   WorktreeRemove  stdin {"worktree_path": "<abs>"}  -> exit 0 when removed
#
# Because this hook replaces the built-in git logic, `.worktreeinclude` is NOT
# processed. git-wt's own `wt.copy` carries the gitignored files instead, so the
# copy list lives in git config rather than in each repository.
set -uo pipefail

input="$(cat)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty')"

if ! command -v git-wt >/dev/null 2>&1; then
	echo "git-wt is not installed; cannot manage worktrees" >&2
	exit 1
fi

# Resolve the remote default branch so a new worktree starts from current trunk
# rather than from whatever happens to be checked out.
default_start_point() {
	local remote_head candidate
	remote_head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || remote_head=""
	if [ -n "$remote_head" ]; then
		printf '%s\n' "$remote_head"
		return 0
	fi
	for candidate in main master; do
		if git show-ref --verify --quiet "refs/remotes/origin/${candidate}"; then
			printf 'origin/%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

# Trim surrounding whitespace without word-splitting; an unquoted `xargs` would
# break on paths containing spaces.
trim() {
	local v="$1"
	v="${v#"${v%%[![:space:]]*}"}"
	printf '%s' "${v%"${v##*[![:space:]]}"}"
}

case "$event" in
WorktreeCreate)
	name="$(printf '%s' "$input" | jq -r '.name // empty')"
	if [ -z "$name" ]; then
		echo "WorktreeCreate: no name supplied" >&2
		exit 1
	fi

	# Claude Code's built-in creation fetches before branching ("fresh" baseRef);
	# this hook replaces that, so fetch here or the worktree starts from a stale
	# origin ref. Non-fatal: without a network we still branch from what we have.
	# fetch does not refresh origin/HEAD either, hence set-head afterwards.
	if git remote get-url origin >/dev/null 2>&1; then
		git fetch --quiet origin >/dev/null 2>&1 || true
		git remote set-head origin --auto >/dev/null 2>&1 || true
	fi

	# git-wt prints the worktree path as the LAST line of stdout; its progress
	# output goes to stderr, which Claude Code surfaces when the hook fails.
	if start_point="$(default_start_point)"; then
		out="$(git wt --nocd "$name" "$start_point")" || exit 1
	else
		out="$(git wt --nocd "$name")" || exit 1
	fi

	path="$(trim "$(printf '%s' "$out" | tail -n 1)")"
	if [ ! -d "$path" ]; then
		echo "WorktreeCreate: git wt did not report a directory (got: ${path})" >&2
		exit 1
	fi
	printf '%s\n' "$path"
	;;
WorktreeRemove)
	path="$(printf '%s' "$input" | jq -r '.worktree_path // empty')"
	if [ -z "$path" ]; then
		echo "WorktreeRemove: no worktree_path supplied" >&2
		exit 1
	fi
	# Idempotent: a path that is already gone counts as removed, so a repeated
	# cleanup does not surface an error.
	if [ ! -e "$path" ]; then
		exit 0
	fi
	# `-d` is the safe form: it refuses while the worktree still holds work.
	# Report that refusal instead of exiting 0 and claiming a removal.
	git wt -d "$path" || exit 1
	;;
*)
	echo "unsupported hook event: ${event:-<none>}" >&2
	exit 1
	;;
esac
