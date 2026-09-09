# CI, merge, and cleanup

Shared by `create-pr` and `update-pr`. Paths are relative to `skills/create-pr/`.

## Watching CI and feedback

Run `scripts/poll-pr.sh --triage-on-change --exit-when-green` instead of polling `gh` in a loop. It checks every 15 seconds for up to 10 minutes and reports new checks, reviews, and comments. For a one-off snapshot use `scripts/triage-pr.sh`; for the full text of one item use `gh pr view --comments` or `gh api` once.

When a check fails, find the run with `gh pr checks` or `gh run list`, read `gh run view <run-id> --log-failed`, fix the cause, commit, push, and resume polling. Never change a test expectation or add a suppression to make CI green.

Review threads are a separate track from CI. Handle them with the `resolve-review-comments` skill on every new batch; green CI with open threads is not done.

## Merge conflicts

`git fetch origin main && git merge origin/main`, resolve conflicts, commit the merge, push, and poll again if CI re-ran.

## Merging

Merge only after CI is green, the PR is approved, and the user has confirmed the merge in this session:

```bash
gh pr merge --merge --delete-branch
```

## After a merge

Check whether the session is in a linked worktree: `[ "$(git rev-parse --git-common-dir)" != "$(git rev-parse --git-dir)" ]`.

- In a worktree, ask the user whether to remove it. In Claude Code, `ExitWorktree` with `action: "remove"` removes it and returns the session to the main checkout. Otherwise capture the main checkout and branch first, because the current directory disappears once the worktree is removed:

  ```bash
  MAIN_WORKTREE="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  BRANCH="$(git branch --show-current)"
  git -C "$MAIN_WORKTREE" worktree remove <worktree-path>
  git -C "$MAIN_WORKTREE" branch -d "$BRANCH"
  ```

  Both commands refuse to discard work (`remove` stops on a dirty worktree, `branch -d` on an unmerged branch); escalate to `--force` or `-D` only when the user confirms discarding it. Run every later command as `git -C "$MAIN_WORKTREE" ...`, since a shell `cd` does not persist between tool calls.

- Otherwise `git checkout main && git pull`.
