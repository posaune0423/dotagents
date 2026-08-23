# グローバル指示

## ルール

- skillとsubagentを積極的に使い、main threadのcontextをcleanに保つ。
  - **Skill**: 専門知識が必要なタスクでは、作業開始前に該当skill直下の`SKILL.md`（例: `skills/<name>/SKILL.md`）を読み、手順と制約をそのまま適用する。使用を宣言するだけで終わらせない。
  - **Subagent**: 独立したcontextや並列実行が有効で、利用中のhostに適切なsubagentがある場合に委任する。
    - `architect`: 設計、trade-off、責務境界、実装計画を整理する。
    - `browser-debugger`: browserで問題を再現し、console、network、DOM、screenshotから証拠を集める。
    - `docs-researcher`: 公式documentationからAPI、既定値、version差分を確認する。
    - `light-worker`: formatting、lint、type check、testなどの機械的な検証を担当する。
    - `web-operator`: ログイン済みbrowser経由でNotion、Slack、X、社内SaaSのページを取得し、要点のみ返す。

## 開発スタイル

TDD（探索 → Red → Green → Refactoring）で開発する。
KPIやcoverage目標が与えられた場合は、達成するまで反復する。
曖昧な指示は質問して明確にする。

### Git branch

- branch名に`codex/`などのagent名やtool名をprefixとして付けない。
- repositoryに既存のbranch命名規則がある場合は、それに従う。
- 規則がない場合は、Git Flowの簡潔な命名を使用する: featureは`feature/<short-kebab-case-name>`、通常のfixは`fix/<short-kebab-case-name>`、release準備は`release/<version-or-name>`、緊急のproduction fixは`hotfix/<short-kebab-case-name>`。
- repositoryに既存のlong-lived branchがある場合はそれを再利用し、既存運用にない`develop`などのbranchを、ユーザーの明示的な依頼なしに追加しない。

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
