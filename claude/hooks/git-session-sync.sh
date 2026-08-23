#!/bin/bash
# SessionStart hook: sync origin once before work starts and tell Claude what
# state the working tree is in. Read-mostly: the only write is a fast-forward of
# the default branch, and only when it is checked out and clean.
#
# Registered globally, so the default branch is resolved per repository instead
# of assuming master.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# No remote means nothing to sync against; stay silent rather than guess.
git remote get-url origin >/dev/null 2>&1 || exit 0

# A failed fetch must not be reported as a successful sync: origin/* refs would
# be stale and every conclusion drawn from them wrong.
fetch_ok=true
git fetch origin --prune --quiet 2>/dev/null || fetch_ok=false

if [ "$fetch_ok" = "true" ]; then
	# fetch does NOT refresh refs/remotes/origin/HEAD, so a repository cloned
	# before a default-branch rename keeps pointing at the old branch.
	git remote set-head origin --auto >/dev/null 2>&1 || true
fi

# Resolve the default branch without another network round trip.
default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
if [ -z "$default_branch" ]; then
	for candidate in main master; do
		if git show-ref --verify --quiet "refs/remotes/origin/${candidate}"; then
			default_branch="$candidate"
			break
		fi
	done
fi
[ -n "$default_branch" ] || exit 0

branch=$(git branch --show-current 2>/dev/null || echo "(detached)")
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
pulled="skipped"

if [ "$fetch_ok" != "true" ]; then
	pulled="fetch 失敗（origin の情報は古い可能性あり）"
elif [ "$branch" = "$default_branch" ] && [ "$dirty" = "0" ]; then
	if git merge --ff-only "origin/${default_branch}" --quiet 2>/dev/null; then
		pulled="ff-only で最新化済み"
	else
		pulled="ff できず（要確認）"
	fi
fi

if [ "$fetch_ok" = "true" ]; then
	behind=$(git rev-list --count "HEAD..origin/${default_branch}" 2>/dev/null || echo "?")
else
	behind="?"
fi
worktree=$(git rev-parse --show-toplevel 2>/dev/null)

if [ "$dirty" != "0" ]; then
	action="未コミットの変更が ${dirty} 件ある。作業を始める前に、この変更を commit / stash / 破棄のどれにするかユーザーに確認する。勝手に破棄しない。"
elif [ "$fetch_ok" != "true" ]; then
	action="origin への fetch に失敗した。origin/${default_branch} との差分は判定できないので、この報告を最新として扱わない。rebase や worktree の判断はユーザーに確認する。"
elif [ "$branch" = "$default_branch" ]; then
	action="${default_branch} 上にいて clean。軽微な修正以外は worktree を切って開始する（skill: git-wt）。"
elif [ "$behind" != "0" ] && [ "$behind" != "?" ]; then
	action="このブランチは origin/${default_branch} より ${behind} commit 遅れている。作業開始前に rebase するかユーザーに確認する。"
else
	action="clean かつ origin/${default_branch} に追随済み。そのまま作業を開始してよい。"
fi

jq -n \
	--arg wt "$worktree" \
	--arg b "$branch" \
	--arg db "$default_branch" \
	--arg d "$dirty" \
	--arg be "$behind" \
	--arg p "$pulled" \
	--arg a "$action" \
	'{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ("[git session sync] worktree: \($wt) / branch: \($b) / default: \($db) / 未コミット: \($d) 件 / origin/\($db) より behind: \($be) / \($db) の pull: \($p)\n→ \($a)")
    }
  }'
