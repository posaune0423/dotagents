# dotagents

このリポジトリは **グローバルな agent 設定**（skills / rules / commands）の **SSoT (Single Source of Truth)** です。

## 環境構築（基本は Nix）

[Nix](https://nixos.org/download/)（flakes 有効）だけ用意すれば、CLI ツールは [flake.nix](flake.nix) の devShell から揃います（**just / Bun / git / lefthook / shellcheck / shfmt**）。

### 手順

1. リポジトリのルートに移動する。
2. **初回のみ**、依存と Git hooks を入れる（どちらか一方でよい）:
   - `nix run .#setup` — `bun install` のみ（インストール完了時に `prepare` が走り lefthook が入る）。
   - または `nix develop` でシェルに入ってから `just bootstrap`（同じく `bun install`）。
3. 以降の作業は `nix develop` のシェル内で `just` / `bun` を使う。

**PATH の注意:** devShell は flake の CLI を PATH の先頭に載せます。ワンショットで `nix develop -c bash -lc '…'` のように **ログインシェル（`-l`）** を使うと、`~/.bash_profile` などが PATH を組み替え、**ホストのツールが先に解決される**ことがあります。スクリプトや CI では `bash -c`（`-l` なし）を使ってください。direnv や対話的な `nix develop` では通常この問題は出ません。

**direnv** を使う場合は [`.envrc`](.envrc) により同じ devShell が自動で載ります。初回だけ `direnv allow` が必要です。

### Nix を使わない場合

- [just](https://github.com/casey/just) と [Bun](https://bun.sh) をそれぞれ [公式の手順](https://github.com/casey/just#installation)で入れ、ルートで `bun install` を実行してください（`prepare` で lefthook が入ります）。

## リポジトリ構成（概要）

| パス        | 内容                                                                                                                                     |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `skills/`   | エージェントスキル（SSoT）                                                                                                               |
| `rules/`    | ルール（`.mdc` など）                                                                                                                    |
| `commands/` | Cursor / エージェント向けコマンド定義                                                                                                    |
| `scripts/`  | リンク・同期・検証シェル                                                                                                                 |
| `justfile`  | 上記スクリプトと開発タスクのエントリポイント                                                                                             |
| `.envrc`    | （任意）[direnv](https://direnv.net/) 用。`use flake` で devShell を自動適用                                                             |
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

devShell に入った状態（`nix develop` または direnv）で次を実行します。

```bash
just format
just lint
just check
```

ワンショットで devShell 経由だけ呼ぶ場合の例:

```bash
nix develop -c just format
nix develop -c just lint
nix develop -c just check
```

## 仕様

- `.agents/` は **生成物** として扱います（手編集しない想定）。
- 同期は **片方向**（dotagents → target）です。
- 同期先でソース側に存在しないファイルは削除しません（安全側）。必要なら `--delete` を使ってください。
