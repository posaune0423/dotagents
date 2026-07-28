#!/usr/bin/env bash
# Materialises the PR's merge-base in a throwaway worktree so the "before" UI can be served.
set -euo pipefail

repo_root=""
base_ref=""
worktree=""
install_command=""
share_node_modules=1
remove=0

usage() {
	cat <<'USAGE'
Usage: base-worktree.sh [--repo-root <path>] [--base-ref <ref>] [options]
       base-worktree.sh --remove [--repo-root <path>] [--worktree <path>]

  --repo-root <path>       Repo to branch from (default: current repo).
  --base-ref <ref>         Base branch (default: the PR's baseRefName, else origin/HEAD).
  --worktree <path>        Where to place it (default: $TMPDIR/pr-ui-screenshot/<repo>-base).
  --install <cmd>          Dependency install command, run only when the lockfile differs.
  --no-share-node-modules  Always install instead of symlinking the parent's node_modules.
  --remove                 Delete the worktree and exit.

Prints the worktree path on stdout. The parent repo's working tree is never touched:
the worktree is detached at the merge-base and lives outside the repo.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--repo-root)
		repo_root="${2:-}"
		shift 2
		;;
	--base-ref)
		base_ref="${2:-}"
		shift 2
		;;
	--worktree)
		worktree="${2:-}"
		shift 2
		;;
	--install)
		install_command="${2:-}"
		shift 2
		;;
	--no-share-node-modules)
		share_node_modules=0
		shift
		;;
	--remove)
		remove=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown arg: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

if [[ -z "$repo_root" ]]; then
	repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$repo_root" || ! -d "$repo_root" ]]; then
	echo "Could not determine repo root. Use --repo-root <path>." >&2
	exit 1
fi

if [[ -z "$worktree" ]]; then
	worktree="${TMPDIR:-/tmp}/pr-ui-screenshot/$(basename "$repo_root")-base"
fi

if [[ "$remove" -eq 1 ]]; then
	if [[ -d "$worktree" ]]; then
		# Drop the symlink first so `git worktree remove` never walks into shared deps.
		[[ -L "${worktree}/node_modules" ]] && rm -f "${worktree}/node_modules"
		git -C "$repo_root" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
	fi
	git -C "$repo_root" worktree prune
	echo "Removed ${worktree}."
	exit 0
fi

if [[ -z "$base_ref" ]]; then
	base_ref="$(cd "$repo_root" && gh pr view --json baseRefName --jq .baseRefName 2>/dev/null || true)"
	if [[ -n "$base_ref" ]]; then
		base_ref="origin/${base_ref}"
	else
		base_ref="$(git -C "$repo_root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
	fi
fi

if ! git -C "$repo_root" rev-parse --verify --quiet "$base_ref" >/dev/null; then
	echo "Base ref not found: ${base_ref}. Run 'git fetch origin' first." >&2
	exit 1
fi

merge_base="$(git -C "$repo_root" merge-base "$base_ref" HEAD)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
if [[ "$merge_base" == "$head_sha" ]]; then
	echo "HEAD is the merge-base with ${base_ref}: there is no diff to compare against." >&2
	exit 1
fi

echo "Base ref: ${base_ref}" >&2
echo "Merge-base: ${merge_base}" >&2

mkdir -p "$(dirname "$worktree")"
if [[ -d "${worktree}/.git" || -f "${worktree}/.git" ]]; then
	current="$(git -C "$worktree" rev-parse HEAD 2>/dev/null || true)"
	if [[ "$current" != "$merge_base" ]]; then
		echo "Reusing worktree, moving ${current:-?} -> ${merge_base}" >&2
		git -C "$worktree" checkout --detach --force "$merge_base"
		git -C "$worktree" clean -fd -e node_modules -e .next >/dev/null
	else
		echo "Reusing worktree already at ${merge_base}" >&2
	fi
else
	rm -rf "$worktree"
	git -C "$repo_root" worktree add --detach --force "$worktree" "$merge_base" >&2
fi

lockfiles=(pnpm-lock.yaml package-lock.json yarn.lock bun.lock bun.lockb)
lock_changed=0
for lock in "${lockfiles[@]}"; do
	if [[ -f "${repo_root}/${lock}" || -f "${worktree}/${lock}" ]]; then
		if ! cmp -s "${repo_root}/${lock}" "${worktree}/${lock}" 2>/dev/null; then
			lock_changed=1
			echo "Lockfile differs between HEAD and merge-base: ${lock}" >&2
		fi
	fi
done

if [[ -e "${worktree}/node_modules" && ! -L "${worktree}/node_modules" ]]; then
	echo "Worktree has its own node_modules; leaving it alone." >&2
elif [[ "$share_node_modules" -eq 1 && "$lock_changed" -eq 0 && -d "${repo_root}/node_modules" ]]; then
	ln -sfn "${repo_root}/node_modules" "${worktree}/node_modules"
	echo "Symlinked node_modules from the parent checkout (lockfile is unchanged)." >&2
elif [[ -n "$install_command" ]]; then
	echo "Installing dependencies in the worktree: ${install_command}" >&2
	(cd "$worktree" && eval "$install_command") >&2
else
	echo "! No node_modules in the worktree and no --install command given." >&2
	echo "! The base dev server will probably fail to start." >&2
fi

echo "$worktree"
