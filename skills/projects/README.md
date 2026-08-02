# skills/projects — プロジェクト専用スキルの置き場

**特定のプロジェクトでだけ使う skill で、まだ team に共有していない（＝そのプロジェクトの
リポジトリに commit していない）もの**を置く。

`skills/` 直下は「どのプロジェクトでも使える共有 skill」の SSoT なので、
特定リポジトリの事情（channel ID、社内 URL、そのリポジトリの devDependency 依存など）が
埋まっているものはここに隔離する。

## git 管理

**中身は `.gitignore` 対象**。この README だけ tracked にしてディレクトリと意図を残している
（そのため `.gitkeep` は置いていない）。手元でだけ使い、共有はしない。

## 構成

```text
skills/
├── projects/
│   ├── README.md                        ← これ（tracked）
│   └── <repo名>/
│       └── <skill名>/
│           ├── SKILL.md
│           └── scripts/…
└── <skill名> -> projects/<repo名>/<skill名>   ← symlink（必須）
```

### symlink が必須な理由

skill 探索は **`skills/<name>/SKILL.md` の 1 階層しか見ない**。`projects/` の下に置いただけでは
認識されないので、`skills/<skill名>` から symlink を張る。

実測（`claude -p` で確認）:

| 配置                                            | 認識 |
| ----------------------------------------------- | ---- |
| `skills/<name>/SKILL.md`                        | ✅   |
| `skills/projects/<repo>/<name>/SKILL.md`        | ❌   |
| `skills/<name>` → `projects/<repo>/<name>`      | ✅   |

## 追加手順

1. 実体を `skills/projects/<repo名>/<skill名>/` に作る
2. `ln -sfn projects/<repo名>/<skill名> skills/<skill名>` で symlink を張る
3. ルートの `.gitignore` に symlink の行（`/skills/<skill名>`）を足す
   — バケット側（`/skills/projects/*`）は既に ignore 済み

## 依存パッケージ

ここの skill は node_modules を持たない。npm パッケージが要る場合は、**作業中のリポジトリの
devDependency を cwd 起点で借りる**実装にして、解決できないときは何を cwd にすべきか
エラーメッセージで示すこと。

## team に共有する段になったら

- **そのプロジェクト固有のまま共有する**: プロジェクト側リポジトリの `.claude/skills/` に移して
  commit する。dotagents からは実体と symlink を消す
- **どのプロジェクトでも使える形に一般化する**: `skills/<skill名>/` に実体を移し、
  `.gitignore` の symlink の行を消して commit する
