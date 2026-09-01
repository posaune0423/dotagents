---
name: myfans-sub-issue-progress-watch
description: getozinc/myfans で自分にassignされたissueの親issueを辿り、DES・BE・FEの兄弟sub-issueの進捗をbranch・PR・commitまで確認して、FEが着手判断できる形で報告する
---

`getozinc/myfans` で `posaune0423` にassignされているopen issueについて、その**親issue配下にいる他の作業者のsub-issueの進捗**を調べ、日本語で報告してください。

読み手はFrontend Engineerで、目的は自分のスケジュールを立てることです。知りたいのは次の2点に集約されます。

- デザイン（`[DES]`）が確定しているか。まだならどこで止まっているか
- FEが着手できるところまでBEの実装が進んでいるか。**stateだけでなく、関連branchのcommitを見て実際にどこまで実装されているか**

## 絶対の制約（read-only）

- **GitHubへの書き込みを一切しないでください。** comment投稿、reaction、label・assignee・state・milestoneの変更、review、thread resolve、branch・PRの作成、push、merge、close はすべて禁止です。他の人のissue・PRには特に触れないでください。
- 使うのは `gh api` / `gh api graphql` / `gh issue list` / `gh pr list` / `gh search` の**読み取り操作だけ**です。
- 書き込みが許されるのは、後述するstate directory配下のファイルだけです。
- repositoryのlocal cloneは不要です。`git clone` / `git fetch` / worktree操作はしないでください。commit確認はGitHub APIで行います。

## 0. Preflight

1. `gh auth status` が成功し、`gh api user --jq .login` が `posaune0423` を返すことを確認してください。異なる場合は調査せず、その事実だけを報告して終了してください。
2. state directory `/Users/asumayamada/.local/state/dotagents/myfans-sub-issue-progress-watch/` を作成し、`latest.json` があれば読み込んでください。これが「前回の状態」になります。無い場合は初回実行として扱い、差分セクションには「初回実行のため差分なし」と書いてください。
3. issue番号はすべて `getozinc/myfans` 側の番号です。`getozinc/myfans-web` のPR番号と混同しないでください。報告に書くときは `getozinc/myfans#21590` の形か、フルURLにしてください。

## 1. 自分のissueと親issueの特定

```bash
gh issue list --repo getozinc/myfans --assignee posaune0423 --state open \
  --limit 50 --json number,title,url,updatedAt
```

各issueについて親を辿ります。

```bash
gh api graphql -f query='
query($n: Int!) {
  repository(owner: "getozinc", name: "myfans") {
    issue(number: $n) {
      number title url state
      parent { number title state url }
    }
  }
}' -F n=21590
```

- 親が無いissueは「親issueなし」として1行だけ触れ、以降の調査対象から外してください。
- 同じ親を持つ自分のissueが複数ある場合、親は1回だけ調査してください。

## 2. 兄弟sub-issueの一覧

親issueの `subIssues` を取得します。

```bash
gh api graphql -f query='
query($n: Int!) {
  repository(owner: "getozinc", name: "myfans") {
    issue(number: $n) {
      number title state url
      subIssues(first: 100) {
        nodes {
          number title state url createdAt updatedAt closedAt
          assignees(first: 5) { nodes { login } }
          labels(first: 10) { nodes { name } }
        }
      }
    }
  }
}' -F n=19850
```

titleの接頭辞で役割を分類してください。

| 接頭辞                                         | 役割             |
| ---------------------------------------------- | ---------------- |
| `[DES]`                                        | デザイン         |
| `[BE]`                                         | Backend          |
| `[FE]`                                         | Frontend         |
| `[QA]`                                         | QA               |
| それ以外（`仕様書作成`、`Sub Issue作成` など） | 仕様・準備タスク |

- 自分がassigneeのsub-issueは「自分の担当」として区別し、進捗調査の主対象は**他の作業者のsub-issue**にしてください。
- `Sub Issue作成` / `アサイン` / `仕様レビュー` のような管理用sub-issueは、closedなら1行に集約してよいです。openのまま残っている場合は「準備が止まっている可能性」として明示してください。

## 3. デザイン（`[DES]`）の進捗

`[DES]` のsub-issueごとに次を確認してください。

1. state（OPEN / CLOSED）、assignee、`updatedAt`
2. 直近のcommentを最大5件読み、確定・差し戻し・保留のどれなのかを判断する

```bash
gh api graphql -f query='
query($n: Int!) {
  repository(owner: "getozinc", name: "myfans") {
    issue(number: $n) {
      comments(last: 5) { nodes { author { login } createdAt body } }
    }
  }
}' -F n=21093
```

3. commentやissue bodyに Figma のURL（`figma.com/design/...` / `figma.com/file/...`）があれば抽出し、報告に載せてください。**FigmaのAPIやMCPで中身を見に行かないでください。**URLの提示だけで十分です。
4. 判定は次の3値にしてください。
   - `確定`: CLOSED、またはcommentで確定が明言されている
   - `作業中`: OPEN かつ 7日以内に更新がある
   - `停滞`: OPEN かつ 7日以上更新が無い（最終更新からの日数を書く）

commentの本文をそのまま長く引用しないでください。要約1行にしてください。

## 4. BE（`[BE]`）の実装状況 — branchとcommitまで見る

これがこのタスクの中心です。stateだけを見て「未着手」と書かないでください。

### 4.0 深掘りする対象を絞る

branch・commitまで見るのは次のBE sub-issueだけにしてください。それ以外のCLOSEDなBE sub-issueは「完了」の1行と、分かる範囲のmerge済みPR番号だけで済ませてください。API呼び出しを無駄に増やさないためです。

- state が OPEN のもの
- 直近7日以内にCLOSEDになったもの
- 自分のissueがFEとして直接依存していると読み取れるもの

### 4.1 branch一覧を1回だけ取得してcacheする

```bash
gh api --paginate "repos/getozinc/myfans/branches?per_page=100" --jq '.[].name'
```

結果はstate directoryの `branches-cache.json` に保存し、その実行中は再取得しないでください。

### 4.2 sub-issue番号から関連branch・PRを探す

BEのbranchは `feature/issue-<番号>-<要約>` / `feature/<番号>-<要約>` / `fix/issue-<番号>-<要約>` の形が使われています。sub-issue `#N` について、次を上から順に試し、見つかったものをすべて集約してください。

1. **branch名の番号一致**: 4.1のbranch一覧から、正規表現 `(^|[^0-9])N([^0-9]|$)` に一致する名前を拾う
2. **issueのtimelineに紐づくPR**

   ```bash
   gh api graphql -f query='
   query($n: Int!) {
     repository(owner: "getozinc", name: "myfans") {
       issue(number: $n) {
         timelineItems(last: 50, itemTypes: [CROSS_REFERENCED_EVENT, CONNECTED_EVENT]) {
           nodes {
             __typename
             ... on CrossReferencedEvent { source { ... on PullRequest { number title state url headRefName isDraft } } }
             ... on ConnectedEvent { subject { ... on PullRequest { number title state url headRefName isDraft } } }
           }
         }
       }
     }
   }' -F n=21840
   ```

3. **本文・titleでの言及**: `gh search prs --repo getozinc/myfans "<N>" --limit 20 --json number,title,state,url` を使い、明らかに無関係なもの（別機能のPRが偶然同じ数字を含むだけ、など）は捨てる
4. **assigneeのPRから拾う**: sub-issueのassignee `<login>` について
   `gh pr list --repo getozinc/myfans --author <login> --state all --limit 30 --json number,title,state,headRefName,updatedAt,isDraft,url`
   を取り、`headRefName` の番号一致で拾う

1〜4のどれでも何も見つからない場合だけ「branch・PRなし（未着手）」と判定してください。**判定根拠（どの方法で探して見つからなかったか）を1行添えてください。**

### 4.3 見つかったbranchの実装量を確認する

各branchについて、default branch `master` との比較を取ります。

```bash
gh api "repos/getozinc/myfans/compare/master...<branch>" \
  --jq '{ahead: .ahead_by, behind: .behind_by, files: (.files | length),
          commits: [.commits[] | {date: .commit.committer.date,
                                  author: .commit.author.name,
                                  message: (.commit.message | split("\n")[0])}]}'
```

- commit数が多い場合は、**最新5件のheadlineと日付**だけを報告してください。全件列挙しないでください。
- 変更ファイル数と、`.files[].filename` から読み取れる**変更の中心領域**（例: `app/controllers/api/v1/...` / `db/migrate/...` / `spec/...`）を1〜2行で要約してください。migrationがあるか、specがあるかはFEの待ち時間の目安になるので必ず触れてください。
- 最終commit日時からの経過日数を出し、3営業日以上動いていないbranchは `停滞` と明示してください。
- **merge済みPRのbranchは削除されているためcompareが404になります。**この場合はbranchが消えたことを失敗として報告せず、PRのcommitを情報源に切り替えてください。

  ```bash
  gh api "repos/getozinc/myfans/pulls/<PR番号>/commits" \
    --jq '[.[] | {date: .commit.committer.date, author: .commit.author.name,
                  message: (.commit.message | split("\n")[0])}]'
  gh api "repos/getozinc/myfans/pulls/<PR番号>/files?per_page=100" --jq '[.[].filename]'
  ```

- compareもPR経由の取得も両方失敗した場合だけ、そのbranchをskipして理由を書いてください。範囲を広げてlocal cloneを取りに行かないでください。

### 4.4 PRの状態

見つかったPRについて、`state`（OPEN / MERGED / CLOSED）、`isDraft`、`reviewDecision`、最新commit日時を報告してください。

```bash
gh api graphql -f query='
query($n: Int!) {
  repository(owner: "getozinc", name: "myfans") {
    pullRequest(number: $n) {
      number title url state isDraft reviewDecision headRefName mergedAt updatedAt
      commits(last: 1) { totalCount nodes { commit { messageHeadline committedDate } } }
    }
  }
}' -F n=22359
```

MERGEDのPRは「FEが依存できる状態」、OPENでdraftでないものは「レビュー待ち」、draftは「実装中」として扱ってください。

### 4.5 FEが依存するAPIの見え方

BEのbranchに `app/controllers/` 配下の追加・変更や、`docs/` / OpenAPI定義の更新が含まれている場合は、**FEが叩けるendpointが生えたかどうか**を1行で書いてください。ここが読み手の一番の関心です。endpointのpathが変更ファイル名から読み取れる場合は書いてください。読み取れない場合に推測で書かないでください。

## 5. FE（`[FE]`）の兄弟

自分以外の `[FE]` sub-issueがある場合は、state・assignee・関連PR（`getozinc/myfans-web` 側になることが多い）を1行ずつ確認してください。`getozinc/myfans-web` のPRは次で探せます。

```bash
gh pr list --repo getozinc/myfans-web --search "<N>" --state all --limit 10 \
  --json number,title,state,headRefName,updatedAt,url
```

自分の担当分の作業内容をここで設計・提案しないでください。このタスクは進捗の観測だけを行います。

## 6. 前回からの差分

`latest.json` と今回の観測を比較し、**変化があったものだけ**を差分として抽出してください。比較キーは次です。

- sub-issueの `state`、`assignees`、`updatedAt`
- 関連branchの最終commit sha と日時、`ahead_by`
- 関連PRの `state`、`isDraft`、`reviewDecision`、commit数
- 新しく現れたbranch・PR・sub-issue

差分が無い場合は「前回（`<前回実行時刻>`）から変化なし」の1行で済ませてください。**変化が無いのに前回と同じ全文を再掲しないでください。**

## 7. state保存

`/Users/asumayamada/.local/state/dotagents/myfans-sub-issue-progress-watch/` に保存してください。

- `YYYY-MM-DDTHH:MM.json`: 今回の観測結果
- `latest.json`: 今回の結果で上書き
- `branches-cache.json`: 4.1で取得したbranch一覧

`latest.json` には、開始・終了日時、自分のissueと親issueの対応、各sub-issueのnumber・title・state・assignee・updatedAt、関連branchごとの最終commit sha・日時・ahead_by・変更ファイル数、関連PRのnumber・state・isDraft・reviewDecision、失敗した取得とその理由を記録してください。commentの本文やissue bodyの全文、token・credentialは保存しないでください。

`YYYY-MM-DD` のファイルが14日分を超えたら古いものから削除してよいです。それ以外のファイルは削除しないでください。

## 8. 報告フォーマット

日本語で、次の順に出力してください。全体で長くなりすぎないよう、**変化と判断を先に、根拠を後に**置いてください。

### 8.1 冒頭サマリ（最重要）

自分のopen issueごとに1行、次の3値で着手可否を書いてください。

- `着手可`: 依存するデザインが確定していて、依存するBEがmergeまたはレビュー待ちまで進んでいる
- `一部着手可`: 一部だけ揃っている。何が揃って何が足りないかを同じ行に書く
- `待ち`: 依存が揃っていない。**何を待っているか（誰の・どのsub-issue）**を同じ行に書く

判定に使った依存関係が推測を含む場合は断定せず「未確定」と書いてください。

### 8.2 今回の変化

前回から変わった点だけを箇条書きにしてください。1項目1行です。変化が無ければ1行でそう書いてください。

### 8.3 親issueごとの詳細

親issueごとに `###` 小見出しを立て、次を載せてください。

- 親issueのnumber・title・URL
- 役割別の表: `役割 | sub-issue | state | 担当 | 進捗`
- `#### BE実装状況`: sub-issueごとに、branch名、PR、commit数、最新commitのheadlineと日付、変更の中心領域、停滞判定
- `#### デザイン`: 確定 / 作業中 / 停滞、FigmaのURL、最新commentの要約1行

### 8.4 詰まっている点

3営業日以上動いていないsub-issue、assigneeが空のopen sub-issue、openのまま残っている管理用sub-issueを列挙してください。**誰かを責める書き方をせず、事実（最終更新日と経過日数）だけを書いてください。**

### 8.5 取得できなかったもの

APIの失敗、権限不足、判定できなかった対応関係を列挙してください。判定できなかったものを「進捗なし」と書き換えないでください。

## 書き方の制約

- 事実と推測を分けてください。branch・commit・PRから確認できたことは断定してよく、それ以外は「未確定」と明記してください。
- 1項目1行。80文字を超えたら2項目に割ってください。
- diffの中身、コード、commentの本文を長く貼らないでください。
- FE側の実装方針の提案、他の作業者への依頼文、issueへ投稿するcomment案は書かないでください。求められているのは進捗の観測結果だけです。
