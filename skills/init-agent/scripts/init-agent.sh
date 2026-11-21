#!/usr/bin/env bash
# Scaffolds missing project files (AGENTS.md, docs/) from the skill's templates, links
# .agents/{skills,commands,rules} into .cursor, .claude, and .codex, and creates
# CLAUDE.md -> AGENTS.md. Existing files are never overwritten.
# Usage: init-agent.sh [--links-only] [project-root]   (default root: current directory)
set -euo pipefail

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/templates" && pwd)"
scaffold=1
root="."
while [[ $# -gt 0 ]]; do
	case "$1" in
	--links-only) scaffold=0 ;;
	-h | --help)
		echo "Usage: init-agent.sh [--links-only] [project-root]"
		exit 0
		;;
	-*)
		echo "init-agent: unknown option: $1" >&2
		exit 1
		;;
	*) root="$1" ;;
	esac
	shift
done

ROOT="$(cd "$root" && pwd)"
cd "$ROOT"

err() {
	echo "init-agent: $*" >&2
	exit 1
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

# Copy each template whose destination does not exist yet; keep everything else.
scaffold_files() {
	local template rel
	while IFS= read -r -d '' template; do
		rel="${template#"${TEMPLATES}/"}"
		if [[ -e "$rel" || -L "$rel" ]]; then
			echo "kept: ${rel}"
			continue
		fi
		mkdir -p "$(dirname "$rel")"
		cp "$template" "$rel"
		echo "created: ${rel}"
	done < <(find "$TEMPLATES" -type f -print0 | sort -z)
}

[[ "$scaffold" -eq 0 ]] || scaffold_files

for sub in skills commands rules; do
	mkdir -p ".agents/${sub}"
done

for parent in .cursor .claude .codex; do
	for sub in skills commands rules; do
		symlink_agent_subdir "$parent" "$sub"
	done
done

link_claude_md

echo "init-agent: done (cwd: ${ROOT})"
