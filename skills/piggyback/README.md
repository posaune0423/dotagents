# piggyback — 構造と越境

契約は [SKILL.md](SKILL.md) / [SKILL-ja.md](SKILL-ja.md) にある。ここは**何がどの境界を越えるか**を図で押さえるための補足。

境界は3つある。取り違えると事故になるのはこの3つだけで、他は実装の詳細である。

1. **contextの境界** — 呼び出し元の会話は、どのプロバイダにも渡らない
2. **マシンの境界** — promptは**このマシンから出る**。無料枠は入力を学習に使う権利を留保しているのが普通
3. **capabilityの境界** — ファイルに触れるのは `agentic` だけ。`inference` は物理的にディスクを読めない

## 全体構成

routerはプロバイダ名を一切ハードコードしない。知っているのはadapterの3verb契約と終了コード契約だけで、だから新しいプロバイダは `providers/` にファイルを1つ置けば増える。

```mermaid
classDiagram
    class Router {
        <<entrypoint>>
        +capability: inference|agentic
        +chain: ordered provider names
        +maxFailures: int
        +route(prompt) Answer
        -satisfies(have, need) bool
        -skipIfCoolingDown(provider) bool
    }

    class ProviderAdapter {
        <<interface>>
        +capabilities() "agentic"|"inference"
        +probe() ExitCode
        +run(promptFile, write, model, workspace, timeout) Answer
    }

    class Common {
        <<library>>
        +EXIT_OK/QUOTA/AUTH/MISSING/TIMEOUT/NO_ROUTE
        +classifyFailure(stderr) Bucket
        +classifyExit(stderr) ExitCode
        +runWithTimeout(sec, cmd)
        +cooldownSet(provider, exit, retryAfter)
        +cooldownActive(provider) bool
        +loadEnvFile()
        +openaiChat(baseUrl, key, model, promptFile)
    }

    class OpenAiTemplate {
        <<mixin>>
        +BASE_URL
        +KEY_VAR
        +DEFAULT_MODEL
        +main(args)
    }

    Router ..> ProviderAdapter : ファイル名で発見
    Router ..> Common : 分類・cooldown
    ProviderAdapter ..> Common

    ProviderAdapter <|.. Antigravity : agentic
    ProviderAdapter <|.. Cursor : agentic
    ProviderAdapter <|.. Copilot : agentic
    ProviderAdapter <|.. Groq : inference
    ProviderAdapter <|.. OpenRouter : inference
    ProviderAdapter <|.. Mistral : inference

    Groq ..|> OpenAiTemplate
    OpenRouter ..|> OpenAiTemplate
    Mistral ..|> OpenAiTemplate
    OpenAiTemplate ..> Common : openaiChat
```

`agentic` の3つはそれぞれ固有のCLIを叩くので個別実装。`inference` の3つはOpenAI互換なので、テンプレートに変数4つを渡すだけの薄いファイルになっている。

## 越境するもの、しないもの

一番効くのはこの図。**破線が越えてはいけない/越える境界**である。

```mermaid
flowchart TB
    subgraph HOST["呼び出し元 (Claude Code / Codex)"]
        CTX["会話のcontext<br/>過去のやりとり・方針・判断"]
        TASK["自己完結したprompt<br/>目的・対象・完了条件を全部含む"]
        CTX -.->|"越えない<br/>プロバイダは会話を見ない"| TASK
    end

    subgraph LOCAL["このマシン"]
        ROUTER["piggyback.sh<br/>チェーンを歩く"]
        ENV[(".env<br/>APIキー")]
        COOL[("cooldown state<br/>~/.local/state/piggyback")]
        FS[("ワークスペース<br/>ソースコード")]
        ROUTER --> COOL
        ENV -.->|"Authorizationヘッダのみ<br/>promptには載せない"| ROUTER
    end

    subgraph CLOUD["外部プロバイダ"]
        INF["inference<br/>groq / openrouter / mistral"]
        AGT["agentic<br/>antigravity / cursor / copilot"]
    end

    TASK --> ROUTER
    ROUTER -->|"prompt本文<br/>マシンの外へ出る"| INF
    ROUTER -->|"prompt本文<br/>マシンの外へ出る"| AGT
    INF -->|"テキストのみ"| ROUTER
    AGT -->|"テキスト + 副作用"| ROUTER

    AGT -->|"読み取りは常時<br/>書き込みは --write のときだけ"| FS
    INF -.->|"到達しない<br/>ディスクを読めない"| FS

    ROUTER -->|"回答だけ"| HOST
```

読み取るべき点は3つ。

- **会話のcontextは越えない。** だからpromptは自己完結していなければならない。「さっき話したバグ」は向こうには存在しない
- **prompt本文はマシンの外に出る。** secret・認証情報・`.env` の中身を載せないのはこのため。keyそのものはAuthorizationヘッダに載るだけで、prompt本文には入らない
- **`inference` はファイルシステムに到達しない。** これは運用上の約束ではなく構造的な事実であり、だから編集タスクをinferenceに流すのが危険（「やっていない編集をやったと報告する」）であり、routerが手前で弾いている

## 状態モデル

cooldownと設定の関係。「なぜあるプロバイダが飛ばされたのか」はこの関係だけで説明できる。

```mermaid
erDiagram
    PROFILE ||--|| CAPABILITY : "宣言する"
    PROFILE ||--|{ CHAIN_ENTRY : "順序付きで持つ"
    CHAIN_ENTRY }o--|| PROVIDER : "指す"
    CHAIN_ENTRY |o--o| MODEL : "省略時はproviderの既定"
    CHAIN ||--|{ PROVIDER : "順序付きで含む"
    PROVIDER ||--|| ADAPTER : "1ファイルで実装される"
    PROVIDER ||--|| CAPABILITY : "宣言する"
    PROVIDER |o--o| CREDENTIAL : "必要とすることがある"
    PROVIDER |o--o| COOLDOWN : "一時的に外されることがある"
    PROVIDER ||--o{ RUN : "試行される"
    RUN ||--|| OUTCOME : "終了コードを返す"
    OUTCOME |o--o| COOLDOWN : "可用性の問題なら書き込む"

    CHAIN {
        string capability "inference or agentic"
        string order "既定 or --profile or --chain"
    }
    PROFILE {
        string name PK "fast, reasoning, long-context, code, review"
        string source "profiles.conf"
    }
    CHAIN_ENTRY {
        string spec "provider または provider=model"
    }
    MODEL {
        string id "コロンとスラッシュを含みうる"
    }
    PROVIDER {
        string name PK "ファイル名と一致"
    }
    ADAPTER {
        string path PK "providers/<name>.sh"
        string verbs "capabilities|probe|run"
    }
    CAPABILITY {
        string kind "agentic superset of inference"
    }
    CREDENTIAL {
        string env_var "GROQ_API_KEY など"
        string source ".env または export 済みの環境変数"
    }
    COOLDOWN {
        int expires_at PK "epoch秒"
        string reason "quota|auth|missing|timeout"
    }
    OUTCOME {
        int exit_code "0,1,2,3,4,5,6"
        string bucket "stale-model|auth|quota|unavailable|failed"
    }
```

`CHAIN_ENTRY` から `MODEL` が**省略可能**なのが要点の1つである。モデルを書かなければproviderの既定が使われる——CursorのFreeプランは名前付きモデルを全部拒否するので、そこではこれが唯一動く形になる。

`OUTCOME` から `COOLDOWN` が**条件付き**なのが要点である。タスク失敗（`1`）ではcooldownを書かない。そのプロバイダの可用性には問題が無く、書いてしまうと別の仕事から見えなくなる。

## 1リクエストの流れ

枠切れで倒れ、cooldownが書かれ、次が応える。

```mermaid
sequenceDiagram
    participant Caller as 呼び出し元
    participant R as piggyback.sh
    participant S as cooldown state
    participant P1 as groq
    participant P2 as openrouter

    Caller->>R: --prompt '...'（inference）
    R->>S: groq は冷却中か？
    S-->>R: いいえ
    R->>P1: run --prompt-file
    P1-->>R: exit 3 + retry_after_seconds
    Note over R: 枠切れは異常ではない。<br/>次へ倒す理由である
    R->>S: cooldown書き込み（申告値を優先）
    R->>S: openrouter は冷却中か？
    S-->>R: いいえ
    R->>P2: run --prompt-file
    P2-->>R: exit 0 + 回答
    R-->>Caller: 回答 + "served by openrouter"

    Note over R,S: 全員が倒れた場合は exit 7。<br/>terminal であり、代わりに自分でやってはならない
```

最後のノートが運用上いちばん重要である。`7` を受けた側が黙って自分の枠で実行し直すと、**このskillを経由した意味が消える**。自分の予算を使う価値があるかは呼び出し元が決める。

## プロバイダを1つ足すとき

触るのは1ファイルだけ。routerもテストも変更しなくてよい。

```mermaid
flowchart LR
    A["providers/&lt;name&gt;.sh を置く"] --> B{"OpenAI互換API？"}
    B -->|はい| C["lib/openai_provider.sh を source<br/>変数4つを埋める"]
    B -->|いいえ| D["capabilities / probe / run を実装<br/>lib/common.sh の分類器を使う"]
    C --> E["チェーンに名前を足す"]
    D --> E
    E --> F["just test-piggyback<br/>providers/*.sh を回すループが<br/>契約を自動で検査する"]
```

`probe` は**枠を消費してはならない**という制約だけ守れば、あとは終了コード契約に従うだけである。
