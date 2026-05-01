# dotagents

このリポジトリは **グローバルな agent 設定**（skills / rules / commands）の **SSoT (Single Source of Truth)** です。

## 設計

- **グローバル**: `~/.agents` にこのrepoの `skills/` `rules/` `commands/` を symlink（SSoT）
- **プロジェクト固有**: `<project>/.agents` はプロジェクト内で管理（ここは自由に追加/上書き）
- **各エージェント**: `<project>/.cursor/.codex/.claude` は `<project>/.agents` を参照するように symlink

## 使い方

### symlink（希望の形：コピーせず参照）

- **グローバル**（このrepo → `~/.agents`）:

```bash
make link-global
```

- **プロジェクト**（`<project>/.agents` を起点に `.cursor/.codex/.claude` を接続）:

```bash
make link-project TARGET=/path/to/your-project
```

- このとき、デフォルトで `~/.agents/{skills,commands,rules}` の中身を `<project>/.agents/{...}` に「足りない分だけ」symlink で取り込みます（**ローカルが優先**）。

### 同期（推奨）

※ symlink の運用が基本ですが、コピー同期したい場合は `rsync` でも可能です。

```bash
./scripts/sync-agents.sh --target /path/to/your-project
```

### 検証

```bash
make verify-project TARGET=/path/to/your-project
```

## 開発（formatter / linter / hooks）

```bash
bun install
bun run prepare
bun run format
bun run lint
bun run check
```

## 仕様

- `.agents/` は **生成物** として扱います（手編集しない想定）。
- 同期は **片方向**（dotagents → target）です。
- 同期先でソース側に存在しないファイルは削除しません（安全側）。必要なら `--delete` を使ってください。
