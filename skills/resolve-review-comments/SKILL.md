---
name: resolve-review-comments
description: Collects PR review comments and unresolved threads, applies minimal fixes, resolves addressed review threads, and verifies CI is green. Use when the user says "review comment", "レビューコメント", "resolve", or asks to respond to PR review feedback.
---

# Resolve Review Comments

## Goals

- **Gather** PR **review comments/threads** and fix what you can with minimal changes
- **Resolve** review threads that have been addressed so there are no unresolved threads left
- Confirm **CI is green** after your changes

## Prerequisites

- The `gh` CLI is available
- You know the PR number (e.g. `171`)
- This repository’s default branch may not be `main` (confirm with `gh repo view`)

## Workflow

### 1) Collect PR comments and review bodies

```bash
PR=171
gh pr view "$PR" --json url,title,comments,reviews --jq '{url,title,commentsCount:(.comments|length),reviewsCount:(.reviews|length)}'
gh pr view "$PR" --comments
```

### 2) List unresolved review threads (GraphQL)

Get `owner/name` from `gh repo view --json nameWithOwner --jq .nameWithOwner`.

```bash
OWNER=ango-ya
NAME=crescent-uniswapx-quoter
PR=171

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

After fixing, run minimal local checks:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test
```

(If CI uses flags like `ENABLE_APP_CONFIG_TESTS=1`, run the same locally.)

### 4) Post a summary comment on the PR (optional but recommended)

```bash
PR=171
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
OWNER=ango-ya
NAME=crescent-uniswapx-quoter
PR=171

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
PR=171
gh pr checks "$PR"
gh pr checks "$PR" --watch --interval 25
```

## Notes

- `gh pr view --comments` shows PR issue comments. **Resolving review threads uses GraphQL**.
- If `reviewThreads(first:100)` is not enough, you need pagination (100 is usually enough).
- For failure logs use `gh run view <run-id> --log-failed`, then fix the root cause with minimal changes.
