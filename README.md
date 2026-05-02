# dotagents

このリポジトリは **グローバルな agent 設定**（skills / rules / commands）の **SSoT (Single Source of Truth)** です。

## 前提条件

- [just](https://github.com/casey/just)（例: `brew install just`）
- [Bun](https://bun.sh)（formatter / linter / git hooks 用）

## リポジトリ構成（概要）

| パス        | 内容                                                                                                                                     |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `skills/`   | エージェントスキル（SSoT）                                                                                                               |
| `rules/`    | ルール（`.mdc` など）                                                                                                                    |
| `commands/` | Cursor / エージェント向けコマンド定義                                                                                                    |
| `scripts/`  | リンク・同期・検証シェル                                                                                                                 |
| `justfile`  | 上記スクリプトと開発タスクのエントリポイント                                                                                             |
| `.codex/`   | （任意）Codex 用の共有ベース設定。`config.toml` はパス依存を除いた最小構成なので、ローカルの `~/.codex/config.toml` とマージして使う想定 |

## 設計

- **グローバル**: `~/.agents` にこのrepoの `skills/` `rules/` `commands/` を symlink（SSoT）
- **プロジェクト固有**: `<project>/.agents` はプロジェクト内で管理（ここは自由に追加/上書き）
- **各エージェント**: `<project>/.cursor/.codex/.claude` は `<project>/.agents` を参照するように symlink

## 使い方

タスクランナーは **just** です。レシピ一覧はリポジトリルートで `just`（引数なし）を実行してください。

### symlink（希望の形：コピーせず参照）

- **グローバル**（このrepo → `~/.agents`）:

```bash
just link-global
```

- **Codex 固有**（`~/.codex/commands` を削除し、`~/.codex/prompts` を `~/.agents/commands` に symlink）:

```bash
just link-codex-prompts
```

- **プロジェクト**（`<project>/.agents` を起点に `.cursor/.codex/.claude` を接続）:

```bash
just link-project /path/to/your-project
```

- このとき、デフォルトで `~/.agents/{skills,commands,rules}` の中身を `<project>/.agents/{...}` に「足りない分だけ」symlink で取り込みます（**ローカルが優先**）。

### 同期（コピー）

※ symlink の運用が基本ですが、`<project>/.agents` へ **コピー** したい場合は次のいずれかです。

```bash
just install /path/to/your-project
# または
./scripts/sync-agents.sh --target /path/to/your-project
```

### 検証

```bash
just verify-project /path/to/your-project
```

## 開発（formatter / linter / hooks）

```bash
bun install
just prepare
just format
just lint
just check
```

## 仕様

- `.agents/` は **生成物** として扱います（手編集しない想定）。
- 同期は **片方向**（dotagents → target）です。
- 同期先でソース側に存在しないファイルは削除しません（安全側）。必要なら `--delete` を使ってください。
