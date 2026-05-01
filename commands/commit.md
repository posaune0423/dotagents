### Command: Commit current changes in logical groups (simple)

Do exactly this, non-interactively, from repo root.

1. Ignore when staging:
   - Follow .gitignore strictly. Additionally, ignore: .cursor/\*\* (except this file), .env

2. Define groups and scopes:
   - infra → config/**, composer.\* , package.json, vite.config.js, docker/**, docker-compose.yml
   - routes → routes/\*\*
   - controllers → app/Http/\*\*
   - models → app/Models/\*\*
   - views → resources/views/\*\*
   - frontend → resources/js/**, resources/css/**
   - migrations → database/migrations/\*\*
   - tests → tests/\*\*

3. For each group that has changes, stage and commit (by intent/responsibility, not only folder):
   - Decide values:
     - ${emoji}:{fix=🐛, feat=✨, docs=📝, style=💄, refactor=♻️, perf=🚀, test=💚, chore=🍱}
     - ${type} in {fix, feat, docs, style, refactor, perf, test, chore}
     - ${scope} = group name (e.g., routes|controllers|models|views|infra|frontend|migrations|tests)
     - ${summary} = 1-line imperative (<=72 chars)
     - ${body} = 1–3 bullets (optional)
   - Commands:
     - git add -A -- ${file1} ${file2} ${fileN}
     - git commit -m "${emoji} ${type}(${scope}): ${summary}" -m "${body}"
     - （フックや署名を意図的に外す場合のみ）`SKIP_HOOKS=1` など明示フラグを付けた手順に切り替え、`--no-verify` / `--no-gpg-sign` はそのときだけ付与する

4. Commit order: chore → docs → style → refactor → perf → feat → fix → test

5. Final check:
   - git -c core.pager=cat status --porcelain=v1 | cat

Message template:
Title: "${emoji} ${type}(${scope}): ${summary}"
Body: "- ${changes}\n- ${reasonImpact}"

Example:
git add -A -- routes/admin.php app/Http/Controllers/Admin/UserController.php
git commit -m "✨ feat(routes): 管理画面ユーザー一覧を追加" -m "- 新規ルートとindex実装\n- 権限チェックを追加"
