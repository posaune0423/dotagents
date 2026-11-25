---
name: natural-japanese-gemini
description: 既存の日本語文書の推敲を、Orca の worker として起動した Antigravity(既定は Gemini 4 Hydrogen)に natural-japanese スキルで実行させる。「Gemini で直して」「Hydrogen で読みやすくして」「natural-japanese を Gemini で」と頼まれたときに使う。モデルの指定がない推敲、新しく書く依頼、採点(score)は natural-japanese を使う。
argument-hint: "[対象ファイル] [補足の依頼]"
---

# natural-japanese-gemini

`natural-japanese` の手順を、自分ではなく Gemini に実行させる。Orca の中で動いているときだけ使える。worker は lint から書き直し、事実の確認までを自分で行い、結果を報告してくる。最後の確認は呼び出したあなたが行う。

文書は Antigravity を通して Google に送られる。社外に出せない文書には使わない。

## 起動

```bash
skills/natural-japanese-gemini/scripts/start-worker.sh --out <直した文書> <元の文書>
```

- `--out` は必須で、元の文書とは別のファイルにする。worker が書き換えてよいのはこのファイルだけ
- `--note "<補足>"`: 読み手や目的、残したい箇所など、依頼者からの補足を worker に渡す
- モデルは `NATURAL_JAPANESE_GEMINI_MODEL` で変えられる(既定 `gemini-4-hydrogen-high`)。使える ID は `agy models` で確かめる

起動したら、そこでターンを終える。worker の完了は Orca が知らせてくるので、待ったり、端末を読みに行ったりしない。起動に失敗したときは、表示された内容だけに従い、自分で再実行しない(`orchestration` スキルと同じ)。

## 報告が届いたあと

worker の報告をそのまま信じず、次を確かめてから結果を渡す。

1. `uv run skills/natural-japanese/scripts/newfacts.py <元の文書> <直した文書>` を自分で実行する。元にない事実が出たら、削るか元の内容に戻す
2. 一覧が0件でも、元の文書と並べて、足された内容と確信の度合いの変化がないかを自分の目で確かめる
3. worker が残した指摘を直すかどうかは、`natural-japanese` の §3 と §4 に従って決める

直しを続けさせるときは、同じ worker に送る。

```bash
orca orchestration send --to dispatch:<dispatch_id> --subject "<件名>" --body "<直してほしい点>"
```
