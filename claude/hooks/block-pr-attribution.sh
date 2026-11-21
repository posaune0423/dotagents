#!/bin/bash
# PreToolUse(Bash) hook: refuse to create or edit a pull request whose body
# carries the "Generated with Claude Code" footer.
#
# Contract (Claude Code):
#   stdin  {"tool_name":"Bash","tool_input":{"command":"..."}}
#   stdout deny decision as JSON, or nothing when the command is allowed
#
# settings.json `attribution.pr: ""` stops Claude Code from asking for the
# footer, but the model still copies it from earlier PR bodies in the same
# session. This hook catches that copy, whether the body is inline, a heredoc,
# or a --body-file / --file / --input / -F path.
set -uo pipefail

FOOTER_RE='Generated with \[?Claude Code\]?|claude\.com/claude-code'

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

# Only PR bodies are in scope: `gh pr create|edit`, REST calls on pulls, and the
# create-pr helpers that run gh themselves. `gh` must be the command being run
# (line start or after ; & | ( plus optional VAR=value prefixes), so a commit
# message or grep pattern that merely mentions it is not mistaken for one.
GH_RE='(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*gh[[:space:]]+(pr[[:space:]]+(create|edit)|api[^|;&]*/pulls)'
HELPER_RE='(gh-pr-create-with-meta|pr-body-update)\.sh'
printf '%s' "$cmd" | grep -qE "$GH_RE|$HELPER_RE" || exit 0

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

reason='The PR body contains the "🤖 Generated with [Claude Code](...)" footer, which this user does not want in PRs. Remove that line (and any blank line left before it) and rerun.'

printf '%s' "$cmd" | grep -qE "$FOOTER_RE" && deny "$reason"

# Bodies passed by file are checked through the file's contents.
while IFS= read -r path; do
	[ -n "$path" ] || continue
	[ "$path" = "-" ] && continue
	[ -f "$path" ] && grep -qE "$FOOTER_RE" "$path" && deny "$reason"
done <<<"$(printf '%s' "$cmd" | grep -oE '(--body-file|--file|--input|-F)[= ]+[^[:space:];|&]+' | sed -E 's/^(--body-file|--file|--input|-F)[= ]+//; s/^["'"'"']//; s/["'"'"']$//; s/^[A-Za-z_]+=@//')"

exit 0
