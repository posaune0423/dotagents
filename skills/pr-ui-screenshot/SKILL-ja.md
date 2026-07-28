---
name: pr-ui-screenshot
description: >-
  PR 用に UI の新旧比較・全言語のスクリーンショットを撮影し、GitHub にアップロードして
  PR 本文のスクリーンショットセクションだけを書き換える。フロントエンドの変更で UI や文言が
  変わり比較画像が必要なとき、または PR のスクリーンショットの添付・更新・撮り直しを
  頼まれたときに使う。
---

# PR UI スクリーンショット

フロントエンドの差分から PR 本文のスクリーンショットセクションを生成する。
何が変わったかを特定し、merge-base と HEAD の両方で撮影し、文言が変わっていれば全言語を撮り、
画像が正しいことを検証し、GitHub にアップロードして、該当セクションだけを差し替える。

確認なしで最後まで実行する。安全弁は Phase 4 で、
**検証を通らない限りアップロードも PR 本文の更新も行わない**。

## 前提

- `git` / `gh`（認証済み）/ `node` が PATH にあること。それ以外は不要
  （PNG は node 標準の `zlib` で自前デコードするので ImageMagick・`jq`・`curl` は使わない）。
- **対象リポジトリ側**に Playwright が入っていること
  （`pnpm exec playwright install chromium`）。スクリプトはこの skill 側ではなく
  対象リポジトリから解決する。
- アップロード用の GitHub セッション。初回のみ:
  `node <skill>/scripts/upload-assets.mjs --login`
- 現在のブランチに対する PR が存在すること。

以下、`<skill>` はこのディレクトリ、`<w>` は作業用ディレクトリ（`$TMPDIR/pr-ui-screenshot`）。

## Phase 0: 設定の解決

```bash
<skill>/scripts/resolve-config.mjs --explain > <w>/config.json
```

後勝ちの重ね合わせ: 同梱の `presets/default.json` → `presets/<owner>-<repo>.json` →
`<repo>/.claude/pr-ui-screenshot.json` → `<repo>/.agents/pr-ui-screenshot.json` →
`$PR_UI_SCREENSHOT_CONFIG`。

プロジェクト固有の設定は `<repo>/.claude/pr-ui-screenshot.json` に置き、**そのリポジトリ自身に
コミットする**。private なコードベースのルート・locale・cookie をこの skill 側に持ち込まないため。
キーの一覧は [references/config.md](references/config.md)。

`dev.command` / `locales` / `section.heading` が明らかに合わないのに設定ファイルが無い場合は、
それを作り、**作ったことをユーザーに伝える**。黙って推測しない。

## Phase 1: 撮影対象を決める

**この手順の前に [references/capture-targets.md](references/capture-targets.md) を読むこと。**
ここが唯一スクリプトに任せられない判断であり、失敗の原因になる箇所。

要点は、merge-base との差分を取り、設定の `detect.*` で変更パスを分類し、
変更されたコンポーネントや翻訳キーから**実際にそれを描画するルート**まで辿ること。
`<w>/manifest.json` を [references/manifest.md](references/manifest.md) の形式で書く。

守るべきルール:

- 翻訳ファイルが変わった → 全言語テーブルが必須。
- 既存 UI が変わった → 新旧テーブルが必須。base 側も必ず撮る。
- 本当に新規の UI → `"captureBase": false`。旧セルは `---` になる。
- ロジック・テスト・型だけの変更 → **何も作らず**、その旨を伝えて終了する。

## Phase 2: HEAD と merge-base の dev server を立てる

```bash
head_url=$(<skill>/scripts/serve.sh --dir "$(git rev-parse --show-toplevel)" \
  --port "$(<skill>/scripts/resolve-config.mjs --get dev.port)" \
  --command "$(<skill>/scripts/resolve-config.mjs --get dev.command)" \
  --timeout "$(<skill>/scripts/resolve-config.mjs --get dev.readyTimeoutSec)" --pid-file <w>/head.pid)

base_dir=$(<skill>/scripts/base-worktree.sh --install "$(<skill>/scripts/resolve-config.mjs --get install.command)")
base_url=$(<skill>/scripts/serve.sh --dir "$base_dir" \
  --port "$(<skill>/scripts/resolve-config.mjs --get dev.basePort)" \
  --command "$(<skill>/scripts/resolve-config.mjs --get dev.command)" \
  --timeout "$(<skill>/scripts/resolve-config.mjs --get dev.readyTimeoutSec)" --pid-file <w>/base.pid)
```

`serve.sh` は既にそのポートが応答していれば再利用する。
`base-worktree.sh` は merge-base を `$TMPDIR` 配下に detached で展開し、
lockfile が同一なら `node_modules` を symlink で共有する。
**対象リポジトリのワーキングツリーには一切触れない。**
すべての pair が `captureBase: false` なら base server は不要。

## Phase 3: 撮影

```bash
node <skill>/scripts/capture.mjs --config <w>/config.json --manifest <w>/manifest.json \
  --base-url "$head_url" --side head
node <skill>/scripts/capture.mjs --config <w>/config.json --manifest <w>/manifest.json \
  --base-url "$base_url" --side base
```

`deviceScaleFactor: 2`、アニメーション無効で撮影し、認証 cookie は**最初の遷移前**に投入する。
`selector` は余白付きで収める。はみ出す場合は**ズームアウトではなく viewport を広げる**
（文字が潰れるとレビュー対象の文言が読めなくなるため）。locale 撮影は head 側のみ。

ログインが要る対象がある場合は `auth.cookies[].valueEnv` の env を先に設定する。
単体デバッグは `--headed --only <id>`。

## Phase 4: 検証（ゲート）

```bash
<skill>/scripts/validate.mjs --manifest <w>/manifest.json
```

ファイル欠損・読めない画像・小さすぎる画像・真っ白な画像・
**新旧がピクセル単位で同一**・**全 locale が同一** を検出して落とす。

ここで落ちるのはノイズではなく本物の指摘。
新旧が同一なら撮った画面に変更が含まれていない。全 locale が同一なら locale が切り替わっていない。
manifest を直して撮り直すこと。**閾値を下げて通してはいけないし、
落ちた manifest のまま Phase 5 に進んではいけない。**

## Phase 5: アップロード

```bash
node <skill>/scripts/upload-assets.mjs --config <w>/config.json --manifest <w>/manifest.json \
  --repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
  --pr "$(gh pr view --json number --jq .number)"
```

`user-attachments` には公式 API がないため、ログイン済みブラウザセッションを使い、
PR のコメント欄を**アップロードフォームとしてだけ**借りる。
**投稿は一切しない**（1 枚ごとに下書きをクリアし、Comment ボタンは押さない）。
既に `url` を持つ画像はスキップするので、途中まで進んだ実行の再開は安全。
1 枚でも失敗したら非ゼロ終了し、**PR 本文には触れない**。

## Phase 6: セクションの差し替え

```bash
gh pr view --json body --jq .body > <w>/body.md
node <skill>/scripts/render-section.mjs --config <w>/config.json \
  --manifest <w>/manifest.json --out <w>/section.md
node <skill>/scripts/replace-section.mjs --config <w>/config.json \
  --body <w>/body.md --section <w>/section.md --out <w>/new-body.md
diff <w>/body.md <w>/new-body.md
<skill>/../create-pr/scripts/pr-body-update.sh --file <w>/new-body.md
```

`render-section.mjs` は `section.template`（`templates/default.md`、日本語の旧/新レイアウトなら
`templates/ja-before-after-locales.md`）を埋める。
**レイアウトを変えたいときはこのテンプレートを編集するか、自前のファイルを指す。**
`replace-section.mjs` は `section.heading` から次の同レベル見出しまでのみ差し替える。
見出しが重複していれば実行を拒否し、テンプレートの見出しと設定が食い違っていても拒否する。
それ以外（CodeRabbit のブロック、CRLF 改行を含む）はバイト単位で保持される。

本文更新は `create-pr` の `pr-body-update.sh` を再利用する（GraphQL 更新＋結果照合まで行う）。

## Phase 7: 後片付けと報告

```bash
<skill>/scripts/serve.sh --stop --pid-file <w>/head.pid
<skill>/scripts/serve.sh --stop --pid-file <w>/base.pid
<skill>/scripts/base-worktree.sh --remove
```

**この実行で起動した server だけ**を止める。
続けて実行する見込みがあれば worktree は残す（初回コンパイルを省ける）。

報告する内容: 撮影した画面、viewport と locale、PR の URL、
そして**意図的に省いたもの**（到達できなかったルート、ログインが必要で撮れなかった locale）。
検証に落ちて中断した場合はその事実をはっきり伝える。**途中結果を完了として報告しない。**

## 注意

- 検証を通すために閾値を下げない。
- アップロード中に Comment を押さない。
- セッションファイルは有効な GitHub cookie を含む。mode 600 で、**絶対にコミットしない**。
- テンプレートは意図的に prettier の対象外。ブロックタグは必ず単独行に置くこと。
- 設定キー一覧: [references/config.md](references/config.md)。
- 詳細: [references/troubleshooting.md](references/troubleshooting.md)。
