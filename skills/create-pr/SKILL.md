---
name: create-pr
description: >-
  Create or update a PR from the current branch to main with a reviewer-first
  body that follows the repo's PR template, then watch CI and address feedback.
  Review threads go through skills/resolve-review-comments/SKILL.md; failing
  checks are fixed from logs and CI config.
---

Uncommitted changes: $`git status --porcelain | wc -l | tr -d ' '`. Branch: $`git branch --show-current` → origin/main.
Upstream: $`git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "none"`.
Existing PR: $`gh pr view --json number,title,url --jq '"#\(.number): \(.title) - \(.url)"' 2>/dev/null || echo "None"`.
PR template: $`./.agents/skills/create-pr/scripts/pr-template.sh --path 2>/dev/null || echo "none"`.
PR language: $`./.agents/skills/create-pr/scripts/pr-lang.sh 2>/dev/null || echo "en"`.

Scripts below live in `./.agents/skills/create-pr/scripts/`.

## 1. Review, commit, push

Review the change first: test coverage, silent failures, stale comments, new types, general quality. Fix what you find. Then `git diff`, commit per the user's instructions and `rules/commit-style.mdc`, and push (`git push -u origin HEAD` when there is no upstream).

## 2. Write the PR body for the reviewer

Read the whole PR, not the last commit: `git diff origin/main...` and `git log origin/main..`.

The reader has ten minutes and no context. Every sentence must save them time or it goes.

- **Language.** Write the title and body in the PR language above (default `en`). Template headings, code, and commands stay as they are. When the user asks to remember a language for a repo or org, run `pr-lang.sh --set <lang> [--for owner]`; it persists in the gitignored `pr-lang.local` (format: `pr-lang.local.example`).
- **Template first.** If a template exists, `pr-template.sh` prints it. Keep every heading, in order. Replace each HTML comment with content or `N/A: <reason>`. Tick a checkbox only when it is true. Never add or drop sections. Without a template, use the layout below and drop only the optional sections that do not apply.
- **Why before what.** Open with the problem in one or two sentences and link the issue or spec (`Closes #N`).
- **Behavior, not files.** Say what changes for users and callers. The diff already lists files.
- **Show, don't narrate.** A before/after table beats a paragraph. A Mermaid diagram (`sequenceDiagram` for request or event flows, `flowchart` for branching or state) earns its place only when the change alters a flow across three or more components; otherwise leave it out.
- **Screenshots for UI.** Any visible change gets a before/after table. Capture them yourself when the app can run locally (a project skill such as `pr-ui-screenshot` first, then Playwright). If you cannot, leave `TODO(author)` cells and say so in the report.
- **Review guide.** Where to start, which hunks carry the risk, what looks odd but is intentional, and what to skip (generated, moved, renamed). Telling the reviewer what to ignore saves the most time.
- **Verification as evidence.** One row per check with its result; separate local, CI, and manual. Claim only what you ran.
- **Risk and rollout.** Breaking changes, migrations, config or env, flags, rollback. `None` when there is none.
- **Out of scope.** Name known gaps and follow-ups so the reviewer does not raise them.
- Under roughly 300 words beyond the template. No marketing tone, no diff narration, no empty headings.

Default layout when no template exists (sections marked _optional_ are dropped when empty):

````markdown
## Why

<1–2 sentences: problem, who hits it, link `Closes #N`.>

## What changed

| Area | Before | After |
| ---- | ------ | ----- |

## How it works <!-- optional: only when a flow across 3+ components changed -->

```mermaid
sequenceDiagram
```

## Screenshots <!-- required for any visible UI change -->

| Before | After |
| ------ | ----- |

## Review guide

1. Start at `<file>`: <what it decides>.
2. Risk: <hunk and why>.
3. Skip: <generated / moved / renamed>.

## Verification

| Check | How | Result |
| ----- | --- | ------ |

## Risk / rollout

None

## Out of scope <!-- optional -->
````

Title: at most 72 characters, `${emoji} ${type}(${scope}): ${summary}` per `rules/commit-style.mdc`.

## 3. Create or update the PR

Write the body to a temp file, then:

- **Existing PR:** `pr-body-update.sh --file <file>` (writes via GraphQL and verifies the result), then `pr-meta-sync.sh`.
- **New PR:** `gh-pr-create-with-meta.sh --base main --title "<title>" --body-file <file>`. Never use `--fill`; it bypasses the template and the rules above.
- Assignees and labels come from `pr-defaults.env` (`CREATE_PR_ASSIGNEES`, `CREATE_PR_LABELS`, `CREATE_PR_NO_LABEL=1`). Without `CREATE_PR_LABELS`, one GitHub stock label is inferred from the branch prefix; it must exist on the repo.

## 4. CI and review feedback

Failing checks and review feedback are two tracks. Green CI is not done while review threads stay open.

1. `poll-pr.sh --triage-on-change --exit-when-green` (15 s × 10 min). On a failure: `gh run view <run-id> --log-failed`, fix the root cause, commit, push, poll again.
2. `git fetch origin main && git merge origin/main`; resolve conflicts, commit, push.
3. For any review comment, bot suggestion, or reviewer request, run `skills/resolve-review-comments/SKILL.md` end to end, once per new batch. `triage-pr.sh` gives a one-shot snapshot.

Keep `gh` non-interactive; CI needs `GH_TOKEN` or `GITHUB_TOKEN`.

## 5. Merge and cleanup

Merge only after CI is green, the PR is approved, and the user confirms: `gh pr merge --merge --delete-branch`.

Then, if `[ "$(git rev-parse --git-common-dir)" != "$(git rev-parse --git-dir)" ]` (a worktree), ask whether to clean up. Prefer the `ExitWorktree` tool with `action: "remove"`. Without it, capture `MAIN_WORKTREE="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"` and `BRANCH="$(git branch --show-current)"` first, since the current directory disappears; then `git -C "$MAIN_WORKTREE" worktree remove <path>` and `git -C "$MAIN_WORKTREE" branch -d "$BRANCH"`. Escalate to `--force` or `-D` only when the user confirms discarding work, and keep using `git -C "$MAIN_WORKTREE"` because `cd` does not persist between tool calls. Not in a worktree: `git checkout main && git pull`.

## Report

PR URL, assignees and labels, CI state, review threads still needing the user, cleanup state. Ask the user when a step cannot be resolved.
