---
name: xai-x-search
description: xAI (Grok) の x_search を使って、任意テーマのX/Web情報を横断調査し、根拠URL付きで結果を保存する汎用リサーチスキル。
disable-model-invocation: true
metadata:
  { "openclaw": { "emoji": "🔎", "requires": { "config": ["skills.entries.xai-x-search.enabled"], "bins": ["bun"] } } }
---

# xAI X Search

## Overview

xAI Responses API + `x_search` を直接使う汎用リサーチスキル。記事用途に限定せず、任意のテーマで「要点 + 根拠URL」を短時間で収集する。

## When To Use

- X上の最新論点や一次情報を素早く調べたい
- 新機能、競合、仕様変更、トレンドの横断リサーチをしたい
- 調査ログ（json/txt/md）を保存して後続作業に使いたい

## Input

- 調べたい内容（1文でOK）

不足時の質問:

- 「何を x_search で調べる？」

## Workflow

1. Query を確定
   調べたいテーマを1文で定義する。

2. Grok delegate
   次のコマンドで実行する。

- `bun skills/xai-x-search/scripts/xai_x_search.ts --query \"...\"`

主なオプション:

- `--locale ja|global`
- `--days 30`
- `--out-dir data/xai-x-search`
- `--dry-run`（API呼び出しなしでpayload確認）

3. 結果確認
   保存された `.md/.txt/.json` と標準出力を確認し、必要ならクエリを調整して再実行する。

## Output

`data/xai-x-search/` に以下を保存する。

- `YYYYMMDD_HHMMSSZ_<locale>_x_search.md`
- `YYYYMMDD_HHMMSSZ_<locale>_x_search.txt`
- `YYYYMMDD_HHMMSSZ_<locale>_x_search.json`

補足:

- 固定テンプレートへの整形は不要。モデル出力をそのまま保存する。
- 参照URLは必ず残す。

## Hand-off

- 調査結果をそのまま企画、仕様策定、記事執筆、検証タスクへ引き渡す。
