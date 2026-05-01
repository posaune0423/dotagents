---
name: update-pr
description: Update an existing pull request with new changes or respond to review feedback. Use when addressing PR comments, making requested changes, or updating a PR after review.
---

# Update Pull Request

The current branch is $`git branch --show-current`.

**Existing PR:** $`gh pr view --json number,title,url --jq '"#\(.number): \(.title) - \(.url)"' 2>/dev/null || echo "None"`

Follow these steps (CI monitoring matches `create-pr`).

## Phase 1: Identify the PR

```bash
# List open PRs for current branch
gh pr list --head $(git branch --show-current)

# Or get PR details by number
gh pr view <PR_NUMBER>
```

## Phase 2: Fetch context & address feedback

```bash
# View PR reviews and comments
gh pr view <PR_NUMBER> --comments

# View the PR diff to understand context
gh pr diff <PR_NUMBER>
```

For each review comment:

1. Read and understand the feedback
2. Make the necessary code changes
3. Stage and commit with a descriptive message

```bash
# Stage changes
git add -u

# Commit with reference to what was addressed
git commit -m "address review: <brief description>"
```

### Push updates

```bash
# Push to the same branch (PR updates automatically)
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
- If you need full context after the script reports a new item, fetch details once with `gh pr view --comments` or `gh api ...`.
- **Address feedback**:
  - For bot reviews, read the review body and any inline comments carefully
  - Address comments that are clearly actionable (bug fixes, typos, simple improvements)
  - Skip comments that require design decisions or user input
  - For addressed feedback, commit fixes with a message referencing the review/comment
  - Return to Phase 2 (push) and Phase 3 (poll) until CI is green

## Phase 4: Merge and cleanup (if the user wants to merge)

Once CI passes and the PR is approved (or the user asks to merge), confirm with the user, then:

```bash
gh pr merge --squash --delete-branch
```

After a successful merge, check if we're in a git worktree:

- Run: `[ "$(git rev-parse --git-common-dir)" != "$(git rev-parse --git-dir)" ]`
- **If in a worktree**: Ask the user if they want to clean up the worktree. If yes, run `git worktree remove --force` to remove the worktree and local branch, then switch back to the main worktree.
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
# 1. Fetch latest review comments
gh pr view 42 --comments

# 2. Make changes based on feedback
# ... edit files ...

# 3. Commit and push
git add -u
git commit -m "address review: add error handling for edge case"
git push

# 4. Watch CI and triage (same as create-pr)
./.agents/skills/create-pr/scripts/poll-pr.sh --triage-on-change --exit-when-green
```
