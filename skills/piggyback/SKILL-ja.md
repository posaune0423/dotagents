---
name: piggyback
description: >-
  別のagentのCLIへ、仕事に合ったモデルを選んでタスクを渡すための統一インターフェース。
  このセッション自身の枠を使わずに済ませる。モデルの選択は名前付きprofileが担う:
  機械的なテキスト処理は `fast`、強いモデルに値する分析は `reasoning`、収まらない
  入力は `long-context`、workspaceが要る作業は `code` と `review`。

  自分でやるのが高くつくか不可能なときに使う: このセッション自身の枠が尽きている
  か温存したい、絞り込んでもなお素材が大きい、独立した呼び出しが多数必要、
  といった場合。ユーザーが「Cursorで」「Antigravityで」「無料枠で」「軽い作業を
  安いところに回して」と言った場合にも使う。

  使う前に grep、sed、head で絞ること。構造化されたテキストでは、shellで絞って
  残りを自分で読むほうがプロバイダへの往復より速く、絞った残りは外に出す価値が
  無いほど小さくなるのが普通である。

  この会話の蓄積されたcontextが必要な作業、呼び出し元が持つべき判断、拒否の回避には
  使わない。プロバイダのチェーンが全滅するのは想定内の結果であり、迂回せず報告すること。
---

# Piggyback

他人の無料枠に相乗りする。自己完結したタスクを1件、まだ枠が残っているプロバイダへ渡す。

`scripts/piggyback.sh` が唯一の入口。順序付きのチェーンを歩き、枠切れのプロバイダを飛ばし、最初に返ってきた実際の回答を返す。プロバイダのCLIを直接叩かないこと: 下の終了コード契約だけが「枠切れ」と「認証切れ」と「本当の失敗」を確実に区別する手段であり、それを毎回エラー文から導き直すのが、このskillが防ごうとしている失敗そのものである。

## main agentがこれを使うべき場面

**答えを自分でレビューしたくなるような判断が要らない仕事**を出す。整形、抽出、要約、分類、文面の下書き。間違ったときの代償が大きく、しかも気づきにくい仕事は出さない。

capability classは2つの問いで決まり、たいてい1つ目で決着する。

**モデルが「いま見たものを踏まえて次に何を実行するか」を決める必要があるか。**
無いなら——コマンドが既に分かっているなら——実行は自分でやり、**解釈だけ**を出す。`just check` を走らせるためにエージェントを起動するのは、シェルで済む仕事にエージェントのオーバーヘッドを払っている。機械的な部分は決定論的で枠を消費しない。モデルが要るのは失敗の読解だけ:

```bash
just check 2>&1 | tail -200 >/tmp/out.txt
{ echo '次の失敗を formatter で直るものと本物の型エラーに分類して:'; cat /tmp/out.txt; } >/tmp/task.txt
skills/piggyback/scripts/piggyback.sh --prompt-file /tmp/task.txt
```

**本文をどちらのcontextが抱えるか。** promptをファイルで組み立てれば、ログは自分のcontextに一切入らない。節約されるのは「読む」分ではなく、**5,000行について考えなくて済む**分である。

既定は `inference`。agentic側は3プロバイダ合計で1日数十リクエスト、inference側は約1,000リクエスト。テキスト整形にagenticを1回使うことは、本当にファイルを編集させたいときに**唯一編集できる枠**を失うことを意味する。`agentic` を使うのは、workspaceが本当に必要なとき——コマンドを実行し、その出力が指すファイルを読み、そこで判断する——に限る。

入力は小さく保つ。Groqの無料枠は毎分8Kトークンなので、ログ全体を送らずに `grep` / `tail` で絞ってから渡すこと。

## ルーティングの実測

`scripts/eval-routing.sh` は、全プロバイダをスタブに差し替えた状態でhost agentを実際に走らせる。無料枠を1リクエストも消費せずに「ルーティングされたか」だけを測れる。Claude Code、6ケース、各1回:

| ケース                                 | 期待   | 実際   |
| -------------------------------------- | ------ | ------ |
| 「無料枠のプロバイダに投げて要約して」 | する   | した   |
| `just check` の失敗を仕分け            | する   | 揺れる |
| ログから未解決のエラーを抽出           | する   | しない |
| ログのERROR行を表に整形                | する   | しない |
| 直前の会話のcontextが必要              | しない | しない |
| 設計上の判断                           | しない | しない |

正直に読むこと: **自律的なルーティングはほぼ起きない。** 確実な起動条件はユーザーが明示的に依頼することだけである。同一条件の再実行で1ケースが反転したので、n=1ではdescriptionの文言差を判別できない。

negativeケースは一度も誤発火しなかった。守るべきはこちらの性質である。

より有用なのは、**使わなかった判断のほうが正しかった**点である。10行のログを渡したとき、エージェントは「10行なので直接読んで整形した」と述べた。1,229行のログでは `grep -n`、`grep -A1`、`sort | uniq -c` で16行のERRORまで絞り、それに対して推論した——本文はエージェントのcontextにも入っておらず、しかも答えはLLMの往復より正確だった。

つまり実際の適用範囲は「機械的なテキスト処理を外に出す」より狭い。shellツールが既に本文をcontextの外に保っており、しかも無料で即座で厳密である。このskillが価値を持つのは、その絞り込みが使えないか足りないとき——hostの枠が本当に尽きている、絞った後もなお大きい、独立した呼び出しが多数必要、ユーザーが明示的に依頼した——に限られる。

## profile: どの仕事にどのモデルか

安いモデル階層を手で選ぶ作業を置き換えるのがこの部分である。profileはモデルの判断に一度だけ名前を付ける。呼び出し側がプロバイダ固有のモデルIDを持ち歩かなくて済む:

```bash
skills/piggyback/scripts/piggyback.sh --profile fast --prompt '...'
skills/piggyback/scripts/piggyback.sh --list-profiles
```

| profile        | capability | 用途                                          |
| -------------- | ---------- | --------------------------------------------- |
| `fast`         | inference  | 仕分け、抽出、整形。最安で枠も最大            |
| `reasoning`    | inference  | 強いモデルに値する分析                        |
| `long-context` | inference  | 小さいcontextに収まらない入力（1Mトークン級） |
| `code`         | agentic    | コードを書く。workspaceが要る                 |
| `review`       | agentic    | コードに対する判断: レビュー、設計批評        |

profileは `profiles.conf` に1行1件で置く:

```text
name|capability|provider[=model],provider[=model],...
```

providerとmodelの区切りが `=` なのは、モデルIDにコロンとスラッシュが入るためである（`nvidia/nemotron-3.5-lightning:free`）。**provider名だけを書くとそのproviderの既定**を使う。CursorはこれでしかないFreeプランは名前付きモデルを全部拒否してAutoしか通さない。

profileの中でも通常の可用性フォールバックは効くので、profileは単一の選択ではなく優先順位である。明示的な `--model` はその1回に限りprofileより優先し、`--write` はprofileのcapabilityより優先する。

ロースターは予告なく変わる。`profiles.conf` を編集したら `--probe` を実行すること。リクエストを消費せずに、設定した既定をproviderのliveなモデル一覧と突き合わせる。

## 終了コード契約

adapterとrouterはこのコードだけを話す。

| コード | 意味                                     | ルーティングへの影響       |
| ------ | ---------------------------------------- | -------------------------- |
| `0`    | 成功                                     | 回答がstdoutにある         |
| `1`    | プロバイダがタスク自体に失敗             | 上限付きで次へ倒す（後述） |
| `2`    | 引数エラー                               | チェーンを止める           |
| `3`    | 枠またはrate limitの枯渇                 | 次のプロバイダへ倒す       |
| `4`    | 未認証 / keyなし / 使えるものが無い      | 倒す                       |
| `5`    | バイナリ・依存の不在、または古いモデルID | 倒す                       |
| `6`    | timeout、またはプロバイダ側の不調        | 倒す                       |
| `7`    | router: チェーンの誰も応えられなかった   | terminal                   |

`3`〜`6` は常に次へ倒す。`1` も倒すが `--max-failures`（既定2）までである。

この上限は妥協点である。実測で、あらゆる `1` で停止する設計が誤りだと分かった: `gemini-cli` が未知のtierエラーを返し、残り全プロバイダを巻き添えで止めた。routerは「タスクが悪い」と「このプロバイダが分類器の知らない壊れ方をしている」を確実には区別できないので、進み続ける——ただし本当に悪いpromptがチェーン全体を焼き尽くすほどには進まない。タスク失敗ではcooldownを書かない。そのプロバイダの可用性には何の問題も無いからである。

`7` はこのskillにとってterminal。**リトライしないこと。代わりに自分でやらないこと。** その仕事に自分の枠を使う価値があるかは呼び出し元が決める。

## 失敗の分類

プロバイダのstderrを大文字小文字を無視して1つのバケットに振り分ける。これは**終了コードが非ゼロのときだけ**走る: 内部リトライが成功する過程で "quota exhausted" を出力するCLIがあり、提供終了した gemini-cli がまさにそうだった。

| バケット      | コード | 実際に観測された例                                                                          |
| ------------- | ------ | ------------------------------------------------------------------------------------------- |
| `stale-model` | `5`    | `model_not_found` — GroqがLlama系chatモデルを予告なく落とした                               |
| `auth`        | `4`    | `IneligibleTierError`（提供終了したGeminiのtier）、`Named models unavailable`（プラン制限） |
| `quota`       | `3`    | `429`、`rate limit`、`you have hit your free requests limit`                                |
| `unavailable` | `6`    | `410 github_models_retirement_brownout`、`503`、`overloaded`                                |
| `failed`      | `1`    | それ以外 — タスクについての回答として扱う                                                   |

最初の4つはどれも「次へ進む理由」である。このいずれかが `failed` バケットに落ちるのがチェーンを詰まらせるバグなので、新しいパターンはadapterではなくここに足すこと。

## capability class

| class       | できること                                            | プロバイダ                   |
| ----------- | ----------------------------------------------------- | ---------------------------- |
| `agentic`   | workspaceを読み、ファイルを編集し、コマンドを実行する | antigravity, cursor, copilot |
| `inference` | テキスト入力・テキスト出力のみ                        | groq, openrouter, mistral    |

`agentic` ⊇ `inference`: agenticなプロバイダは質問にも答えられるが、逆は成り立たない。inference専用に編集タスクを渡してはならない。このgateはrouterが強制する。さもなければ**実際には行っていない作業を、行ったかのように自信を持って報告される**からである。

inference要求は意図的にinference専用を先に試す。agentic枠でも質問には答えられるが、Groqで足りる仕事に使えば、**ファイルを編集できる唯一の枠**を無駄にする。

## 手順

### 1. 何が使えるか確認する

```bash
skills/piggyback/scripts/piggyback.sh --probe
```

probeは推論リクエストを消費しない。どのadapterも認証情報か無料の `models` 一覧を見るだけで、completionは呼ばない。`--status` はcooldown表を出す。

### 2. 自己完結したpromptを書く

どのプロバイダもこの会話を見ていない。目的、作業ディレクトリ、対象ファイルやコマンド、編集の可否、完了条件をpromptが全部持つ必要がある。`inference` プロバイダにはコード本体も載せること。ディスクを読めない。

### 3. 実行する

```bash
skills/piggyback/scripts/piggyback.sh --prompt 'この差分を3行で要約して: ...'
```

agenticな読み取り専用:

```bash
skills/piggyback/scripts/piggyback.sh --capability agentic \
  --workspace /path/to/repo \
  --prompt 'src/auth/session.ts を読み、期限切れsessionを返しうる経路を全部挙げて。file:line を添えること。'
```

編集は、呼び出し元が明示的に書き込みを許可したときだけ:

```bash
skills/piggyback/scripts/piggyback.sh --write --workspace /path/to/repo \
  --prompt-file /tmp/task.md
```

### 4. 報告する

回答、どのプロバイダが応えたか、終了コードの意味を返す。

## オプション

| オプション                                      | 既定        | 備考                                                |
| ----------------------------------------------- | ----------- | --------------------------------------------------- |
| `--prompt` / `--prompt-file`                    | —           | タスク。どちらか必須                                |
| `--capability inference\|agentic`               | `inference` | workspaceに触るには `agentic` が要る                |
| `--write`                                       | off         | ファイル編集を許可。`--capability agentic` を含意   |
| `--provider <name>`                             | —           | 1つに固定し、倒さない                               |
| `--chain <a,b=model,c>`                         | 下記        | 順序を上書き。各entryにモデルを付けられる           |
| `--profile <name>`                              | —           | 名前付きの用途profileを使う。`--list-profiles` 参照 |
| `--model <id>`                                  | 未設定      | 通常は指定しない（後述）                            |
| `--workspace <path>`                            | cwd         | agenticプロバイダの作業ディレクトリ                 |
| `--timeout <seconds>`                           | `900`       | プロバイダ1件あたりの実時間上限                     |
| `--max-failures <n>`                            | `2`         | タスク失敗がこの回数に達したら諦める                |
| `--no-cooldown`                                 | off         | cooldownを無視し、書き込まない                      |
| `--json`                                        | off         | `{"provider":…,"exit":…,"answer":…}`                |
| `--probe` / `--status` / `--clear-cooldown [p]` | —           | 可用性、cooldown表、リセット                        |

既定のチェーン。`PIGGYBACK_CHAIN_INFERENCE`、`PIGGYBACK_CHAIN_AGENTIC`、`PIGGYBACK_CHAIN` で上書きできる:

```text
inference: groq, openrouter, mistral, antigravity, cursor, copilot
agentic:   antigravity, cursor, copilot
```

## 設定

プロバイダのkeyは `skills/piggyback/.env` に置く。リポジトリルートの `.gitignore` が既に除外している。exampleを複製して、持っているものだけ埋めればよい:

```bash
cp skills/piggyback/.env.example skills/piggyback/.env
```

このファイルはsourceせずパースする——設定ファイルであり、sourceすれば中身が何であれ実行してしまうからである。既にexportされている値が常に優先される。`PIGGYBACK_ENV_FILE` で別の場所を指せる。

未設定のものはそのプロバイダが `4` を返してrouterに飛ばされるだけなので、途中まで埋めた状態でも設定として成立する。

## cooldown

枠を使い切ったばかりのプロバイダは、次のタスクでも同じことを言う。cooldownが無いと、以降の全リクエストが**チェーンの死んだ区間を歩く時間**を払う。小さい無料枠を束ねるときの主なコストはこれである。

状態は `${XDG_STATE_HOME:-~/.local/state}/piggyback/<provider>.cooldown` に、プロバイダごと1つのepoch失効時刻として置かれる。既定は quota 1時間、auth 15分、missing 1時間、timeout 10分で、`PIGGYBACK_COOLDOWN_QUOTA` などで上書きできる。プロバイダ自身がbackoff秒数を申告した場合（OpenRouterは輻輳した無料モデルで `retry_after_seconds` を返す）はそちらを優先する。5秒の詰まりで1時間チェーンから外すべきではない。

日次リセットより意図的に短くしてある: 推測が外れても無駄なprobeが1回増えるだけだが、cooldownが長すぎると復活したプロバイダが黙って消える。

## Antigravityが Gemini CLI を置き換えた

`gemini-cli` はもうプロバイダではない。Gemini Code Assistの個人向けOAuth tierは提供終了し、`IneligibleTierError: This client is no longer supported ... migrate to the Antigravity suite` を返すようになった。`agy` CLIがその移行先であり、そもそも設計上も良い: `agy models` はリクエストを消費しない本物の可用性チェックで、geminiのadapterはディスク上の認証情報から推測するしかなかった。

罠が1つある: `agy --print` はpromptを**値として**取る。素で渡すとagyは後続のフラグをpromptとして飲み込み、別の質問に答えてしまうので、adapterは常に `--print=<prompt>` の形で書く。

## Cursorでは `--model` が粘着する

`cursor-agent` は `--model` をローカル設定ではなく**アカウント側に永続化する**。名前付きモデルで1回呼ぶと、その選択が以降の全実行に、どのクライアントからでも引き継がれる。Freeプランではこれが罠になる: 名前付きモデルは `ActionRequiredError: Named models unavailable. Free plans can only use Auto` で拒否されるため、1回の実験でそのプロバイダが以降ずっと失敗し続ける。

そのためadapterはフラグを省略せず、毎回 `--model auto` を送る。各呼び出しが自己完結し、他のクライアントが残した選択も直る。実測: 名前付きモデルを渡したら以降の全実行が壊れ、明示的な `auto` で復旧した。

## `--model` を通常は指定しない理由

各adapterには、その無料枠が実際に公開しているものに合わせた既定がある。`cursor-agent models` はFreeアカウントでも200以上のIDを並べる——Opus 5、GPT-5.6、Gemini 3.1 Pro——が、この一覧は名目上のものである。gateは実行時にかかり、名前付きは全部拒否される。Freeプランが通せるのはAutoだけである。

プロバイダのモデル一覧は予告なく変わるので、`probe` は設定された既定をliveの `/models` 一覧と突き合わせる。実行時に1リクエスト払って気づくより安い。Groqの現在のchatモデルは `openai/gpt-oss-20b`（既定）、`openai/gpt-oss-120b`、`qwen/qwen3.8-27b`。

OpenRouterはもう少し注意が要る。`:free` モデルは上流プールを共有しているので、一覧に載っていても `429 upstream_provider_shared_pool` と `retry_after_seconds: 5` を返すことがある——枠の枯渇ではなく輻輳である。routerは固定の1時間ではなくこの数値に従う。一覧に載っていても使えないものもあり、アクセスエラーを返す。既定は `nvidia/nemotron-3.5-lightning:free` で、動作確認済み。

## プロバイダを追加する

ここが拡張点である。プロバイダとは `scripts/providers/<name>.sh` に置かれた、3つのverbを実装した実行ファイル1つである:

```bash
<adapter> capabilities              # 'agentic' か 'inference' を出力
<adapter> probe                     # 0=利用可、3/4/5=不可。枠を消費しないこと
<adapter> run --prompt-file <path> [--write] [--model <id>] [--workspace <path>] [--timeout <n>]
                                    # 回答をstdoutへ、終了コードは契約どおり
```

routerはadapterをファイル名で発見し、プロバイダ名を一切ハードコードしないので、ファイルを置いてチェーンに名前を足すだけで完結する。

OpenAIのchat-completions形式を話すものなら本体は書いてある——adapterは変数4つで済む:

```bash
PROVIDER=example
PIGGYBACK_BASE_URL="${PIGGYBACK_EXAMPLE_BASE_URL:-https://api.example.com/v1}"
PIGGYBACK_KEY_VAR="EXAMPLE_API_KEY"
PIGGYBACK_DEFAULT_MODEL="${PIGGYBACK_EXAMPLE_MODEL:-example-small}"

source "${HERE}/../lib/openai_provider.sh"
piggyback_openai_provider_main "$@"
```

`lib/common.sh` が終了コード、失敗分類器、timeout監視、cooldown状態、`piggyback_openai_chat` を提供する。**分類は必ず非ゼロ終了時だけ**行うこと: 内部リトライが成功する過程で "quota exhausted" を出すCLIがある。

追加したら `scripts/tests/piggyback.test.sh` を拡張する。`providers/*.sh` を回すループが、置かれている全adapterに対して契約を既に検査している。

## 制約

- プロバイダのCLIを直接呼ばない。必ずrouterを通す
- 呼び出し元がこのタスクで明示的に編集を許可していない限り `--write` を渡さない。`--write` はagenticなプロバイダに、このhostの権限系の外でファイル編集とシェル実行を許す
- secret、認証情報、`.env` の中身をpromptに入れない。**このマシンから出る**し、無料枠は入力を学習に使う権利を留保しているのが普通である
- `7` をリトライしない。1タスク、チェーン1周
- 入力は小さく。無料枠には毎分のトークン上限がある

## プロバイダの設定

2026-09-01にliveエンドポイントで確認。

| プロバイダ  | 無料枠                                                        | 設定                                                   | 状態         |
| ----------- | ------------------------------------------------------------- | ------------------------------------------------------ | ------------ |
| groq        | 30/分、約1,000/日、8Kトークン/分                              | console.groq.com の `GROQ_API_KEY`                     | **往復確認** |
| openrouter  | 20/分、`:free` で50/日                                        | `OPENROUTER_API_KEY`。`:free` は入れ替わるのでIDを固定 | **往復確認** |
| mistral     | 無料Experiment tier、上限非公開                               | `MISTRAL_API_KEY`                                      | **往復確認** |
| antigravity | Gemini Flash/Pro、Claude Sonnet/Opus 4.6、GPT-OSS。上限非公開 | `agy login`                                            | **往復確認** |
| cursor      | Freeプラン、Autoモデルのみ                                    | `cursor-agent login`                                   | **往復確認** |
| copilot     | 50/月                                                         | `npm i -g @github/copilot` のあと `copilot` を1回実行  | **往復確認** |

## 削除したプロバイダ

2つのadapterは、失敗したまま残さず削除した。どちらも復活しないからである:

- **gemini-cli** — Gemini Code Assistの個人向けOAuth tierが提供終了。`IneligibleTierError` でAntigravityを案内してくるので、ここではAntigravityが置き換えた
- **GitHub Models** — 2026-07-30に完全終了。playground、model catalog、inference API、BYOKエンドポイントが全顧客に対して消えた。いまも `410 github_models_retirement_brownout` を返すが、この文言は残骸である: brownoutは7月16日と23日の予行であり、これは恒久停止のほうである。GitHubはMicrosoft FoundryかCopilotを案内している

死んだプロバイダをチェーンに残すのは無害ではない。cooldownが切れるたびに、同じことを知るために往復を1回払う。

## このskillの対象外

ローカルのモデルサーバーはここでのプロバイダではない。枠は消費しないが、マシン自身のCPUと熱の予算を消費する。それらは別種の予算であり、トレードオフも違う——ラップトップのファンに黙って倒れるチェーンは、他人の無料枠に倒れるチェーンと同じ約束ではない。ローカル推論は別に設定する。このリポジトリでは既に `codex/agents/qwen_worker.toml` が担当している。

未設定のものは `4` か `5` を返して飛ばされるので、途中まで設定したチェーンは、設定済みのメンバーが許す範囲でそのまま動く。
