# グローバル指示

## ルール

- skillとsubagentを積極的に使い、main threadのcontextをcleanに保つ。
  - **Skill**: 専門知識が必要なタスクでは、作業開始前に該当skill直下の`SKILL.md`（例: `skills/<name>/SKILL.md`）を読み、手順と制約をそのまま適用する。使用を宣言するだけで終わらせない。
  - **Subagent**: 独立したcontextや並列実行が有効で、利用中のhostに適切なsubagentがある場合に委任する。
    - `architect`: 設計、trade-off、責務境界、実装計画を整理する。
    - `browser-debugger`: browserで問題を再現し、console、network、DOM、screenshotから証拠を集める。
    - `docs-researcher`: 公式documentationからAPI、既定値、version差分を確認する。
    - `light-worker`: formatting、lint、type check、testなどの機械的な検証を担当する。
      - `light-worker`をspawnするときは`fork_turns="none"`を既定とし、必要な直近contextだけが不可欠な場合に限り必要最小限の正整数を使う。`fork_turns="all"`は使わない。
      - 委任promptを自己完結させ、目的、作業directory、対象file・command、変更可否、完了条件を含める。
    - `web-operator`: ログイン済みbrowser経由でNotion、Slack、X、社内SaaSのページを取得し、要点のみ返す。

## 開発スタイル

- テストは「仕様として固定する価値がある振る舞い」に対して書く。外部から観測できる振る舞いの変更と、バグ修正がこれにあたる。バグ修正では再現する失敗テストを先に書き、実際に落ちることを確認してから直す。
- 次のものにはテストを書かない: 設定・ドキュメント・依存更新、型やlinterが静的に保証できる範囲、一度きりの調査スクリプト、仕様として固定する意図のない実装詳細。
- 仕様が固まっていない探索段階と、機械的で自明な変更では、Red → Greenの順序に固執しない。先に動かし、仕様として残す価値が決まった時点でテストにする。
- KPIやcoverage目標が与えられた場合は、達成するまで反復する。
- 曖昧な指示は質問して明確にする。

### Git branch

- branch名に`codex/`などのagent名やtool名をprefixとして付けない。
- repositoryに既存のbranch命名規則がある場合は、それに従う。
- 規則がない場合は、Git Flowの簡潔な命名を使用する: featureは`feature/<short-kebab-case-name>`、通常のfixは`fix/<short-kebab-case-name>`、release準備は`release/<version-or-name>`、緊急のproduction fixは`hotfix/<short-kebab-case-name>`。
- repositoryに既存のlong-lived branchがある場合はそれを再利用し、既存運用にない`develop`などのbranchを、ユーザーの明示的な依頼なしに追加しない。

### Git worktree

- worktreeを作る前に、`git rev-parse --path-format=absolute --git-dir`と`git rev-parse --path-format=absolute --git-common-dir`を比較する。
- pathが異なる場合、現在のディレクトリは既にlinked worktreeなのでそこに留まり、ユーザーがworktreeのlifecycle操作を明示的に依頼していない限り新しく作らない。
- worktreeの作成はshellに落とさず、host自身のworktree機能を使う（Claude Codeならworktree機能と`EnterWorktree`/`ExitWorktree`）。repositoryの`.worktreeinclude`が処理されるのはその経路だけで、新しいworktreeに必要なgitignore済みファイルがコピーされる。shellから`git worktree add`した場合は何もコピーされない。
- shellから扱う必要がある場合は素の`git worktree add`を使い、削除は`git worktree remove`のあとに`git branch -d`を実行する。どちらも作業の破棄を既に拒否する: `remove`はdirtyなworktreeで停止し、`branch -d`は未マージbranchで停止する。`--force`や`-D`への昇格はユーザーが破棄を確認したあとだけ。
- `node_modules`などの依存ディレクトリをworktree間でコピーしない。worktreeごとにinstallして、それぞれ独立して解決させる。

### Pull Request

- repositoryにPR templateがある場合は、その見出しと項目構成をそのまま守り、項目を削らない。該当しない項目は削除せず、該当しない理由を明記する。
- templateが無い場合は「背景」「変更内容」「変更理由」「検証結果」「レビュー時の注目点」を見出しとして立てる。
- 本文はPRに含まれる全commitを対象に書く。最新の変更だけを説明しない。
- レビュアーの負担を減らすため、視覚的に読める形にする。比較・影響範囲は表、処理の流れや構成の変化はMermaid図、UI変更は前後のscreenshotを使う。該当箇所は`file.ts:42`形式で示す。
- 検証結果は実行したcommandと実際の出力で示す。「テスト済み」とだけ書かない。未検証の項目は未検証と明記する。
- 簡潔さを目的に情報を削らない。避けるのは冗長な重複だけ。

### コード設計

- 関心を分離する。
- 状態とlogicを分離する。
- 可読性と保守性を優先する。
- contract layer（API・型）を厳密に定義し、implementation layerは再生成可能に保つ。
- 静的に検査できるルールはpromptではなく、対象環境のlinterまたはast-grepで表現する。

### Tool

- Search: `grep`ではなく`rg`（ripgrep）を使用する。
- Find: `find`ではなく`fd`を使用する。
- JSON: JSON処理には`jq`を使用する。
- Shell: Fish shellを優先する。
- Task: Makefileではなく`justfile`を使用する。
- Node.js: Bun、Node.js v24以上を使用する。
- E2E・ローカル開発中のbrowser操作: `chrome-devtools`ではなく`playwright`を使用する。
- 認証付きweb: ログインが必要なページは`web-operator`に委譲し、経路をMCP → CLI → 認証済みbrowserの順に選ぶ。browser profileの対応表は`~/.claude/browser-profiles.json`。`playwright`は新規profileでsessionを持たないため、保存済みのstorage stateが無い限り認証が必要な外部serviceには使わない。
- 対話login: `ntn login`のようなbrowser往復を要するloginをagentから試さない。認証情報が無い場合は再試行せず、認証済みbrowser経路に切り替える。
- Python: `uv`を使用する。
