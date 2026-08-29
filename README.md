# dotagents

このリポジトリは **グローバルな agent 設定**（skills / rules / commands）と共通scheduled taskの **SSoT (Single Source of Truth)** です。

## 環境構築（基本は Nix）

[Nix](https://nixos.org/download/)（flakes 有効）だけ用意すれば、CLI ツールは [flake.nix](flake.nix) の devShell から揃います（**just / Bun / git / fd / jq / rg / lefthook / shellcheck / shfmt**）。

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

| パス         | 内容                                                                                                                                                                                                                                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `skills/`    | エージェントスキル（SSoT）                                                                                                                                                                                                                                         |
| `rules/`     | ルール（`.mdc` など）                                                                                                                                                                                                                                              |
| `commands/`  | Cursor / エージェント向けコマンド定義                                                                                                                                                                                                                              |
| `schedules/` | Codex / Claudeなどで共通利用するscheduled task定義。home配下へsymlinkせず、各providerへ明示的に反映する                                                                                                                                                            |
| `scripts/`   | リンク・同期・検証シェル                                                                                                                                                                                                                                           |
| `justfile`   | 上記スクリプトと開発タスクのエントリポイント                                                                                                                                                                                                                       |
| `.envrc`     | （任意）[direnv](https://direnv.net/) 用。`use flake` で devShell を自動適用                                                                                                                                                                                       |
| `codex/`     | 共通global instructionの日本語正典`AGENTS-ja.md`と英訳runtime`AGENTS.md`、Codex subagent、hook、共有ベース設定。`config.toml`はreferenceであり、`~/.codex/config.toml`はhome固有のまま管理する                                                                     |
| `claude/`    | Claude Code用global instruction bridge、subagent定義、hook（`~/.claude/hooks` へlinkされる。空でもdirectoryは保持する）、共有設定のreference。`~/.claude/settings.json` は自動linkしない（hookを登録する場合は `claude/settings.template.json` の `hooks` に置く） |
| `gemini/`    | Gemini CLI用global instruction bridge                                                                                                                                                                                                                              |

## 設計

- **グローバルasset**: `~/.agents` にこのrepoの `skills/` `rules/` `commands/` を symlink（SSoT）
- **共通のglobal instruction**: `codex/AGENTS-ja.md` を編集上の正典とする。日本語版を先に更新し、その全文を英訳した[codex/AGENTS.md](codex/AGENTS.md)へ反映する。`gemini/GEMINI.md`は英語runtime版への相対symlinkを維持する。`claude/CLAUDE.md`はsymlinkではなく実ファイルで、`codex/AGENTS.md`を土台にClaude Codeに存在しない概念（Codex固有の`fork_turns`など）を除いたもの。home側の標準パスからは各bridgeへsymlinkする
- **このrepo固有のinstruction**: root [AGENTS.md](AGENTS.md) が正典。root `CLAUDE.md` と `GEMINI.md` は各tool向けのproject instruction bridge
- **home固有設定**: `~/.codex/config.toml` と `~/.claude/settings.json`、認証、履歴、DB、plugin、cacheはrepoへlinkしない
- **scheduled task**: `schedules/` で共通のcadenceとskillをGit管理し、provider固有の保存先、権限、履歴、thread関連付けはhomeまたはcloud側に残す
- **プロジェクト固有**: `<project>/.agents` はプロジェクト内で管理（ここは自由に追加/上書き）
- **各エージェント**: `<project>/.cursor/.codex/.claude` は `<project>/.agents` を参照するように symlink
- **Subagent**: 形式がツールごとに異なる（Claude Code は `claude/agents/*.md`、Codex は `codex/agents/*.toml` ＋ `config.toml` 登録）ため `~/.agents` では共有せず、それぞれのhome標準パスへlinkする
- **プロジェクト固有の subagent**: 必要な場合は `<project>/.claude/agents/` に直接置く（`<project>/.agents` 経由では配布しない）
- **Hook**: hook scriptは `claude/hooks/` と `codex/hooks/` でGit管理し、`just link-global` で `~/.claude/hooks` と `~/.codex/hooks` へsymlinkする。hookの登録先（`~/.claude/settings.json` の `hooks`、`codex/hooks.json`）は起動側の設定なので、Claude側はhome固有設定として扱う
- **Cursorのglobal rule**: file symlinkではなくCursorの Customize → Rules で管理する。root `AGENTS.md` はproject ruleとして利用できる

## Subagent（Claude Code）

`claude/agents/*.md` に定義し、`just link-global` で `~/.claude/agents` に symlink されます。

| agent              | 用途                                                                              | model  | effort |
| ------------------ | --------------------------------------------------------------------------------- | ------ | ------ |
| `architect`        | 設計・トレードオフ・契約・実装順序の決定（**`@agent-architect` で明示呼び出し**） | fable  | xhigh  |
| `impl-worker`      | 仕様が確定した実装を1件担当。並列実装を main thread から切り離す                  | opus   | medium |
| `browser-debugger` | 実ブラウザで再現手順と証拠（console / network / DOM / screenshot）                | opus   | medium |
| `light-worker`     | format / lint / typecheck / test / build の実行ループ                             | sonnet | low    |
| `docs-researcher`  | 外部ライブラリの公式ドキュメントで API・既定値・バージョン差分を確認              | sonnet | low    |
| `researcher`       | 一次資料・repository・dataなど、独立したEvidence laneをread-onlyで調査            | sonnet | medium |
| `evidence-analyst` | 原因分解・比較・感度・代替仮説をread-onlyで分析                                   | opus   | high   |
| `evidence-auditor` | 重要claimのsupport・coverage・source品質・scopeをread-onlyで監査                  | opus   | high   |
| `pr-runner`        | PR 作成・更新、CI 監視、レビューコメント対応                                      | sonnet | low    |
| `web-operator`     | ログイン済みブラウザ経由で Notion / Slack / X / 社内 SaaS のページを取得          | sonnet | medium |

委譲の仕組み（実測と一次情報で確認したもの）:

- **自動委譲は best effort。** Claude は「リクエスト中のタスク記述」「各 agent の `description`」「現在のコンテキスト」の 3 つで判断します。加えてセッションによっては「ユーザーに言われない限り agent を spawn するな」というシステムプロンプト側の指示が載るため、`description` をどう書いても発火が保証されません。**確実に走らせる手段は `@agent-<name>` だけです。**
- **`description` は「主題」ではなく「吸収する使い捨て出力の量」で書く。** モデルはコンテキスト隔離の価値で判断しており、タスクの分野では判断していません。実測では出力の長い`light-worker`が発火しました。`architect`は明示呼び出しとし、`docs-researcher`は外部documentationを大量に読む調査を隔離します。
- **小文字の `use proactively` は実際に配線されています。** Agent ツールの説明に「description が proactively に使うべきと述べていれば、ユーザーに言われる前に使うよう最善を尽くせ」という指示が入っています（バイナリで確認）。一方 **`MUST BE USED` はバイナリにも公式ドキュメントにも存在しない folklore**、**全大文字 `PROACTIVELY` も無意味**（バイナリ内の該当箇所は無関係な認証ライブラリの定数）。
- **設計判断はmain thread、独立した設計reviewは`architect`。** 頻繁な往復や複数phaseでcontextを共有する設計判断はmain threadで扱い、独立した評価が必要なときだけ`architect`を明示呼び出しします。外部documentationの大量取得は`docs-researcher`へ隔離します。
- **subagent には自動起動を強制/禁止する frontmatter フィールドがありません。** skill にある `when_to_use` / `disable-model-invocation` / `paths` に相当するものは無く、禁止側は permission で `Agent(<name>)` を deny するしかありません。

設計の原則:

- **model は「必要な知能」、effort は「速度ダイヤル」。** モデル階層を下げて速くするのではなく `effort` を役割ごとに下げる。Claude Code は全モデルが同じ使用量枠を共有するため、Codex の `gpt-5.3-codex-spark` のような「別枠だから安いモデルを使う」動機が存在しない。よって Haiku は使わない。
- **`effort` を省略するとセッション側の設定を継承する。** つまり省略は「速度を指定しない」ではなく「呼び出し元と同じ思考量で走る」こと。このリポジトリの想定は Opus + high なので、機械的な作業ほど明示的に下げる価値が大きい（実際の既定値はモデルと設定に依存するため、ここでは特定の値を前提にしない）。
- **組み込みとプラグインと重複させない。** 組み込みの `Explore` / `Plan` / `general-purpose` と、有効化済み plugin の `code-architect` / `code-explorer` / `code-reviewer` / `codex-rescue` が担う役割は作らない。とくに探索は組み込み `Explore` が速い（カスタム subagent は呼び出しごとに CLAUDE.md 階層と git status を再読み込みするが、`Explore` はこれをスキップする）。
- **数を増やさない。** 各 agent の `name` と `description` は毎セッション main thread の system prompt に載る。増やすと誤ルーティングが増え、失敗1回ごとに委譲の往復が丸ごと無駄になる。
- **`skills:` は「ほぼ毎回使うもの」だけ。** 挙げたスキルは全文が起動時に system prompt へ注入される。使うかどうかが呼び出しごとに変わるものは挙げず、`Skill` ツールでオンデマンドに取らせる。
- **`tools` はコンテキスト削減ではなく安全性のため。** Claude Code には Codex の `sandbox_mode` に相当する設定が無いので、書き込み禁止を表現する手段は `tools` allowlist だけ。
- **共有 instruction は短く保つ。** 非 fork の subagent は**呼び出しごとに** CLAUDE.md 階層全体を読み直します（`Explore` / `Plan` だけが省略し、変更手段はありません）。セッション単位より強い動機でここを削る価値があります。公式の目標値は 1 ファイル 200 行未満で、`@path` import は整理には役立つがコンテキストは減りません（launch 時に読まれる）。

プロンプトは共通スケルトン（役割1文 → `Working mode` → `Constraints` → `Stop conditions` → `Return` → `When NOT to use`）に揃えています。`claude/agents/` 直下には YAML frontmatter 付きの agent 定義 `.md` 以外を置かないこと（frontmatter が無いファイルは読み込みで警告になります）。

## 使い方

タスクランナーは **just** です。レシピ一覧はリポジトリルートで `just`（引数なし）を実行してください。

### symlink（希望の形：コピーせず参照）

- **グローバル**（このrepo → `~/.agents`）:

```bash
just link-global
```

> `just link-global` はGitのcommon directoryからmain checkoutを解決し、worktree内から実行しても
> home linkをmain checkoutへ向けます。`just verify-global` は全管理対象とinstruction bridgeのdriftを検出します。

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

グローバル（`~/.agents` / `~/.codex` / `~/.claude` / `~/.gemini` の管理対象symlink。読み取りのみ）:

```bash
just verify-global
```

プロジェクト:

```bash
just verify-project /path/to/your-project
```

## Hook（Claude Code）

`claude/hooks/*.sh` に置き、`just link-global` で `~/.claude/hooks` に symlink されます。登録は
`~/.claude/settings.json` の `hooks` で行い、こちらは home 固有設定なので Git 管理しません。

| hook                           | event                           | 役割                                                             |
| ------------------------------ | ------------------------------- | ---------------------------------------------------------------- |
| `worktree-git-wt.sh`           | WorktreeCreate / WorktreeRemove | Claude Code の worktree ライフサイクルを `git wt` に委譲する     |
| `block-agent-branch-prefix.sh` | PreToolUse (Bash)               | `claude/` `codex/` 等の agent 名 prefix を持つ branch 作成を拒否 |

`block-agent-branch-prefix.sh` の設計:

- **拒否リスト方式**（`claude|codex|gemini|cursor|copilot|devin|agent|ai`）。Git Flow の許可リストにすると、
  repository 固有の命名規則がある場合に誤爆する。常に誤りと言える agent prefix だけを弾く
- **作成のみを拒否**する。`git branch -d claude/old` の削除、`git checkout claude/existing` の切り替え、
  `--set-upstream-to=...` 等の維持操作、`--list` 等の参照は通す
- **git の綴りは短形・長形の両方を見る**。`-c` だけでなく `--create`、`--force-create`、`--orphan` も
  作成なので、短形しか見ないと長形が抜け道になる
- **copy と rename は最後の引数が宛先**。`git branch -c main claude/foo` で最初の operand を読むと
  source の `main` を拾って新 branch を見逃す
- **push の refspec は省略形も解釈する**。`git push origin claude/foo`、`HEAD:claude/foo`、`+claude/foo` は
  すべて remote branch の作成。`--delete` と `:claude/foo`（空 source）は削除なので通す
- **quote は解析前に除去**する。`git checkout -b "claude/foo"` は tokenize で quote が残り、
  anchored な prefix 一致が外れて抜け道になる
- **command word が git 自身であることを要求**する。segment 内の任意の位置の `git` を見ると
  `echo git checkout -b claude/foo` のような無害なコマンドを誤爆させる
- **heredoc の本文は解析前に除去**する。skill や script を書くたびに、本文に含まれる
  forbidden command の文字列で誤爆するため
- 事前フィルタ `if: "Bash(git *)"` は**使わない**。権限ルール構文は前方一致のみで、
  `cd /foo && git checkout -b claude/x` のように `git` で始まらない複合コマンドを取り逃す

検証は `just test-hooks`（61 ケース。ブロックすべき形と、通すべき形の両方）。

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

## Evidence work のA/B評価

`evidence-work` は、専門概念、source-backed research、対象固有の原因診断、business/personal decisionをEvidenceへ接続するskillです。日常質問と実装taskは既存flowを維持します。

評価runnerは、対象skillを無効化した`control`、暗黙起動の`auto`、明示起動の`forced`を同一prompt・model・reasoning・tool条件で比較します。各runはread-onlyかつephemeralで、skill比較中はhookを無効にします。まずmodelを呼ばないplanを確認してください。

```bash
just eval-evidence-work-smoke --dry-run
just eval-evidence-work-full --dry-run
```

実行command:

```bash
# 8 case x control/auto/forced x 1回
just eval-evidence-work-smoke

# 24 case x control/auto x 3回。tokenとreview時間が大きいので重要変更時のみ
just eval-evidence-work-full

# autoで取りこぼしたcaseだけforcedで診断
just eval-evidence-work-forced direct-prop-amm,research-metaplanet

# skill本体とは別にautoとauto+hookを比較
just eval-evidence-work-hook
```

artifactはgit管理外の`data/evaluations/evidence-work/<run-id>/`へ保存されます。`comparison.md`はarm名を隠した状態で採点し、`arm-key.json`は採点後に開きます。`ratings.jsonl`を埋めた後、次のcommandで`summary.json`へ集計します。

```bash
./skills/evidence-work/scripts/eval.ts \
  --summarize-run data/evaluations/evidence-work/<run-id>
```

実際のObsidian・業務情報を使うcaseはcommitせず、`--private-cases <git管理外のJSONL>`で追加してください。通常の`--cases`は`privacy_class: sanitized`、`--private-cases`は`privacy_class: private`だけを受け付けます。高costなprivate caseを絞って比較する場合は、`--case-ids id-a,id-b`を指定すると、選択したcaseだけをmode既定のarmで実行できます。

## 仕様

- `.agents/` は **生成物** として扱います（手編集しない想定）。
- 同期は **片方向**（dotagents → target）です。
- 同期先でソース側に存在しないファイルは削除しません（安全側）。必要なら `--delete` を使ってください。
