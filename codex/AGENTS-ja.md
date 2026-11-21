# グローバル指示

## ルール

- **Skill**: 専門知識が必要なタスクでは、作業開始前に該当skill直下の`SKILL.md`（例: `skills/<name>/SKILL.md`）を読み、手順と制約をそのまま適用する。使用を宣言するだけで終わらせない。
- **Subagent**: 各spawnは空のcontextから始まり、時間とtokenがかかる。次のどれかに当たるときだけ使う。
  - 互いに独立した作業を並列に進める。
  - test・lint・CIのlogや大量のdocumentation・web pageなど、長い出力をmain threadに入れない。
  - 実装を見ていない立場でreviewする。
  - 往復の多い作業、数回のtool呼び出しで終わる変更、待ち時間が問題になる作業はmain threadで行う。
  - 委任promptは自己完結させ、目的、作業directory、対象file・command、変更可否、完了条件、返す内容を含める。
  - 利用中のhostに定義があるagentだけを使う。
    - `light-worker`: format、lint、type check、test、buildを実行して結果だけ返す。直すのは機械的な失敗だけ。
      - spawnするときは`fork_turns="none"`を既定とし、直近のcontextが不可欠な場合に限り必要最小限の正整数を使う。`fork_turns="all"`は使わない。
    - `docs-researcher`: 外部library・CLIの公式documentationで、API、既定値、version差分を確認する。
    - `researcher`: 一次資料、repository、dataなど、独立した調査laneを読み取り専用で担当する。
    - `impl-worker`: 対象file、挙動、完了条件が決まっている実装を担当する。
    - `pr-runner`: PRの作成・更新、CIの監視、review commentへの対応を担当する。
    - `web-operator`（Claude Code）: ログイン済みbrowserでNotion、Slack、X、社内SaaSのページを取得し、要点だけ返す。
    - `architect`、`reviewer`、`evidence-analyst`、`evidence-auditor`（Codex）: 設計判断、独立したcode review、根拠の分析と監査を担当する。

## 開発スタイル

TDD（探索 → Red → Green → Refactoring）で開発する。
KPIやcoverage目標が与えられた場合は、達成するまで反復する。
曖昧な指示は質問して明確にする。

- documentationや指示fileにある現状説明・実装慣例が既存codeと食い違う場合は、関連codeとtestを確認し、既存codeで一貫して使われている慣例に従う。食い違いだけを根拠に、動いている既存codeをdocumentationに合わせて書き換えない。
- 明示された新しい要件・移行方針・security制約は、既存codeと異なっていても優先する。どちらが古いか判断できず、対応が大きく変わる場合だけ確認する。見つけた食い違いと採用した判断は、最終回答ですべて簡潔に報告する。

### Git branch

- branch名に`codex/`などのagent名やtool名をprefixとして付けない。
- repositoryに既存のbranch命名規則がある場合は、それに従う。
- 規則がない場合は、Git Flowの簡潔な命名を使用する: featureは`feature/<short-kebab-case-name>`、通常のfixは`fix/<short-kebab-case-name>`、release準備は`release/<version-or-name>`、緊急のproduction fixは`hotfix/<short-kebab-case-name>`。
- repositoryに既存のlong-lived branchがある場合はそれを再利用し、既存運用にない`develop`などのbranchを、ユーザーの明示的な依頼なしに追加しない。

### Git worktree

- agent自身がworktreeを作る場合は`git wt --basedir=.worktrees --nocd <branch>`を使い、`<project>/.worktrees/`配下へ作る。既にlinked worktree内なら新しく作らない。

### コード設計

- 関心を分離する。
- 状態とlogicを分離する。
- 可読性と保守性を優先する。
- contract layer（API・型）を厳密に定義し、implementation layerは再生成可能に保つ。
- 静的に検査できるルールはpromptではなく、対象環境のlinterまたはast-grepで表現する。

### Tool

- Task: Makefileではなく`justfile`を使用する。
- Node.js: Bun、Node.js v24以上を使用する。
- E2E・ローカル開発中のbrowser操作: `chrome-devtools`ではなく`playwright`を使用する。
  - browserは既定でheadlessで起動する（`playwright-cli open`に`--headed`を付けない）。手動loginなどuserが画面を見る・操作する必要があるときだけ`--headed`を使う。Computer Use / `orca computer`もwindowを前面に出すので、browserの操作には使わない。
- Python: `uv`を使用する。
