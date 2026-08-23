---
name: update-pr
description: >-
  Update an existing PR or respond to review feedback. For review threads, follow
  skills/resolve-review-comments/SKILL.md; for failing CI, follow the CI/poll
  steps below.
---

# Update Pull Request

The current branch is $`git branch --show-current`.

**Existing PR:** $`gh pr view --json number,title,url --jq '"#\(.number): \(.title) - \(.url)"' 2>/dev/null || echo "None"`

Follow these steps (CI monitoring matches `create-pr`).

**Review comments:** Use **`skills/resolve-review-comments/SKILL.md`** as the dedicated playbook for triaging and implementing reviewer/bot feedback. Use **Phase 3** below mainly for **CI failures, merge conflicts, and polling**—do not collapse “update PR” into CI-only fixes.

## Phase 1: Identify the PR

```bash
# List open PRs for current branch
gh pr list --head $(git branch --show-current)

# Or get PR details by number
gh pr view <PR_NUMBER>
```

## Phase 2: Fetch context & address feedback

1. Open **`skills/resolve-review-comments/SKILL.md`** and run **Phases 1–5** there (collect comments, triage, implement, quality gate, push, optional replies).

2. Quick context (still useful before or during that skill):

```bash
gh pr view <PR_NUMBER> --comments
gh pr diff <PR_NUMBER>
```

3. Stage/commit conventions are defined in the resolve-review-comments skill; typical flow:

```bash
git add -u
git commit -m "address review: <brief description>"
git push
```

### Optional: reply or re-request review

If you need to reply to specific comments:

```bash
# Reply to a review comment
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments/<COMMENT_ID>/replies \
  -f body="Done - updated the implementation as suggested"
```

Or use the GitHub web interface for complex discussions.

```bash
# Re-request review from specific reviewers
gh pr edit <PR_NUMBER> --add-reviewer <username>
```

### Optional: keep assignees/labels in sync with create-pr defaults

After pushing, if the PR should match `./.agents/skills/create-pr/pr-defaults.env`:

```bash
./.agents/skills/create-pr/scripts/pr-meta-sync.sh
```

## Phase 3: Monitor CI and address issues

Note: Keep commands CI-safe and avoid interactive `gh` prompts. Ensure `GH_TOKEN` or `GITHUB_TOKEN` is set in CI.

1. Watch CI status and feedback using the polling script (instead of running `gh` in a loop):

- Run `./.agents/skills/create-pr/scripts/poll-pr.sh --triage-on-change --exit-when-green` (polls every 15s for 10 mins).
- If checks fail, use `gh pr checks` or `gh run list` to find the failing run id, then:
  - Fetch the failed check logs using `gh run view <run-id> --log-failed`
  - Analyze the failure and fix the issue
  - Commit and push the fix
  - Continue polling until all checks pass

2. Check for merge conflicts:

- Run `git fetch origin main && git merge origin/main`
- If conflicts exist, resolve them sensibly
- Commit the merge resolution and push
- Re-run the polling step above if CI re-ran

3. Use the polling script output to notice new reviews and comments (avoid direct polling via `gh`):

- If you need a full snapshot, run `./.agents/skills/create-pr/scripts/triage-pr.sh` once.
- When new review items appear, return to **Phase 2** and **`skills/resolve-review-comments/SKILL.md`** before assuming the PR is done.
- Alternate **resolve-review-comments** passes with CI polling until checks are green **and** actionable review threads are cleared (or explicitly deferred with the user).

## Phase 4: Merge and cleanup (if the user wants to merge)

Once CI passes and the PR is approved (or the user asks to merge), confirm with the user, then:

```bash
gh pr merge --merge --delete-branch
```

After a successful merge, check if we're in a git worktree:

- Run: `[ "$(git rev-parse --git-common-dir)" != "$(git rev-parse --git-dir)" ]`
- **If in a worktree**: Ask the user if they want to clean up the worktree. If yes:
  1. In Claude Code, use the `ExitWorktree` tool with `action: "remove"`. It removes the worktree and returns the session to the main checkout, so no path bookkeeping is needed.
  2. Without that tool, capture the main worktree and branch first, because the current directory stops existing once the worktree is deleted: `MAIN_WORKTREE="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"` and `BRANCH="$(git branch --show-current)"`. Then run `git -C "$MAIN_WORKTREE" worktree remove <worktree-path>` followed by `git -C "$MAIN_WORKTREE" branch -d "$BRANCH"`. Both already refuse to discard work: `remove` stops on a dirty worktree and `branch -d` on an unmerged branch. Escalate to `--force` or `-D` only when the user confirms discarding it.
  3. Run every later command against the captured path (`git -C "$MAIN_WORKTREE" ...`); a shell `cd` does not persist between tool calls.
- **If not in a worktree**: Switch back to main with `git checkout main && git pull`

## Handling common review requests

### "Please add tests"

1. Identify the appropriate test locations in the repo
2. Add test cases covering the new functionality
3. Run the project's test command when defined (e.g. `bun test`) to verify

### "Update types"

1. Run the project's typecheck/build command
2. Update type definitions as needed
3. Ensure no type errors remain

### "Fix lint issues"

Run the repo's format/lint commands (e.g. `bun run format` / `bun run lint`, and `bun run check` when a single gate is preferred).

### "Update snapshots"

Follow the project's snapshot update workflow and commit updated artifacts.

## Squashing commits (if requested)

If the reviewer asks to squash commits:

```bash
# Interactive rebase to squash
git rebase -i origin/main

# In the editor, change 'pick' to 'squash' for commits to combine
# Save and edit the combined commit message

# Force push (safe for PR branches)
git push --force-with-lease
```

## Completion

Report to the user:

- PR URL
- CI status (passed / still failing / merged)
- Assignees and labels if you ran `pr-meta-sync.sh`
- Any unresolved review comments that need user attention
- Cleanup status (worktree removed or branch switched) if you merged

If any step fails in a way you cannot resolve, ask the user for help.

## Example workflow

```bash
# 1. Follow skills/resolve-review-comments/SKILL.md (includes fetching comments + implementing)

# 2. Commit and push
git add -u
git commit -m "address review: add error handling for edge case"
git push

# 3. Watch CI and triage (same as create-pr); if new comments appear, re-run resolve-review-comments
./.agents/skills/create-pr/scripts/poll-pr.sh --triage-on-change --exit-when-green
```
