# グローバル指示

## 進め方

- 完了条件は「実装し、動かし、結果を確認し、壊れたものを直す」まで。最初の実装で止めてレビューを待たない。途中で止めるべき場合はユーザーがそう指示する。
- 曖昧な点は、可逆な作業なら仮定を明示して進める。質問は、解釈によって成果物が大きく変わる点か、破壊的・外部公開・課金を伴う操作の前に限り、質問中も依存しない作業は続ける。
- ローカルのtest・lint・format・typecheck・build、fileの読み取り、`git status`・`git diff`・`git log`は、都度の承認なしに実行してよい。
- 独立したtool call（検索、読み取り、checkの実行）は1つのmessageにまとめて並列に出す。依存関係のあるものだけ順に実行する。
- 既存fileは該当箇所の差分編集で変更し、file全体を書き直さない。

## Skillとsubagent

- 専門知識が必要なタスクでは、作業開始前に該当skillの`SKILL.md`を読み、手順と制約をそのまま適用する。使用を宣言するだけで終わらせない。
- 独立したcontextや並列実行が有効なときだけsubagentに委任する。委任promptは自己完結させ、目的、作業directory、対象file・command、変更可否、完了条件を含める。
- `light-worker`をspawnするときは`fork_turns="none"`を既定とし、必要な直近contextだけが不可欠な場合に限り必要最小限の正整数を使う。`fork_turns="all"`は使わない。

## 開発スタイル

- 挙動を変えるcodeはTDD（探索 → Red → Green → Refactoring）で進める。設定file、docs、使い捨てscript、生成codeは対象外。
- KPIやcoverage目標が与えられた場合は、達成するまで反復する。

### Git branch

- branch名に`codex/`などのagent名やtool名をprefixとして付けない。
- repositoryに既存のbranch命名規則がある場合は、それに従う。
- 規則がない場合は、Git Flowの簡潔な命名を使用する: featureは`feature/<short-kebab-case-name>`、通常のfixは`fix/<short-kebab-case-name>`、release準備は`release/<version-or-name>`、緊急のproduction fixは`hotfix/<short-kebab-case-name>`。
- repositoryに既存のlong-lived branchがある場合はそれを再利用し、既存運用にない`develop`などのbranchを、ユーザーの明示的な依頼なしに追加しない。

### Git worktree

- agent自身がworktreeを作る場合は`git wt --basedir=.worktrees --nocd <branch>`を使い、`<project>/.worktrees/`配下へ作る。既にlinked worktree内なら新しく作らない。

### コード設計

- 状態とlogicを分離する。
- contract layer（API・型）を厳密に定義し、implementation layerは再生成可能に保つ。
- 静的に検査できるルールはpromptではなく、対象環境のlinterまたはast-grepで表現する。

### Tool

- Task: Makefileではなく`justfile`を使用する。
- Node.js: Bun、Node.js v24以上を使用する。
- E2E・ローカル開発中のbrowser操作: `chrome-devtools`ではなく`playwright`を使用する。
- Python: `uv`を使用する。
