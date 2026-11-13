import assert from "node:assert/strict"
import { test } from "node:test"

import { accountIds, launchCommand, matchWorkspacePaths, parseResolution, workspacePath } from "./routing.js"

const RISE = {
  account: "rise",
  claude: "/Users/me/Library/Application Support/orca/claude-profiles/78c2e992/home",
  codex: "/Users/me/Library/Application Support/orca/codex-accounts/f60ee2c3/home",
}

test("parseResolution reads the resolver's key=value lines", () => {
  const out = `account=rise\nclaude=${RISE.claude}\ncodex=${RISE.codex}\n`
  assert.deepEqual(parseResolution(out), RISE)
  assert.deepEqual(parseResolution("account=partial\ncodex=/x=y\n"), { account: "partial", codex: "/x=y" })
  assert.equal(parseResolution(""), null)
})

test("workspacePath takes the path after the repo id", () => {
  assert.equal(
    workspacePath("16c434c6::/Users/me/orca/workspaces/myfans/be-2"),
    "/Users/me/orca/workspaces/myfans/be-2",
  )
  assert.equal(workspacePath("identity:wt2:local:622e89bf"), null)
  assert.equal(workspacePath(null), null)
})

test("launchCommand prefixes both directories so nested agents follow", () => {
  assert.equal(
    launchCommand("claude", "claude '--chrome'", RISE),
    `CLAUDE_CONFIG_DIR='${RISE.claude}' ORCA_CLAUDE_INJECTED_CONFIG_DIR= ` +
      `CODEX_HOME='${RISE.codex}' ORCA_CODEX_HOME='${RISE.codex}' claude '--chrome'`,
  )
  assert.equal(
    launchCommand("codex", "codex '-c' 'x=1'", { account: "p", codex: "/c" }),
    "CODEX_HOME='/c' ORCA_CODEX_HOME='/c' codex '-c' 'x=1'",
  )
})

test("launchCommand leaves other agents and empty resolutions alone", () => {
  assert.equal(launchCommand("opencode", "opencode", RISE), null)
  assert.equal(launchCommand("claude", "claude", null), null)
  assert.equal(launchCommand("claude", "claude", { account: "empty" }), null)
})

test("launchCommand refuses a directory it cannot quote", () => {
  assert.equal(launchCommand("claude", "claude", { account: "x", claude: "/it's" }), null)
})

test("accountIds maps Orca-managed directories to Orca account ids", () => {
  assert.deepEqual(accountIds(RISE), { claude: "78c2e992", codex: "f60ee2c3" })
  assert.deepEqual(accountIds({ account: "own", claude: "/Users/me/.claude", codex: RISE.codex }), {
    codex: "f60ee2c3",
  })
})

test("matchWorkspacePaths finds the focused workspace by name and branch", () => {
  const workspaces = [
    { name: "be-2", branch: "fix/a", path: "/w/myfans/be-2" },
    { name: "be-2", branch: "main", path: "/w/other/be-2" },
    { name: "docs", branch: "fix/a", path: "/w/docs" },
  ]
  assert.deepEqual(matchWorkspacePaths(workspaces, { displayName: "be-2", branch: "fix/a" }), ["/w/myfans/be-2"])
  assert.deepEqual(matchWorkspacePaths(workspaces, { displayName: "nope", branch: "fix/a" }), [])
  assert.deepEqual(matchWorkspacePaths(workspaces, null), [])
})
