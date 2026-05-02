---
name: resolve-review-comments
description: Collects PR review comments and unresolved threads, applies minimal fixes, resolves addressed review threads, and verifies CI is green. Use when the user says "review comment", "レビューコメント", "resolve", or asks to respond to PR review feedback.
---

# Resolve Review Comments

## 目的

- PR の **レビューコメント/スレッドを回収**し、対応できるものを最小修正で直す
- 対応済みの **Review thread を Resolve** して未解決をゼロにする
- 変更後に **CI が green** であることを確認する

## 前提

- `gh` CLI が利用できる
- PR 番号（例: `171`）が分かっている
- このリポジトリのデフォルトブランチが `main` とは限らない（`gh repo view` で確認する）

## 手順

### 1) PR のコメントとレビュー本文を回収する

```bash
PR=171
gh pr view "$PR" --json url,title,comments,reviews --jq '{url,title,commentsCount:(.comments|length),reviewsCount:(.reviews|length)}'
gh pr view "$PR" --comments
```

### 2) 未解決の Review thread を列挙する（GraphQL）

`owner/name` は `gh repo view --json nameWithOwner --jq .nameWithOwner` で確認する。

```bash
OWNER=posaune0423
NAME=dotagents
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

### 3) 対応方針（最小修正）

- **即対応する**: 明確なバグ、typo、設定の矛盾、テスト追加で仕様固定できるもの
- **保留する**: 設計判断が必要、要件が不明、影響範囲が大きい（ユーザーに確認が必要）

対応したら、ローカルで最低限の検証を回す:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test
```

（CI が `ENABLE_APP_CONFIG_TESTS=1` のようなフラグを使う場合は、ローカルでも合わせて実行する）

### 4) 対応内容を PR にコメントする（任意だが推奨）

```bash
PR=171
gh pr comment "$PR" --body '対応しました: <要点を箇条書き> / 関連コミット: <短い SHA>'
```

### 5) 対応済み thread を Resolve する

Resolve は thread 単位で行う。未解決一覧の `id` をそのまま使う。

```bash
THREAD_ID='PRRT_xxx'
gh api graphql -f query='mutation($thread:ID!){
  resolveReviewThread(input:{threadId:$thread}){ thread{id isResolved} }
}' -F thread="$THREAD_ID" --jq '.data.resolveReviewThread.thread'
```

複数ある場合は、上を繰り返す（またはシェルで連結して順番に実行する）。

### 6) 未解決 thread が 0 件になったことを確認する

```bash
OWNER=posaune0423
NAME=dotagents
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

### 7) CI を確認する

```bash
PR=171
gh pr checks "$PR"
gh pr checks "$PR" --watch --interval 25
```

## 注意点

- `gh pr view --comments` は PR の issue comments を表示する。**review threads の resolve は GraphQL** で行う。
- `reviewThreads(first:100)` で足りない場合は pagination 対応が必要（通常は 100 で足りる前提）。
- 失敗ログが必要な場合は `gh run view <run-id> --log-failed` を使い、根本原因を最小修正で潰す。
