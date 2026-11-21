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

Set `CREATE_PR_SKILL_DIR` to the absolute directory containing the **loaded copy of this SKILL.md**. Run its scripts by absolute path, keeping the working directory in the target repository. Do not assume that the repository has `.agents/skills/`.

Resolve and read the template before writing the body:

```bash
bash "$CREATE_PR_SKILL_DIR/scripts/pr-template.sh"
bash "$CREATE_PR_SKILL_DIR/scripts/pr-lang.sh"
```

The template resolver returns the repository template when one exists, otherwise [assets/default-pr-template.md](assets/default-pr-template.md). There is no template-free path. Errors must remain visible: never use `2>/dev/null || echo none`. For multiple repository templates, select the applicable file with `--name <file.md>` and pass the same choice as `--template-name <file.md>` when creating or updating the PR.

All script names below refer to `$CREATE_PR_SKILL_DIR/scripts/`.

## 1. Review, commit, push

Review the change first: test coverage, silent failures, stale comments, new types, general quality. Fix what you find. Then `git diff`, commit per the user's instructions and `rules/commit-style.mdc`, and push (`git push -u origin HEAD` when there is no upstream).

## 2. Write the PR body for the reviewer

Read the whole PR, not the last commit: `git diff origin/main...` and `git log origin/main..`.

The reader has ten minutes and no context. Every sentence must save them time or it goes.

- **Language.** Write the title and body in the PR language above (default `en`). Template headings, code, and commands stay as they are. When the user asks to remember a language for a repo or org, run `pr-lang.sh --set <lang> [--for owner]`; it persists in the gitignored `pr-lang.local` (format: `pr-lang.local.example`).
- **Template first.** Use the body returned by `pr-template.sh`. For a repository template, keep every heading in order and never add or drop sections. Otherwise use the skill default, retaining its required headings in order and dropping only optional sections that do not apply. Replace HTML comments with content or `N/A: <reason>`. Tick a checkbox only when it is true.
- **Why before what.** Open with the problem in one or two sentences and link the issue or spec (`Closes #N`).
- **Behavior, not files.** Say what changes for users and callers. The diff already lists files.
- **Show, don't narrate.** A before/after table beats a paragraph. A Mermaid diagram (`sequenceDiagram` for request or event flows, `flowchart` for branching or state) earns its place only when the change alters a flow across three or more components; otherwise leave it out.
- **Screenshots for UI.** Any visible change gets a before/after table. Capture them yourself when the app can run locally (a project skill such as `pr-ui-screenshot` first, then Playwright). If you cannot, leave `TODO(author)` cells and say so in the report.
- **Review guide.** Where to start, which hunks carry the risk, what looks odd but is intentional, and what to skip (generated, moved, renamed). Telling the reviewer what to ignore saves the most time.
- **Verification as evidence.** One row per check with its result; separate local, CI, and manual. Claim only what you ran.
- **Risk and rollout.** Breaking changes, migrations, config or env, flags, rollback. `None` when there is none.
- **Out of scope.** Name known gaps and follow-ups so the reviewer does not raise them.
- Under roughly 300 words beyond the template. No marketing tone, no diff narration, no empty headings.

The default template's required sections are Why, What changed, Review guide, Verification, and Risk / rollout. Its conditional sections are How it works, Screenshots, and Out of scope; Screenshots is mandatory for visible UI changes. The template file is the source of truth for the layout. Scripts check required headings and order; the agent must also check the contents and conditional sections against the actual diff.

Title: at most 72 characters, `${type}(${scope}): ${subject}` (or `${type}: ${subject}` without a scope) per `rules/commit-style.mdc`. No emoji. With squash merges the title becomes the commit on the base branch.

## 3. Create or update the PR

Write the body to a temp file, then:

- **Existing PR:** `pr-body-update.sh --file <file>` (writes via GraphQL and verifies the result), then `pr-meta-sync.sh`.
- **New PR:** `gh-pr-create-with-meta.sh --base main --title "<title>" --body-file <file>`. It validates required template headings before creating a draft (`CREATE_PR_DRAFT=0` opts out). Always use this wrapper, never plain `gh pr create`, `--fill`, or an alternative API that skips validation and assignment.
- Creation and metadata sync always add `@me` (the authenticated GitHub user). `CREATE_PR_ASSIGNEES` in `pr-defaults.env` adds other assignees; leaving it empty cannot disable self-assignment. Labels still use `CREATE_PR_LABELS` / `CREATE_PR_NO_LABEL=1`; without an explicit label, one GitHub stock label is inferred from the branch prefix and must exist on the repo.
- The helpers read back the saved body and assignees. A verification failure is not success: fix the existing PR at the reported URL and rerun verification with `pr-verify.sh <pr-url> <body-file>`. Never retry creation for a PR that already exists. Report the selected template path and verified assignees.

## 4. CI and review feedback

Failing checks and review feedback are two tracks. Green CI is not done while review threads stay open.

1. `poll-pr.sh --triage-on-change --exit-when-green` (15 s × 10 min). On a failure: `gh run view <run-id> --log-failed`, fix the root cause, commit, push, poll again.
2. `git fetch origin main && git merge origin/main`; resolve conflicts, commit, push.
3. Once CI is green, mark a draft ready for review with `gh pr ready`.
4. For any review comment, bot suggestion, or reviewer request, run `skills/resolve-review-comments/SKILL.md` end to end, once per new batch. `triage-pr.sh` gives a one-shot snapshot.

Keep `gh` non-interactive; CI needs `GH_TOKEN` or `GITHUB_TOKEN`.

## 5. Merge and cleanup

Merge only after CI is green, the PR is approved, and the user confirms: `gh pr merge --merge --delete-branch`.

Then, if `[ "$(git rev-parse --git-common-dir)" != "$(git rev-parse --git-dir)" ]` (a worktree), ask whether to clean up. Prefer the `ExitWorktree` tool with `action: "remove"`. Without it, capture `MAIN_WORKTREE="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"` and `BRANCH="$(git branch --show-current)"` first, since the current directory disappears; then `git -C "$MAIN_WORKTREE" worktree remove <path>` and `git -C "$MAIN_WORKTREE" branch -d "$BRANCH"`. Escalate to `--force` or `-D` only when the user confirms discarding work, and keep using `git -C "$MAIN_WORKTREE"` because `cd` does not persist between tool calls. Not in a worktree: `git checkout main && git pull`.

## Report

PR URL, assignees and labels, CI state, review threads still needing the user, cleanup state. Ask the user when a step cannot be resolved.
