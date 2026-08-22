---
name: safe-dev-storage-cleanup
description: Safely remove verified merged-PR worktrees and old dangling Docker cache or images. Use for scheduled local development-storage maintenance; skip anything active or uncertain.
---

Mac上の開発用ストレージを安全にcleanupし、日本語で結果を報告してください。対象は、merge済みPull Requestから作られた不要なGit worktreeと、再生成可能な古いDocker build cache・dangling imageだけです。

このタスクは、以下の安全条件をすべて満たす対象だけを自動削除することを許可されています。条件が1つでも確認できない場合や、コマンドが失敗した場合は削除せず、理由付きでskipしてください。ディスク空きが少なくても安全条件を緩和しないでください。

## 共通安全ルール

- `rm`、`rm -rf`、`trash`、Finder操作、`sudo`、force deleteを使わないでください。
- Gitリポジトリ本体、main checkout、branch、tag、remote、stash、commit、未追跡ファイルを削除しないでください。
- `.codex`、`.claude`、session履歴、SQLite DB、memory、credential、設定ファイルを削除・移動・変更しないでください。
- Docker volume、container、network、tag付きimageを削除しないでください。
- `docker system prune`、`docker container prune`、`docker volume prune`、`docker network prune`、`docker image prune -a`、`docker builder prune -a` は禁止です。
- 実行中・使用中・dirty・未push・unmerged・判定不能なものは必ず保持してください。
- Git worktreeの判定・lock管理・削除は、後述するGit管理済みscriptだけに任せてください。scriptをコピー、改変、迂回したり、agent自身でworktreeを削除したりしないでください。
- 許可される通常の書き込みは、state directoryのlockとレポート、および後述するGit管理済みscriptとDockerコマンドによるcleanupだけです。

## 1. Preflight

1. `df -k /` と `docker system df` を読み取り専用で実行し、cleanup前の空き容量とDocker使用量を記録してください。Dockerが起動していない場合はDocker部分だけskipしてください。
2. `ghq root` と `ghq list -p` が利用できることを確認し、`ghq list -p` が返すmain checkoutだけをGit調査の起点にしてください。ホーム全体を再帰走査してリポジトリを推測しないでください。
3. state directoryの `latest.json` があれば前回結果を読み、同じworktreeを連続して判定不能にしている場合も勝手に安全扱いへ昇格させないでください。

## 2. Git worktree cleanup

worktree cleanupは次のversion管理済みscriptだけで実行してください。

```bash
/Users/asumayamada/ghq/github.com/posaune0423/dotagents/schedules/safe-dev-storage-cleanup/scripts/cleanup-worktrees.sh --execute
```

scriptが見つからない、実行権限がない、または失敗した場合は、agent自身で代替コマンドを組み立てずGit cleanup全体をskipしてください。scriptは `ghq list -p` が返すmain checkoutだけを起点とし、main checkout自身を除くlinked worktreeについて以下をすべて確認します。

1. worktreeが`locked`ではなく、detached HEADでもなく、ローカルbranchが判別できる。
2. `git status --porcelain --untracked-files=all --ignore-submodules=none` が完全に空で、変更・未追跡ファイル・submodule変更がない。加えて `git ls-files --others --ignored --exclude-standard -z` も完全に空で、ignored fileが1件もない。
3. `git fetch --prune origin` が成功し、`origin/HEAD`からdefault branchを一意に解決できる。fetchまたはdefault branch解決に失敗したrepoはskipする。
4. worktreeのHEADがremote default branchの到達可能な履歴に含まれることを、`git merge-base --is-ancestor HEAD <remote-default-branch>` で確認する。
5. upstreamが存在する場合は、upstreamより先行したcommitが0件である。upstreamが無い場合も、前項とPR確認の両方を満たさなければskipする。
6. `gh repo view` でoriginに対応する `owner/repo` を確定し、`gh pr list -R <owner/repo> --head <branch> --state merged --json number,mergedAt,headRefName,headRefOid,headRepository,headRepositoryOwner,baseRefName,url` でPRを1件だけ取得できる。`headRefOid`が現在のworktree HEADと完全一致し、head repository、branch、base branchも現在のrepoと一致し、mergeから72時間以上経過している。どれかが一致しない場合はskipする。
7. `lsof +D <worktree-path>` でworktree配下を開いているprocessが1件もない。権限エラーや判定エラーも「使用中の可能性あり」としてskipする。
8. worktree配下のファイル・ディレクトリに過去72時間以内の更新がない。判定できない場合はskipする。
9. 対象pathが `git worktree list --porcelain` から得たcanonicalな絶対pathと完全一致し、`/`、`/Users/asumayamada`、`ghq root`、main checkout、main checkout内、またはそれらの親ではない。

scriptは全条件を満たした候補だけ `git worktree remove <exact-absolute-worktree-path>` で削除します。`--force`、`git worktree prune`、手動ディレクトリ削除、branch削除は実行しません。判定と結果はstate directoryの `worktrees-latest.json` に保存されます。

## 3. Docker cleanup

Docker cleanupも次のversion管理済みscriptだけで実行してください。

```bash
/Users/asumayamada/ghq/github.com/posaune0423/dotagents/schedules/safe-dev-storage-cleanup/scripts/cleanup-docker.sh --execute
```

scriptが見つからない、実行権限がない、または失敗した場合は、agent自身で代替pruneコマンドを実行せずDocker cleanup全体をskipしてください。scriptはowner metadata付きの専用lockを管理し、次を確認・実行します。

- `docker info` が成功し、ユーザーが開始した `docker build`、`docker buildx build`、`buildctl` が実行中でない場合だけ続行する。実行中または判定不能ならDocker cleanup全体をskipする。
- cleanup前の `docker system df -v` と全containerの参照imageを記録する。
- `docker builder prune --filter "until=168h" --force` と `docker image prune --filter "until=168h" --force` だけを実行する。
- `--all`を付けず、7日以上前のdangling build cacheと、どのcontainerからも参照されない7日以上前のdangling imageだけを対象にする。
- 片方が失敗しても範囲を広げず、`system`、container、volume、network、tag付きimage、Docker Desktop VM disk、`Docker.raw`には触れない。
- 判定と結果をstate directoryの `docker-latest.json` に保存する。

## 4. 検証とレポート

cleanup後に `df -k /`、`docker system df`、各対象repoの `git worktree list --porcelain` を再取得し、削除した対象が消え、保持対象が残っていることを確認してください。

`/Users/asumayamada/.local/state/dotagents/safe-dev-storage-cleanup/` に次を保存してください。

- `YYYY-MM-DD.json`: 今回の実行結果
- `latest.json`: 今回の結果で安全に更新

JSONには開始・終了日時、cleanup前後の空き容量、解放できた容量、削除したworktree、削除したDocker build cache・imageの件数と容量、skipした候補と理由、実行したコマンドとexit statusを記録してください。credentialやファイル内容は記録しないでください。

最終回答は次の順で短く報告してください。

1. 判定: cleanup実施、対象なし、または安全条件によりskip
2. 解放容量: 合計、Git worktree、Docker
3. 削除した対象
4. 保持・skipした対象と理由
5. cleanup前後のディスク空き容量
6. エラーまたは追加確認が必要な点
