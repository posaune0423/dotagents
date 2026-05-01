#!/usr/bin/env bash
# Links .agents/{skills,commands,rules} into .cursor, .claude, and .codex via symlinks,
# and creates CLAUDE.md -> AGENTS.md at repo root. Run from repository root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT"

err() {
	echo "init-agent: $*" >&2
	exit 1
}

require_source_dir() {
	local name="$1"
	local path=".agents/${name}"
	[[ -d "$path" ]] || err "missing source directory: ${path} (create it or run from repo root)"
}

symlink_agent_subdir() {
	local parent="$1"
	local sub="$2"
	local dest="${parent}/${sub}"
	local target="../.agents/${sub}"

	mkdir -p "$parent"

	if [[ -L "$dest" ]]; then
		local current
		current="$(readlink "$dest")"
		if [[ "$current" == "$target" ]]; then
			echo "ok: ${dest} -> ${target}"
			return 0
		fi
		err "${dest} is a symlink pointing to '${current}', expected '${target}'. Remove it and re-run."
	fi

	if [[ -e "$dest" ]]; then
		err "${dest} exists and is not a symlink (refusing to replace). Move or remove it, then re-run."
	fi

	ln -s "$target" "$dest"
	echo "created: ${dest} -> ${target}"
}

link_claude_md() {
	local agents="AGENTS.md"
	local claude="CLAUDE.md"
	[[ -f "$agents" ]] || err "missing ${agents} at repo root"

	if [[ -L "$claude" ]]; then
		local current
		current="$(readlink "$claude")"
		if [[ "$current" == "$agents" ]]; then
			echo "ok: ${claude} -> ${agents}"
			return 0
		fi
		err "${claude} is a symlink pointing to '${current}', expected '${agents}'. Remove it and re-run."
	fi

	if [[ -e "$claude" ]]; then
		err "${claude} exists and is not a symlink (refusing to replace). Move or remove it, then re-run."
	fi

	ln -s "$agents" "$claude"
	echo "created: ${claude} -> ${agents}"
}

for sub in skills commands rules; do
	require_source_dir "$sub"
done

for parent in .cursor .claude .codex; do
	for sub in skills commands rules; do
		symlink_agent_subdir "$parent" "$sub"
	done
done

link_claude_md

echo "init-agent: done (cwd: ${ROOT})"
