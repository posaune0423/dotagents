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

| パス        | 内容                                                                                                                                                                                                        |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `skills/`   | エージェントスキル（SSoT）                                                                                                                                                                                  |
| `rules/`    | ルール（`.mdc` など）                                                                                                                                                                                       |
| `commands/` | Cursor / エージェント向けコマンド定義                                                                                                                                                                       |
| `scripts/`  | リンク・同期・検証シェル                                                                                                                                                                                    |
| `justfile`  | 上記スクリプトと開発タスクのエントリポイント                                                                                                                                                                |
| `.envrc`    | （任意）[direnv](https://direnv.net/) 用。`use flake` で devShell を自動適用                                                                                                                                |
| `.claude/`  | Claude Code 用の共有設定。`CLAUDE.md` / `settings.json` と subagent 定義 `agents/*.md`                                                                                                                      |
| `.codex/`   | （任意）Codex 用の共有ベース設定。subagent は `agents/*.toml` ＋ `config.toml` の `[agents.*]` 登録。`config.toml` はパス依存を除いた最小構成なので、ローカルの `~/.codex/config.toml` とマージして使う想定 |

## 設計

- **グローバル**: `~/.agents` にこのrepoの `skills/` `rules/` `commands/` を symlink（SSoT）
- **プロジェクト固有**: `<project>/.agents` はプロジェクト内で管理（ここは自由に追加/上書き）
- **各エージェント**: `<project>/.cursor/.codex/.claude` は `<project>/.agents` を参照するように symlink
- **Subagent**: 形式がツールごとに異なる（Claude Code は Markdown `.claude/agents/*.md`、Codex は TOML `.codex/agents/*.toml` ＋ `config.toml` 登録、Cursor は該当機能なし）ため `~/.agents` では共有しない。Claude Code 用はディレクトリごと `.claude/agents` → `~/.claude/agents` に symlink する
- **プロジェクト固有の subagent**: 必要な場合は `<project>/.claude/agents/` に直接置く（`<project>/.agents` 経由では配布しない）

## Subagent（Claude Code）

`.claude/agents/*.md` に定義し、`just link-global` で `~/.claude/agents` に symlink されます。

| agent              | 用途                                                                 | model  | effort |
| ------------------ | -------------------------------------------------------------------- | ------ | ------ |
| `architect`        | 設計・トレードオフ・契約・実装順序の決定                             | fable  | xhigh  |
| `impl-worker`      | 仕様が確定した実装を1件担当。並列実装を main thread から切り離す     | opus   | medium |
| `browser-debugger` | 実ブラウザで再現手順と証拠（console / network / DOM / screenshot）   | opus   | medium |
| `check-runner`     | format / lint / typecheck / test / build の実行ループ                | sonnet | low    |
| `docs-verifier`    | 外部ライブラリの公式ドキュメントで API・既定値・バージョン差分を確認 | sonnet | low    |
| `pr-runner`        | PR 作成・更新、CI 監視、レビューコメント対応                         | sonnet | low    |

設計の原則:

- **model は「必要な知能」、effort は「速度ダイヤル」。** モデル階層を下げて速くするのではなく `effort` を役割ごとに下げる。Claude Code は全モデルが同じ使用量枠を共有するため、Codex の `gpt-5.3-codex-spark` のような「別枠だから安いモデルを使う」動機が存在しない。よって Haiku は使わない。
- **`effort` を省略するとセッション側の設定を継承する。** つまり省略は「速度を指定しない」ではなく「呼び出し元と同じ思考量で走る」こと。このリポジトリの想定は Opus + high なので、機械的な作業ほど明示的に下げる価値が大きい（実際の既定値はモデルと設定に依存するため、ここでは特定の値を前提にしない）。
- **組み込みとプラグインと重複させない。** 組み込みの `Explore` / `Plan` / `general-purpose` と、有効化済み plugin の `code-architect` / `code-explorer` / `code-reviewer` / `codex-rescue` が担う役割は作らない。とくに探索は組み込み `Explore` が速い（カスタム subagent は呼び出しごとに CLAUDE.md 階層と git status を再読み込みするが、`Explore` はこれをスキップする）。
- **数を増やさない。** 各 agent の `name` と `description` は毎セッション main thread の system prompt に載る。増やすと誤ルーティングが増え、失敗1回ごとに委譲の往復が丸ごと無駄になる。
- **`skills:` は「ほぼ毎回使うもの」だけ。** 挙げたスキルは全文が起動時に system prompt へ注入される。使うかどうかが呼び出しごとに変わるものは挙げず、`Skill` ツールでオンデマンドに取らせる。
- **`tools` はコンテキスト削減ではなく安全性のため。** Claude Code には Codex の `sandbox_mode` に相当する設定が無いので、書き込み禁止を表現する手段は `tools` allowlist だけ。

プロンプトは共通スケルトン（役割1文 → `Working mode` → `Constraints` → `Stop conditions` → `Return` → `When NOT to use`）に揃えています。`.claude/agents/` 直下には YAML frontmatter 付きの agent 定義 `.md` 以外を置かないこと（frontmatter が無いファイルは読み込みで警告になります）。

## 使い方

タスクランナーは **just** です。レシピ一覧はリポジトリルートで `just`（引数なし）を実行してください。

### symlink（希望の形：コピーせず参照）

- **グローバル**（このrepo → `~/.agents`）:

```bash
just link-global
```

> **注意**: `just link-global` は **main checkout のルート**で実行してください。worktree 内で実行すると
> symlink が worktree のパスを指し、worktree を削除した時点で壊れます。`just verify-global` は
> リンク先が main checkout のパスと一致するかを確認するので、このミスを検出できます。

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

グローバル（`~/.agents` / `~/.claude` / `~/.gemini` の symlink 健全性。読み取りのみ）:

```bash
just verify-global
```

プロジェクト:

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
