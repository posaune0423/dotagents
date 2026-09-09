---
name: create-pr
description: >-
  Commit the current branch, open its pull request against main with the configured assignees and
  labels, then watch CI and review feedback until green. Use when asked to create a PR; for a PR that
  already exists use update-pr.
---

# Create PR

Open the pull request for the current branch against `main`, then see it through CI and review.

## Steps

1. Establish state: uncommitted changes, current branch, upstream, and whether a PR already exists (`gh pr view`). Commit remaining changes following the repository's commit conventions and push.
2. Write the description from `git diff origin/main...` so it covers every commit in the PR, not only the latest. Title under 80 characters, body under five sentences, written to a temp file.
3. Create the PR with `scripts/gh-pr-create-with-meta.sh --base main --title ... --body-file ...`; it accepts any `gh pr create` flag and applies assignees and labels from [pr-defaults.env](pr-defaults.env). If a PR already exists, update the body with `scripts/pr-body-update.sh --file <body>` and sync metadata with `scripts/pr-meta-sync.sh`.
   - Assignee defaults to `@me`; `CREATE_PR_ASSIGNEES` overrides, an empty value skips.
   - Labels: `CREATE_PR_LABELS` when set, otherwise one label inferred from the branch prefix via `scripts/infer-github-default-label.sh`; `CREATE_PR_NO_LABEL=1` skips labels.
4. Watch CI and review feedback, fix failures, resolve conflicts, and merge or clean up as described in [references/ci-and-merge.md](references/ci-and-merge.md).

## Boundaries

- Do not merge, force-push, or delete branches without the user's explicit confirmation in this session.
- Keep `gh` non-interactive. In CI, `GH_TOKEN` or `GITHUB_TOKEN` must be set.

## Report

PR URL, assignees and labels applied, CI status, review threads still open, and cleanup status.
