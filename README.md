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
| `.claude/`  | Claude Code 用の共有設定。`CLAUDE.md`（`AGENTS.md` への symlink）/ `settings.json` と subagent 定義 `agents/*.md`                                                                                           |
| `.codex/`   | （任意）Codex 用の共有ベース設定。subagent は `agents/*.toml` ＋ `config.toml` の `[agents.*]` 登録。`config.toml` はパス依存を除いた最小構成なので、ローカルの `~/.codex/config.toml` とマージして使う想定 |

## 設計

- **グローバル**: `~/.agents` にこのrepoの `skills/` `rules/` `commands/` を symlink（SSoT）
- **共通の instruction**: [AGENTS.md](AGENTS.md) が正典。root の `CLAUDE.md` と `.claude/CLAUDE.md` はどちらもそれへの symlink（Claude Code は `AGENTS.md` を読まないため、公式が挙げている橋渡しのうち symlink 方式を採用）。目的はトークン削減ではなく**乖離防止**で、同じ内容が複製されて実際に食い違っていたのを解消するためです。`.gemini/GEMINI.md` は現状コピーのままで、既知の残件です
- **プロジェクト固有**: `<project>/.agents` はプロジェクト内で管理（ここは自由に追加/上書き）
- **各エージェント**: `<project>/.cursor/.codex/.claude` は `<project>/.agents` を参照するように symlink
- **Subagent**: 形式がツールごとに異なる（Claude Code は Markdown `.claude/agents/*.md`、Codex は TOML `.codex/agents/*.toml` ＋ `config.toml` 登録、Cursor は該当機能なし）ため `~/.agents` では共有しない。Claude Code 用はディレクトリごと `.claude/agents` → `~/.claude/agents` に symlink する
- **プロジェクト固有の subagent**: 必要な場合は `<project>/.claude/agents/` に直接置く（`<project>/.agents` 経由では配布しない）

## Subagent（Claude Code）

`.claude/agents/*.md` に定義し、`just link-global` で `~/.claude/agents` に symlink されます。

| agent              | 用途                                                                              | model  | effort |
| ------------------ | --------------------------------------------------------------------------------- | ------ | ------ |
| `architect`        | 設計・トレードオフ・契約・実装順序の決定（**`@agent-architect` で明示呼び出し**） | fable  | xhigh  |
| `impl-worker`      | 仕様が確定した実装を1件担当。並列実装を main thread から切り離す                  | opus   | medium |
| `browser-debugger` | 実ブラウザで再現手順と証拠（console / network / DOM / screenshot）                | opus   | medium |
| `check-runner`     | format / lint / typecheck / test / build の実行ループ                             | sonnet | low    |
| `docs-verifier`    | 外部ライブラリの公式ドキュメントで API・既定値・バージョン差分を確認              | sonnet | low    |
| `pr-runner`        | PR 作成・更新、CI 監視、レビューコメント対応                                      | sonnet | low    |

委譲の仕組み（実測と一次情報で確認したもの）:

- **自動委譲は best effort。** Claude は「リクエスト中のタスク記述」「各 agent の `description`」「現在のコンテキスト」の 3 つで判断します。加えてセッションによっては「ユーザーに言われない限り agent を spawn するな」というシステムプロンプト側の指示が載るため、`description` をどう書いても発火が保証されません。**確実に走らせる手段は `@agent-<name>` だけです。**
- **`description` は「主題」ではなく「吸収する使い捨て出力の量」で書く。** モデルはコンテキスト隔離の価値で判断しており、タスクの分野では判断していません。実測でも、出力の長い `check-runner` は発火し、設計判断とドキュメント参照は発火しませんでした。
- **小文字の `use proactively` は実際に配線されています。** Agent ツールの説明に「description が proactively に使うべきと述べていれば、ユーザーに言われる前に使うよう最善を尽くせ」という指示が入っています（バイナリで確認）。一方 **`MUST BE USED` はバイナリにも公式ドキュメントにも存在しない folklore**、**全大文字 `PROACTIVELY` も無意味**（バイナリ内の該当箇所は無関係な認証ライブラリの定数）。
- **設計判断とドキュメント参照が main thread に残るのは仕様どおり。** 公式ドキュメントは「頻繁な往復」「複数フェーズでコンテキストを共有」「小さく的を絞った変更」「レイテンシ重要」を main thread 向きと明記しています。よって `architect` は proactive 表現を入れず、明示呼び出し前提にしています。
- **subagent には自動起動を強制/禁止する frontmatter フィールドがありません。** skill にある `when_to_use` / `disable-model-invocation` / `paths` に相当するものは無く、禁止側は permission で `Agent(<name>)` を deny するしかありません。

設計の原則:

- **model は「必要な知能」、effort は「速度ダイヤル」。** モデル階層を下げて速くするのではなく `effort` を役割ごとに下げる。Claude Code は全モデルが同じ使用量枠を共有するため、Codex の `gpt-5.3-codex-spark` のような「別枠だから安いモデルを使う」動機が存在しない。よって Haiku は使わない。
- **`effort` を省略するとセッション側の設定を継承する。** つまり省略は「速度を指定しない」ではなく「呼び出し元と同じ思考量で走る」こと。このリポジトリの想定は Opus + high なので、機械的な作業ほど明示的に下げる価値が大きい（実際の既定値はモデルと設定に依存するため、ここでは特定の値を前提にしない）。
- **組み込みとプラグインと重複させない。** 組み込みの `Explore` / `Plan` / `general-purpose` と、有効化済み plugin の `code-architect` / `code-explorer` / `code-reviewer` / `codex-rescue` が担う役割は作らない。とくに探索は組み込み `Explore` が速い（カスタム subagent は呼び出しごとに CLAUDE.md 階層と git status を再読み込みするが、`Explore` はこれをスキップする）。
- **数を増やさない。** 各 agent の `name` と `description` は毎セッション main thread の system prompt に載る。増やすと誤ルーティングが増え、失敗1回ごとに委譲の往復が丸ごと無駄になる。
- **`skills:` は「ほぼ毎回使うもの」だけ。** 挙げたスキルは全文が起動時に system prompt へ注入される。使うかどうかが呼び出しごとに変わるものは挙げず、`Skill` ツールでオンデマンドに取らせる。
- **`tools` はコンテキスト削減ではなく安全性のため。** Claude Code には Codex の `sandbox_mode` に相当する設定が無いので、書き込み禁止を表現する手段は `tools` allowlist だけ。
- **共有 instruction は短く保つ。** 非 fork の subagent は**呼び出しごとに** CLAUDE.md 階層全体を読み直します（`Explore` / `Plan` だけが省略し、変更手段はありません）。セッション単位より強い動機でここを削る価値があります。公式の目標値は 1 ファイル 200 行未満で、`@path` import は整理には役立つがコンテキストは減りません（launch 時に読まれる）。

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
