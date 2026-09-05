---
name: resolve-review-comments
description: >-
  Collect PR review comments and unresolved threads, apply minimal fixes, resolve the addressed
  threads, and confirm CI is green. Use when asked to respond to review feedback or レビューコメント.
---

# Resolve Review Comments

## Goals

- **Gather** PR **review comments/threads** and fix what you can with minimal changes
- **Resolve** review threads that have been addressed so there are no unresolved threads left
- Confirm **CI is green** after your changes

## Prerequisites

- The `gh` CLI is available
- You know the PR number
- The default branch may not be `main`; confirm with `gh repo view`

## Workflow

### 1) Collect PR comments and review bodies

```bash
PR=<number>
gh pr view "$PR" --json url,title,comments,reviews --jq '{url,title,commentsCount:(.comments|length),reviewsCount:(.reviews|length)}'
gh pr view "$PR" --comments
```

### 2) List unresolved review threads (GraphQL)

```bash
OWNER="$(gh repo view --json owner --jq .owner.login)"
NAME="$(gh repo view --json name --jq .name)"
PR=<number>

gh api graphql -f query='
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      reviewThreads(first:100){
        nodes{
          id
          isResolved
          isOutdated
          comments(first:10){nodes{author{login} bodyText createdAt}}
        }
      }
    }
  }
}' -F owner="$OWNER" -F name="$NAME" -F number="$PR" \
--jq '.data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved==false)
  | {id,isOutdated,authors:(.comments.nodes|map(.author.login)|unique),snippet:(.comments.nodes[0].bodyText|tostring|.[0:140])}'
```

### 3) How to respond (minimal fixes)

- **Fix now**: Clear bugs, typos, inconsistent config, things you can lock down with tests
- **Defer**: Design decisions, unclear requirements, large blast radius (needs user confirmation)

After fixing, run the project's own checks for what you touched (the `justfile`, `package.json` scripts, or CI workflow show the real commands, including any environment flags CI sets).

### 4) Post a summary comment on the PR (optional but recommended)

```bash
PR=<number>
gh pr comment "$PR" --body 'Addressed: <bullet summary> / Related commits: <short SHA>'
```

### 5) Resolve threads that are done

Resolve is per thread. Use the `id` from the unresolved list as-is.

```bash
THREAD_ID='PRRT_xxx'
gh api graphql -f query='mutation($thread:ID!){
  resolveReviewThread(input:{threadId:$thread}){ thread{id isResolved} }
}' -F thread="$THREAD_ID" --jq '.data.resolveReviewThread.thread'
```

If there are several, repeat the above (or loop in the shell).

### 6) Confirm there are zero unresolved threads

```bash
OWNER="$(gh repo view --json owner --jq .owner.login)"
NAME="$(gh repo view --json name --jq .name)"
PR=<number>

gh api graphql -f query='
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      reviewThreads(first:100){ nodes{ isResolved } }
    }
  }
}' -F owner="$OWNER" -F name="$NAME" -F number="$PR" \
--jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)] | length'
```

### 7) Check CI

```bash
PR=<number>
gh pr checks "$PR"
gh pr checks "$PR" --watch --interval 25
```

## Notes

- `gh pr view --comments` shows PR issue comments. **Resolving review threads uses GraphQL**.
- If `reviewThreads(first:100)` is not enough, you need pagination (100 is usually enough).
- For failure logs use `gh run view <run-id> --log-failed`, then fix the root cause with minimal changes.
