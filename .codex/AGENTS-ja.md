# Codex Global Instructions

## Rules

- 積極的にskill, subagentを使用しmain threadのcontextをcleanに保ってください
  - **Skill**: 専門知識が必要なタスク → 作業開始前に該当スキル直下の `SKILL.md`（例: `skills/<name>/SKILL.md`）を読み、手順/制約をそのまま適用する。宣言だけで終わらせない。
  - **Subagent**: 独立コンテキストが有効なタスク（リファクタリング・レビュー・広範囲探索など）、または並列実行したい場合に委任する。
  - [browser_debugger](./agents/browser_debugger.toml): UIやweb appのdebugを行う専用のsubagent
  - [docs_researcher](./agents/docs_researcher.toml): 公式ドキュメント、API、フレームワーク情報を一次情報ベースで収集する専用のsubagent
  - [light_worker](./agents/light_worker.toml): format, lint, type checkなどの軽いタスクに加え、PR作成・更新などの軽量なPRワークフローを実行する専用subagent
  - [qwen_worker](./agents/qwen_worker.toml): lmstudioでlocal llmのqwen3.6を使用する専用のsubagent
  - ※ 両者は併用可。Skill の知識を Subagent に渡して実行することもある。
  - ※ 小さいタスクで該当する Skill/Subagent がない場合は、通常フローで進める。

## 開発スタイル

TDD で開発する（探索 → Red → Green → Refactoring）。
KPI やカバレッジ目標が与えられたら、達成するまで試行する。
不明瞭な指示は質問して明確にする。

### コード設計

- 関心の分離を保つ
- 状態とロジックを分離する
- 可読性と保守性を重視する
- コントラクト層（API/型）を厳密に定義し、実装層は再生成可能に保つ
- 静的検査可能なルールはプロンプトではなく、その環境の linter か ast-grep で記述する

### ツール

- Search: Use `rg` (ripgrep) instead of `grep`
- Find: Use `fd` instead of `find`
- JSON: Use `jq` for JSON processing
- Shell: Fish shell is the primary shell
  - Task: `justfile` instead of Makefile
- Node.js: bun, v24+
- E2E: `playwright` instead of `chrome-devtools`
- Python: `uv`
