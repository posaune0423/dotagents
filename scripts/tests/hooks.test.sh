#!/usr/bin/env bash
# Integration tests for the Claude Code hook scripts in claude/hooks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${ROOT}/claude/hooks/block-agent-branch-prefix.sh"

pass=0
fail=0

fail_msg() {
	echo "FAIL: $*" >&2
	fail=$((fail + 1))
}

# Feed one Bash tool call through the hook and print whatever it decides.
run_hook() {
	jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "${HOOK}"
}

# A blocked command must produce a well-formed PreToolUse deny decision.
assert_denied() {
	local out
	out="$(run_hook "$1")"
	if [[ "${out}" != *'"deny"'* ]]; then
		fail_msg "expected deny: $1"
		return
	fi
	if ! jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' <<<"${out}" >/dev/null; then
		fail_msg "deny payload missing PreToolUse event name: $1"
		return
	fi
	pass=$((pass + 1))
}

# Anything else must pass through silently. A false positive is worse than a
# miss here, because it blocks legitimate work with no way around it.
assert_allowed() {
	local out
	out="$(run_hook "$1")"
	if [[ -n "${out}" ]]; then
		fail_msg "expected no decision: $1 (got: ${out})"
		return
	fi
	pass=$((pass + 1))
}

[[ -x "${HOOK}" ]] || {
	echo "FAIL: hook is missing or not executable: ${HOOK}" >&2
	exit 1
}

# --- creation, short options -------------------------------------------------
assert_denied 'git checkout -b claude/foo'
assert_denied 'git checkout -b claude/foo main'
assert_denied 'git switch -c codex/bar'
assert_denied 'git switch -C gemini/baz'
assert_denied 'git checkout -B cursor/x'
assert_denied 'git branch copilot/y'
assert_denied 'git branch devin/y'
assert_denied 'git branch ai/experiment'
assert_denied 'git worktree add ../wt -b claude/z'
assert_denied 'git worktree add -b agent/z ../wt'
assert_denied 'git branch -m claude/renamed'
assert_denied 'git -C /some/repo checkout -b claude/foo'
assert_denied 'git status && git checkout -b claude/foo'
assert_denied 'cd /tmp && git checkout -b claude/foo'

# --- creation, long and orphan options ---------------------------------------
# git spells every creating option two ways; recognizing only the short form
# leaves the long one as a silent bypass.
assert_denied 'git switch --create claude/foo'
assert_denied 'git switch --force-create claude/foo'
assert_denied 'git switch --orphan claude/foo'
assert_denied 'git checkout --orphan claude/foo'
assert_denied 'git worktree add -B claude/z ../wt'

# --- creation by copy --------------------------------------------------------
# A copy names its destination last, exactly like a rename; reading the first
# operand instead picks up the source branch and lets the new one through.
assert_denied 'git branch -c main claude/foo'
assert_denied 'git branch -C main claude/foo'
assert_denied 'git branch --copy main claude/foo'

# --- creation through quoting ------------------------------------------------
assert_denied 'git checkout -b "claude/foo"'
assert_denied "git checkout -b 'claude/foo'"
assert_denied 'git branch "claude/foo"'

# --- creation of a remote branch ---------------------------------------------
# Pushing a new agent-prefixed branch is the same mistake one step later, and
# git accepts several spellings shorter than the fully expanded refspec.
assert_denied 'git push origin claude/foo'
assert_denied 'git push origin HEAD:claude/foo'
assert_denied 'git push origin HEAD:refs/heads/claude/foo'
assert_denied 'git push -u origin claude/foo'
assert_denied 'git push --set-upstream origin claude/foo'
assert_denied 'git push origin +claude/foo'
assert_denied 'git push origin main:claude/foo'

# --- compliant names ---------------------------------------------------------
assert_allowed 'git checkout -b feature/browser-tools'
assert_allowed 'git switch -c fix/login-crash'
assert_allowed 'git switch --create fix/login-crash'
assert_allowed 'git checkout -b release/1.2.0'
assert_allowed 'git checkout -b hotfix/prod-500'
assert_allowed 'git worktree add ../wt'
assert_allowed 'git push origin feature/x'

# --- operating on an existing agent-prefixed branch --------------------------
# The policy is creation-only: switching to, inspecting, maintaining, and
# deleting an already-existing prefixed branch all stay allowed.
assert_allowed 'git checkout claude/browser-tool-options-918797'
assert_allowed 'git switch claude/browser-tool-options-918797'
assert_allowed 'git branch -d claude/old-branch'
assert_allowed 'git branch -D claude/old-branch'
assert_allowed 'git push origin --delete claude/old-branch'
assert_allowed 'git push origin :claude/old-branch'
assert_allowed 'git branch --set-upstream-to=origin/main claude/foo'
assert_allowed 'git branch --set-upstream-to origin/main claude/foo'
assert_allowed 'git branch --unset-upstream claude/foo'

# --- inspection --------------------------------------------------------------
assert_allowed 'git branch --list'
assert_allowed 'git branch -a'
assert_allowed 'git branch --show-current'
assert_allowed 'git branch --contains=HEAD'
assert_allowed 'git branch --sort=-committerdate'
assert_allowed 'git log --oneline claude/foo'

# --- commands that only mention a forbidden branch as text -------------------
assert_allowed 'git commit -m "align with claude/foo docs"'
assert_allowed 'rg "claude/agents" .'
assert_allowed 'echo hello'
assert_allowed 'echo git checkout -b claude/foo'
assert_allowed 'printf "%s" "git switch -c codex/bar"'

# Authoring a file whose contents mention a forbidden command is not running it.
# Without heredoc stripping this hook blocks its own test suite.
assert_allowed "$(printf 'cat > doc.md <<%s\ngit checkout -b claude/foo\nEOF\n' "'EOF'")"
assert_allowed "$(printf 'cat > s.sh <<-%s\n\tgit switch -c codex/bar\n\tEOF\n' "'EOF'")"

branch_pass="${pass}"

# --- PR attribution footer ---------------------------------------------------
HOOK="${ROOT}/claude/hooks/block-pr-attribution.sh"
[[ -x "${HOOK}" ]] || {
	echo "FAIL: hook is missing or not executable: ${HOOK}" >&2
	exit 1
}
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
footer='🤖 Generated with [Claude Code](https://claude.com/claude-code)'
printf '## Why\n\nFix.\n\n%s\n' "${footer}" >"${TMP}/attributed.md"
printf '## Why\n\nFix.\n' >"${TMP}/clean.md"

assert_denied "gh pr create --title t --body \"Fix.

${footer}\""
assert_denied "cd repo && gh pr edit 1 --body \"${footer}\""
assert_denied "GH_REPO=o/r gh pr create --body \"${footer}\""
assert_denied "gh pr create --title t --body-file ${TMP}/attributed.md"
assert_denied "gh api repos/o/r/pulls/1 -X PATCH -F body=@${TMP}/attributed.md -f title=t --input ${TMP}/attributed.md"
# create-pr helpers run gh themselves, so the command never contains `gh pr create`.
assert_denied "bash skills/create-pr/scripts/gh-pr-create-with-meta.sh --title t --body-file ${TMP}/attributed.md"
assert_denied "bash skills/create-pr/scripts/pr-body-update.sh --pr 1 --file ${TMP}/attributed.md"

assert_allowed "gh pr create --title t --body-file ${TMP}/clean.md"
assert_allowed "bash skills/create-pr/scripts/pr-body-update.sh --pr 1 --file ${TMP}/clean.md"
# Text that only mentions the command and the footer is not a PR body.
assert_allowed "git commit -m \"Block gh pr create when the body has ${footer}\""
assert_allowed "rg 'Generated with Claude Code' claude/hooks"

if [[ "${fail}" -ne 0 ]]; then
	echo "FAIL: ${fail} case(s) failed, ${pass} passed" >&2
	exit 1
fi
echo "PASS: ${branch_pass} branch-name hook case(s), $((pass - branch_pass)) PR attribution hook case(s)"
