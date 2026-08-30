#!/bin/bash
# PreToolUse(Bash) hook: enforce the user's branch naming and manual worktree
# placement policies.
#
# Contract (Claude Code):
#   stdin  {"tool_name":"Bash","tool_input":{"command":"..."}}
#   stdout deny decision as JSON, or nothing when the command is allowed
#
# Branch-name enforcement is creation-only. Switching to, inspecting,
# maintaining, and deleting an existing agent-prefixed branch all stay allowed;
# only bringing a new one into existence is refused. Manual worktree creation is
# allowed only below ./.worktrees/; host-managed creation bypasses this hook.
#
# Two classes of input must not be mistaken for a branch-creating command:
# heredoc bodies (a file being written may quote such a command as text) and
# commands that merely pass one along as an argument, such as `echo`. Both are
# handled below, and both are covered by scripts/tests/hooks.test.sh.
set -uo pipefail

BLOCKED_RE='^(claude|codex|gemini|cursor|copilot|devin|agent|ai)/'

input="$(cat)"

hook_error() {
	printf 'Git policy hook error: %s\n' "$1" >&2
	exit 2
}

command -v jq >/dev/null 2>&1 || hook_error "jq is required"
cmd="$(printf '%s' "$input" | jq -er '.tool_input.command | strings | select(length > 0)' 2>/dev/null)" ||
	hook_error "invalid hook JSON or missing command"

deny() {
	jq -cn --arg r "$1" '{
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason: $r
		}
	}'
	exit 0
}

# Trim surrounding whitespace without word-splitting.
trim() {
	local v="$1"
	v="${v#"${v%%[![:space:]]*}"}"
	printf '%s' "${v%"${v##*[![:space:]]}"}"
}

# A heredoc body is data the command writes, not commands the shell runs.
# Authoring a skill or a script that quotes a forbidden command must not read as
# an attempt to run it.
strip_heredoc_bodies() {
	local line delim="" in_doc=0 out=""
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "$in_doc" -eq 1 ]; then
			if [ "$(trim "$line")" = "$delim" ]; then
				in_doc=0
			fi
			continue
		fi
		out="${out}${line}"$'\n'
		if [[ "$line" =~ \<\<-?[[:space:]]*[\'\"]?([A-Za-z_][A-Za-z0-9_]*)[\'\"]? ]]; then
			delim="${BASH_REMATCH[1]}"
			in_doc=1
		fi
	done
	printf '%s' "$out"
}

# Report the branch a segment would bring into existence, or print nothing.
# The caller has already stripped quote characters, so a quoted branch name
# arrives bare and the anchored prefix match still applies to it.
branch_name_from_segment() {
	local -a tok
	read -r -a tok <<<"$1" || return 0
	local i=0 n=${#tok[@]} sub="" arg

	# The command word must be git itself. Accepting a git token anywhere in the
	# segment would deny `echo git checkout -b claude/x`, which runs nothing.
	while [ "$i" -lt "$n" ]; do
		case "${tok[i]}" in
		env | command | exec | --) i=$((i + 1)) ;;
		[A-Za-z_]*=*) i=$((i + 1)) ;;
		git | */git) break ;;
		*) return 0 ;;
		esac
	done
	[ "$i" -lt "$n" ] || return 0
	i=$((i + 1))

	# Step over git's own global options to reach the subcommand.
	while [ "$i" -lt "$n" ]; do
		case "${tok[i]}" in
		-C | -c | --git-dir | --work-tree | --namespace)
			i=$((i + 2))
			;;
		-*)
			i=$((i + 1))
			;;
		*)
			sub="${tok[i]}"
			i=$((i + 1))
			break
			;;
		esac
	done
	[ -n "$sub" ] || return 0

	case "$sub" in
	checkout | switch)
		# Every creating option, in both its short and long spelling.
		while [ "$i" -lt "$n" ]; do
			case "${tok[i]}" in
			-b | -B | -c | -C | --create | --force-create | --orphan)
				[ $((i + 1)) -lt "$n" ] && printf '%s\n' "${tok[i + 1]}"
				return 0
				;;
			--create=* | --force-create=* | --orphan=*)
				printf '%s\n' "${tok[i]#*=}"
				return 0
				;;
			esac
			i=$((i + 1))
		done
		;;
	branch)
		# Read-only, upstream-maintenance, and delete forms create nothing. Each
		# option that takes a value has an `=value` spelling too; matching only
		# the space-separated one would deny ordinary maintenance of an existing
		# prefixed branch.
		for arg in "${tok[@]:i}"; do
			case "$arg" in
			-d | -D | --delete | -l | --list | -a | --all | -r | --remotes | \
				-v | --verbose | -u | --show-current | --unset-upstream | \
				--edit-description | -i | --ignore-case | --column | --no-column | \
				-h | --help | \
				--set-upstream-to | --set-upstream-to=* | --set-upstream | \
				--merged | --merged=* | --no-merged | --no-merged=* | \
				--contains | --contains=* | --no-contains | --no-contains=* | \
				--points-at | --points-at=* | --sort | --sort=* | \
				--format | --format=*)
				return 0
				;;
			esac
		done
		# A rename or a copy names its destination last; a plain create names it
		# first. Reading the first operand of a copy would pick up the source.
		for arg in "${tok[@]:i}"; do
			case "$arg" in
			-m | -M | --move | -c | -C | --copy)
				printf '%s\n' "${tok[n - 1]}"
				return 0
				;;
			esac
		done
		for arg in "${tok[@]:i}"; do
			case "$arg" in
			-*) ;;
			*)
				printf '%s\n' "$arg"
				return 0
				;;
			esac
		done
		;;
	worktree)
		[ "${tok[i]:-}" = "add" ] || return 0
		while [ "$i" -lt "$n" ]; do
			case "${tok[i]}" in
			-b | -B)
				[ $((i + 1)) -lt "$n" ] && printf '%s\n' "${tok[i + 1]}"
				return 0
				;;
			esac
			i=$((i + 1))
		done
		;;
	push)
		branch_names_from_push "${tok[@]:i}"
		;;
	esac
	return 0
}

# Report the destination of `git worktree add`, or print nothing for any other
# command. Host-managed worktree creation does not pass through this Bash hook;
# this only constrains manual shell creation.
worktree_path_from_segment() {
	local -a tok
	read -r -a tok <<<"$1" || return 0
	local i=0 n=${#tok[@]} sub="" arg

	while [ "$i" -lt "$n" ]; do
		case "${tok[i]}" in
		env | command | exec | --) i=$((i + 1)) ;;
		[A-Za-z_]*=*) i=$((i + 1)) ;;
		git | */git) break ;;
		*) return 0 ;;
		esac
	done
	[ "$i" -lt "$n" ] || return 0
	i=$((i + 1))

	while [ "$i" -lt "$n" ]; do
		case "${tok[i]}" in
		-C | -c | --git-dir | --work-tree | --namespace)
			i=$((i + 2))
			;;
		-*) i=$((i + 1)) ;;
		*)
			sub="${tok[i]}"
			i=$((i + 1))
			break
			;;
		esac
	done
	[ "$sub" = "worktree" ] && [ "${tok[i]:-}" = "add" ] || return 0
	i=$((i + 1))

	while [ "$i" -lt "$n" ]; do
		arg="${tok[i]}"
		case "$arg" in
		-b | -B | --reason)
			i=$((i + 2))
			;;
		--)
			i=$((i + 1))
			[ "$i" -lt "$n" ] && printf '%s\n' "${tok[i]}"
			return 0
			;;
		--reason=* | -*) i=$((i + 1)) ;;
		*)
			printf '%s\n' "$arg"
			return 0
			;;
		esac
	done
}

# Print the destination branch of every refspec a push would create. Deleting a
# remote branch is allowed, in both the --delete and the empty-source spelling.
branch_names_from_push() {
	local -a rest=("$@")
	local j=0 m=${#rest[@]} seen_remote=0 arg dst

	for arg in "${rest[@]}"; do
		case "$arg" in
		-d | --delete) return 0 ;;
		esac
	done

	while [ "$j" -lt "$m" ]; do
		arg="${rest[j]}"
		case "$arg" in
		-o | --push-option | --repo | --receive-pack | --exec | --signed | --force-with-lease)
			j=$((j + 2))
			continue
			;;
		-*)
			j=$((j + 1))
			continue
			;;
		esac
		if [ "$seen_remote" -eq 0 ]; then
			# The first operand is the remote, not a refspec.
			seen_remote=1
			j=$((j + 1))
			continue
		fi
		# An empty source deletes the destination rather than creating it.
		case "$arg" in
		:*)
			j=$((j + 1))
			continue
			;;
		esac
		dst="${arg#+}"
		dst="${dst##*:}"
		dst="${dst#refs/heads/}"
		[ -n "$dst" ] && printf '%s\n' "$dst"
		j=$((j + 1))
	done
}

# Shell operators separate independent commands; check each one. Quote
# characters are dropped so a quoted branch name is compared bare.
segments="$(printf '%s' "$cmd" | strip_heredoc_bodies |
	sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|]/\n/g' -e 's/["'"'"']//g')"

segment_count=0
while IFS= read -r candidate; do
	[ -n "$(trim "$candidate")" ] && segment_count=$((segment_count + 1))
done <<<"$segments"
compound_command=0
[ "$segment_count" -gt 1 ] && compound_command=1

check_segment() {
	local seg="$1" name worktree_path inner
	[ -n "$seg" ] || return 0
	if [[ "$seg" =~ (^|[[:space:]])worktree[[:space:]]+add([[:space:]]|$) ]]; then
		case "$seg" in
		*\$\(* | *\`*) deny "Command substitution around git worktree creation is blocked." ;;
		esac
		if [[ "$(trim "$seg")" =~ ^(rg|echo|printf)[[:space:]]*\(\) ]]; then
			deny "Shell functions that wrap git worktree creation are blocked."
		fi
	fi
	if [ "$compound_command" -eq 1 ] && [[ "$seg" =~ (^|[[:space:]])worktree[[:space:]]+add([[:space:]]|$) ]]; then
		case "$(trim "$seg")" in
		rg\ * | echo\ * | printf\ * | git\ commit\ *) ;;
		*) deny "Manual worktree creation must run as a standalone literal command from the repository root." ;;
		esac
	fi
	while IFS= read -r name; do
		[ -n "$name" ] || continue
		case "$name" in
		*'$'* | *'`'* | *\\*)
			deny "Dynamic branch names are blocked because the hook cannot verify the expanded value. Use a literal compliant branch name."
			;;
		esac
		if printf '%s' "$name" | grep -qE "$BLOCKED_RE"; then
			deny "Branch name \"${name}\" is prefixed with an agent or tool name, which this user's global convention forbids. Use the repository's existing convention, or Git Flow: feature/<short-kebab-case>, fix/<...>, release/<...>, hotfix/<...>. Rerun with a compliant name."
		fi
	done <<<"$(branch_name_from_segment "$seg")"

	worktree_path="$(worktree_path_from_segment "$seg")"
	if [[ "$seg" =~ (^|[[:space:]])([^[:space:]]*/)?git[[:space:]]+-C[[:space:]].*worktree[[:space:]]+add([[:space:]]|$) ]]; then
		deny "Manual worktree creation through git -C is blocked because the hook cannot verify the effective destination. Run the command from the repository root."
	fi
	if [ -n "$worktree_path" ]; then
		if [ "$compound_command" -eq 1 ]; then
			deny "Manual worktree creation must run as a standalone command from the repository root."
		fi
		worktree_path="${worktree_path#./}"
		case "$worktree_path" in
		*'$'* | *'`'* | *\\*)
			deny "Dynamic worktree paths are blocked because the hook cannot verify the expanded destination. Use a literal ./.worktrees/<name> path."
			;;
		esac
		case "/${worktree_path}/" in
		*/../*)
			deny "Manual worktrees must stay inside the current repository at ./.worktrees/<name>. Do not create sibling, parent, /tmp, or other external worktree directories. Use the host's managed worktree feature when available."
			;;
		esac
		case "$worktree_path" in
		.worktrees/*)
			git check-ignore -q -- "$worktree_path" 2>/dev/null ||
				deny "Manual worktrees require a repository-ignored ./.worktrees/ directory. Add it to the repository ignore rules or use the host's managed worktree feature."
			;;
		*)
			deny "Manual worktrees must stay inside the current repository at ./.worktrees/<name>. Do not create sibling, parent, /tmp, or other external worktree directories. Use the host's managed worktree feature when available."
			;;
		esac
	elif [[ "$seg" =~ (^|[[:space:]])worktree[[:space:]]+add([[:space:]]|$) ]]; then
		case "$(trim "$seg")" in
		eval\ * | \$\(* | \`*)
			deny "Indirect git worktree creation is blocked. Use a literal git worktree add ./.worktrees/<name> command."
			;;
		*) ;;
		esac
	fi

	if [[ "$seg" =~ ^[[:space:]]*(bash|zsh|sh|fish)[[:space:]]+-[^[:space:]]*c[[:space:]]+(.+)$ ]]; then
		inner="${BASH_REMATCH[2]}"
		check_segment "$inner"
	fi
}

while IFS= read -r seg; do
	check_segment "$seg"
done <<<"$segments"

exit 0
