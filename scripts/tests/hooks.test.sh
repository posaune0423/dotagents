#!/usr/bin/env bash
# Integration tests for the Claude Code git-policy hook in claude/hooks.
# shellcheck disable=SC2016 # Literal shell snippets intentionally contain unexpanded variables.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${ROOT}/claude/hooks/block-agent-branch-prefix.sh"
CODEX_HOOK="${ROOT}/codex/hooks/block-git-policy.sh"

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

assert_hook_error() {
	local input="$1" expected="$2" out rc
	set +e
	out="$(printf '%s' "${input}" | bash "${HOOK}" 2>&1)"
	rc=$?
	set -e
	if [[ "${rc}" -ne 2 || "${out}" != *"${expected}"* ]]; then
		fail_msg "expected hook error rc=2 containing '${expected}', got rc=${rc}: ${out}"
		return
	fi
	pass=$((pass + 1))
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

if [[ ! -x "${CODEX_HOOK}" ]]; then
	fail_msg "Codex PreToolUse git-policy hook is missing or not executable: ${CODEX_HOOK}"
else
	out="$(jq -cn --arg c 'git worktree add ../wt' '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}' | bash "${CODEX_HOOK}")"
	if [[ "${out}" != *'"deny"'* ]]; then
		fail_msg "Codex PreToolUse hook must deny project-external worktrees"
	else
		pass=$((pass + 1))
	fi
fi

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
assert_allowed 'git push origin feature/x'

# --- worktree placement ------------------------------------------------------
# Manual worktrees must remain inside the repository-local .worktrees area.
# Host-managed worktrees (for example Codex Desktop) bypass this Bash hook and
# continue to use the host's own standard directory.
assert_denied 'git worktree add ../wt'
assert_denied 'git worktree add /tmp/wt'
assert_denied 'git worktree add /Users/asumayamada/ghq/github.com/example/repo-feature'
assert_denied 'git -C /some/repo worktree add -b feature/x ../repo-x main'
assert_denied 'git worktree add .worktrees/../repo-feature'
assert_denied 'env -- git worktree add ../outside'
assert_denied 'command -- git worktree add ../outside'
assert_denied 'p=../../outside; git worktree add .worktrees/$p'
assert_denied "git worktree add .worktrees/\$(printf '../../outside')"
assert_denied "bash -c 'git worktree add ../outside'"
assert_denied "eval 'git worktree add ../outside'"
assert_denied "\$(printf git) worktree add ../outside"
assert_denied 'branch=claude/foo; git checkout -b "$branch"'
assert_denied 'git worktree add .worktrees/.\./.\./outside'
assert_denied 'git checkout -b clau\de/foo'
assert_denied 'cd scripts && git worktree add .worktrees/review'
assert_denied 'git -C scripts worktree add .worktrees/review'
assert_denied '/usr/bin/git -C scripts worktree add .worktrees/review'
assert_denied 'builtin cd scripts && git worktree add .worktrees/review'
assert_denied 'pushd scripts && git worktree add .worktrees/review'
assert_denied 'f(){ git worktree add ../outside; }; f'
assert_denied 'rg "$(git worktree add ../outside)" .'
assert_denied 'rg () { git worktree add ../outside; }; rg'
assert_allowed 'git worktree add .worktrees/review'
assert_allowed 'git worktree add -b feature/x ./.worktrees/feature-x main'
assert_allowed 'git worktree add --detach .worktrees/review HEAD'

git check-ignore -q .worktrees/review || fail_msg '.worktrees/ must be ignored by the repository'
assert_hook_error '{not-json' 'invalid hook JSON'

set +e
missing_jq_output="$(PATH=/nonexistent /bin/bash "${HOOK}" <<<'{"tool_name":"Bash","tool_input":{"command":"git status"}}' 2>&1)"
missing_jq_rc=$?
set -e
if [[ "${missing_jq_rc}" -ne 2 || "${missing_jq_output}" != *'jq is required'* ]]; then
	fail_msg "missing jq must fail closed with rc=2"
else
	pass=$((pass + 1))
fi

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
assert_allowed 'echo git worktree add ../outside'
assert_allowed 'printf "%s" "git switch -c codex/bar"'
assert_allowed "rg 'git worktree add' ."
assert_allowed "rg 'git worktree add' . && echo checked"
assert_allowed "git commit -m 'document worktree add policy'"

# Authoring a file whose contents mention a forbidden command is not running it.
# Without heredoc stripping this hook blocks its own test suite.
assert_allowed "$(printf 'cat > doc.md <<%s\ngit checkout -b claude/foo\nEOF\n' "'EOF'")"
assert_allowed "$(printf 'cat > s.sh <<-%s\n\tgit switch -c codex/bar\n\tEOF\n' "'EOF'")"

if [[ "${fail}" -ne 0 ]]; then
	echo "FAIL: ${fail} case(s) failed, ${pass} passed" >&2
	exit 1
fi
echo "PASS: ${pass} git-policy hook case(s)"
