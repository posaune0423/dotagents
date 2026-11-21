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
- **共通のglobal instruction**: `codex/AGENTS-ja.md` を編集上の正典とする。日本語版を先に更新し、その全文を英訳した[codex/AGENTS.md](codex/AGENTS.md)へ反映する。`claude/CLAUDE.md`と`gemini/GEMINI.md`は英語runtime版への相対symlinkを維持し、home側の標準パスから各bridgeへsymlinkする
- **このrepo固有のinstruction**: root [AGENTS.md](AGENTS.md) が正典。root `CLAUDE.md` と `GEMINI.md` は各tool向けのproject instruction bridge
- **home固有設定**: `~/.codex/config.toml` と `~/.claude/settings.json`、認証、履歴、DB、plugin、cacheはrepoへlinkしない
- **scheduled task**: `schedules/` で共通のcadenceとskillをGit管理し、provider固有の保存先、権限、履歴、thread関連付けはhomeまたはcloud側に残す
- **プロジェクト固有**: `<project>/.agents` はプロジェクト内で管理（ここは自由に追加/上書き）
- **各エージェント**: `<project>/.cursor/.codex/.claude` は `<project>/.agents` を参照するように symlink
- **Subagent**: 形式がツールごとに異なる（Claude Code は `claude/agents/*.md`、Codex は `codex/agents/*.toml` ＋ `config.toml` 登録）ため `~/.agents` では共有せず、それぞれのhome標準パスへlinkする
- **プロジェクト固有の subagent**: 必要な場合は `<project>/.claude/agents/` に直接置く（`<project>/.agents` 経由では配布しない）
- **Hook**: hook scriptは `claude/hooks/` と `codex/hooks/` でGit管理し、`just link-global` で `~/.claude/hooks` と `~/.codex/hooks` へsymlinkする。hookの登録先（`~/.claude/settings.json` の `hooks`、`codex/hooks.json`）は起動側の設定なので、Claude側はhome固有設定として扱う
- **Cursorのglobal rule**: file symlinkではなくCursorの Customize → Rules で管理する。root `AGENTS.md` はproject ruleとして利用できる

## 外部スキルの管理

Git管理している外部由来のスキルは、[skills-lock.json](skills-lock.json) に取得元と取り込み後の内容を記録します。
自作スキルと、ローカル専用の未追跡スキルは対象外です。

- `source` / `sourceType` / `skillPath`: 上流リポジトリと、その中の `SKILL.md` のパス。
- `ref`: 取り込み元、または取り込んだ内容と一致する上流コミットを確認できる場合に記録します。不明な場合は推測で埋めません。
- `computedHash`: Skills CLIと同じ方式で、スキル配下の全ファイルの相対パスと内容から計算するSHA-256です（パス順に整列し、`.git` / `node_modules` を除外）。ローカル修正も含みます。

外部スキルを追加・更新したらlockも更新します。上流の更新を取り込む際は、既存のローカル修正を確認してから差分を反映します。
`ref` がない既存項目は内容の追跡用であり、取得元のコミットまで固定した記録ではありません。

## Subagent

Claude Code は `claude/agents/*.md`、Codex は `codex/agents/*.toml`（`codex/config.toml` の `[agents.*]` に登録）に定義し、`just link-global` でそれぞれ `~/.claude/agents` / `~/.codex/agents` に symlink されます。
共通の役割は同じ名前にそろえ、使われていない agent や役割が重なる agent は置きません（2026-11 時点で直近 30 日の spawn 実績を見て整理）。

| agent              | 用途                                                                    | Claude Code       | Codex                 |
| ------------------ | ----------------------------------------------------------------------- | ----------------- | --------------------- |
| `light-worker`     | format / lint / typecheck / test / build を実行し、結果だけ返す         | `haiku` / low     | `gpt-6-luna` / medium |
| `docs-researcher`  | 外部ライブラリの公式ドキュメントで API・既定値・バージョン差分を確認    | `sonnet` / low    | `gpt-6-luna` / high   |
| `researcher`       | 一次資料・repository・data など、独立した調査 lane を read-only で担当  | `sonnet` / medium | `gpt-6-luna` / high   |
| `impl-worker`      | 対象 file・挙動・完了条件が決まった実装を1件担当                        | `opus` / medium   | 親を継承 / medium     |
| `pr-runner`        | PR 作成・更新、CI 監視、レビューコメント対応                            | `sonnet` / low    | 親を継承 / low        |
| `web-operator`     | ログイン済みブラウザで Notion / Slack / X / 社内 SaaS のページを取得    | `sonnet` / medium | —                     |
| `architect`        | 設計・トレードオフ・実装順序の判断                                      | —                 | 親を継承 / high       |
| `reviewer`         | 正しさ・セキュリティ・回帰・テスト漏れに絞った PR レビュー              | —                 | 親を継承 / high       |
| `evidence-analyst` | 原因分解・比較・感度・代替仮説を read-only で分析（`evidence-work` 用） | —                 | 親を継承 / high       |
| `evidence-auditor` | 重要 claim の根拠・網羅性・情報源の質を read-only で監査（同上）        | —                 | 親を継承 / high       |
| `explorer`         | Codex 組み込みの探索 role の model だけを上書き                         | —                 | `gpt-6-luna` / medium |

整理の方針（契約は `scripts/tests/codex-agent-routing.test.sh` で検査）:

- **spawn には毎回コストがかかる。** 非 fork の subagent は空の context から始まり、CLAUDE.md 階層を読み直します。並列化、長い出力の隔離、実装を見ていない立場での review に限って使い、往復の多い作業や短い変更は main thread で行います。
- **Claude Code は自分からはほとんど spawn しない。** 最近の版では Agent ツールの説明に「ユーザーに頼まれない限り spawn しない」という指示が入っており、自動委譲はあてになりません。確実に走らせるには `@agent-<name>` で呼ぶか、skill の手順から呼びます。Codex も、直接頼まれたときか `AGENTS.md` / skill が委譲を指示したときに spawn します。
- **model は最新を追う側に寄せる。** Claude Code は `opus` / `sonnet` / `haiku` / `fable` の alias を使います（alias は最新版を指し続ける）。Codex は軽い scan 系だけ `gpt-6-luna` に固定し、それ以外は `model` を書かずに親（`config.toml` の `model`）を継承させます。model の更新は `config.toml` の1か所で済みます。
- **軽い作業には軽い model。** 公式ドキュメントは単純な作業に Haiku を勧めているので、`light-worker` は `haiku` で動かします。
- **`effort` は必ず書く。** main と別の model で動く subagent はセッションの effort を継承しないため、役割ごとに明示します。
- **組み込みとプラグインと重複させない。** Claude Code の `Explore` / `Plan` / `general-purpose` と、有効化済み plugin の `code-architect` / `code-explorer` / `code-reviewer` / `codex-rescue` が担う役割は作りません。探索は組み込み `Explore` が速い（CLAUDE.md の読み直しを省く）。
- **`description` には「吸収する出力の量」を書く。** model は context を隔離する価値で委譲を判断します。小文字の `use proactively` は公式に案内されている書き方ですが、発火は保証されません。
- **`tools` は安全のために絞る。** Claude Code には Codex の `sandbox_mode` に当たる設定が無いので、書き込みを禁じる手段は `tools` allowlist だけです。`skills:` には毎回使うものだけを挙げます（全文が起動時に注入される）。

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

### Claude Code on the web

クラウドのセッションにはローカルの `~/.claude` が渡らないため、claude.ai/code の環境の **Setup script** に次を書きます（root で、Claude Code の起動前に走る）。

```bash
git clone --depth 1 https://github.com/posaune0423/dotagents.git ~/dotagents && ~/dotagents/scripts/cloud-setup.sh
```

`link-dotagents.sh --home --all --tool-links` に加えて `~/.claude/{skills,commands,rules}` を `~/.agents` へ繋ぎ、
`~/.claude/settings.json` に `cloud-setup.sh --refresh`（`git pull`）の SessionStart hook を登録します。
環境は setup の結果を snapshot して以降のセッションで setup script を飛ばすため、更新はこの hook が取り込みます。
Git に入っていない skill（`skills/projects/*` や `.git/info/exclude` のもの）とplugin（`enabledPlugins`）はクラウドには入りません。

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

## Hook（Claude Code / Codex）

`claude/hooks/*.sh` に置き、`just link-global` で `~/.claude/hooks` に symlink されます。登録は
`~/.claude/settings.json` の `hooks` で行い、こちらは home 固有設定なので Git 管理しません。

Codex のブランチ名ガードは `codex/hooks.json` から同じ `~/.claude/hooks/block-agent-branch-prefix.sh` を呼びます。
標準の `--tool-links` 設定は Codex と Claude の hooks ディレクトリを両方 link するため、スクリプトを二重管理しません。
Codex 側では新しいフックを `/hooks` で確認・承認してから使います。

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
