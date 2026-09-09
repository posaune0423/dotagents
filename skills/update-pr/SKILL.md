---
name: update-pr
description: >-
  Update an existing pull request: address review feedback, fix failing CI, resolve merge conflicts,
  and merge when asked. Use when a PR already exists for the branch; use create-pr to open a new one.
---

# Update Pull Request

Bring an existing pull request to a mergeable state.

## Steps

1. Identify the PR: `gh pr list --head "$(git branch --show-current)"` or `gh pr view <number>`, then read `gh pr diff` and `gh pr view --comments` for context.
2. Address review threads with the `resolve-review-comments` skill: collect, triage, implement minimal fixes, run the project's checks, push, and resolve the threads that are done.
3. Handle CI failures, merge conflicts, polling, merge, and worktree cleanup as described in [create-pr/references/ci-and-merge.md](../create-pr/references/ci-and-merge.md). Alternate review passes with CI polling until checks are green and actionable threads are cleared or explicitly deferred with the user.
4. If the PR should carry the standard assignees and labels, run `../create-pr/scripts/pr-meta-sync.sh`.

If a reviewer asks for a squash, rebase onto `origin/main` and push with `--force-with-lease`; that is the only force-push this skill performs, and only on request.

## Report

PR URL, CI status, review threads still open, assignees and labels if synced, and cleanup status if merged.
