---
name: natural-japanese-gemini
description: 既存の日本語文書の推敲を、natural-japanese スキルの規則のまま Gemini(既定は Gemini 4 Neon)に書かせる。「Gemini で直して」「Neon で読みやすくして」「natural-japanese を Gemini で」と頼まれたときに使う。モデルの指定がない推敲、新しく書く依頼、採点(score)は natural-japanese を使う。
argument-hint: "[対象ファイル] [補足の依頼]"
---

# natural-japanese-gemini

`natural-japanese` の書き直しだけを Gemini に任せる。検出(lint)と、元にない事実の洗い出し(newfacts)は手元で実行し、最後の確認は呼び出したあなたが行う。

文書の全文が Gemini API に送られる。社外に出せない文書には使わない。

## 実行

```bash
skills/natural-japanese-gemini/scripts/rewrite.sh --out <直した文書> <元の文書>
```

- `--out` を省くと、直した文書を標準出力に出す。元の文書は書き換えない。`--out` に元の文書は指定できない
- `--genre business|essay|tech`: lint の基準を文書の種類に合わせる
- `--note "<補足>"`: 読み手や目的など、依頼者からの補足をモデルに渡す
- `GEMINI_API_KEY` が必要。モデルは `NATURAL_JAPANESE_GEMINI_MODEL` で変えられる(既定 `gemini-4-neon`)
- 1回に数分かかる。待ち時間の上限は `NATURAL_JAPANESE_GEMINI_TIMEOUT` 秒(既定 900)

API のエラーや、出力が途中で切れたときは、非ゼロで終了し、直した文書は出さない。

## 実行したあと

標準エラーに、次の2つが出る。どちらも読んでから結果を渡す。

1. `newfacts.py` の一覧。直した文書にだけある数値・固有名詞・英字の語。元にない事実なら、削るか元の内容に戻す
2. 直した文書への `lint.py` の結果。残った指摘を直すかどうかは、`natural-japanese` の §3 と §4 に従って決める

一覧が0件でも、元の文書と並べて、足された内容と確信の度合いの変化がないかを自分の目で確かめる。Gemini は自分の出力を検査していない。

残った指摘をもう一度 Gemini に直させるときは、直した文書を入力にして再実行する。そのときも、事実の確認は最初の元の文書と比べる。

```bash
uv run skills/natural-japanese/scripts/newfacts.py <最初の元の文書> <最終版>
```
