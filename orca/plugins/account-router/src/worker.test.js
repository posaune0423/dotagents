// Runs the worker as Orca would, with stub resolver and Orca CLI scripts in place of the real ones.
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { assert, mockHost, mountWorker, test } from "orca/testing"

import * as main from "./worker.js"

const CLIENT_CLAUDE = "/x/orca/claude-profiles/client-id/home"
const CLIENT_CODEX = "/x/orca/codex-accounts/team-id/home"

function stubs() {
  const dir = mkdtempSync(join(tmpdir(), "account-router-"))
  const resolver = join(dir, "resolver.sh")
  const cli = join(dir, "orca")
  const log = join(dir, "cli.log")
  // Routes any path containing /widget/ to client, everything else to nothing.
  writeFileSync(
    resolver,
    `#!/bin/sh
case "$2" in */widget/*) printf 'account=client\\nclaude=${CLIENT_CLAUDE}\\ncodex=${CLIENT_CODEX}\\n' ;; esac
`,
  )
  const failFlag = join(dir, "fail")
  // Fails while the flag file exists, so a test can simulate `orca account select` erroring.
  writeFileSync(cli, `#!/bin/sh\n[ -e "${failFlag}" ] && exit 1\necho "$*" >> "${log}"\n`)
  chmodSync(resolver, 0o755)
  chmodSync(cli, 0o755)
  process.env.AGENT_ACCOUNT_RESOLVER = resolver
  process.env.AGENT_ACCOUNT_ORCA_CLI = cli
  const calls = () => {
    try {
      return readFileSync(log, "utf8").trim().split("\n")
    } catch {
      return []
    }
  }
  const failCli = on => (on ? writeFileSync(failFlag, "") : rmSync(failFlag, { force: true }))
  return { calls, failCli, cleanup: () => rmSync(dir, { recursive: true, force: true }) }
}

const launch = (agent, workspaceId, command) => ({
  agent,
  workspaceId,
  workspaceKind: "worktree",
  command,
  env: {},
})

test("prefixes the routed account onto agent launches in a mapped workspace", async () => {
  const { cleanup } = stubs()
  const worker = await mountWorker(main, { hooks: ["agent.launch.before"] })
  const event = launch("claude", "repo::/w/widget/be-2", "claude '--chrome'")
  assert.deepEqual(await worker.hooks.fire("agent.launch.before", event), {
    kind: "continue",
    event: {
      ...event,
      command:
        `CLAUDE_CONFIG_DIR='${CLIENT_CLAUDE}' ORCA_CLAUDE_INJECTED_CONFIG_DIR= ` +
        `CODEX_HOME='${CLIENT_CODEX}' ORCA_CODEX_HOME='${CLIENT_CODEX}' claude '--chrome'`,
    },
  })
  await worker.deactivate()
  cleanup()
})

test("passes launches it cannot route unchanged", async () => {
  const { cleanup } = stubs()
  const worker = await mountWorker(main, { hooks: ["agent.launch.before"] })
  for (const event of [
    launch("claude", "repo::/w/personal/app", "claude"),
    launch("claude", null, "claude"),
    launch("opencode", "repo::/w/widget/be-2", "opencode"),
  ]) {
    const result = await worker.hooks.fire("agent.launch.before", event)
    assert.equal(result.kind, "continue")
    assert.equal(result.event.command, event.command)
  }
  await worker.deactivate()
  cleanup()
})

test("selects the focused workspace's Orca accounts once per workspace", async () => {
  const { calls, cleanup } = stubs()
  const host = mockHost({
    capabilities: ["workspace:read"],
    results: {
      "workspace.list": {
        truncated: false,
        workspaces: [
          { id: "a", kind: "worktree", name: "be-2", branch: "fix/a", path: "/w/widget/be-2", hostId: null },
          { id: "b", kind: "worktree", name: "app", branch: "main", path: "/w/personal/app", hostId: null },
        ],
      },
    },
  })
  const worker = await mountWorker(main, { host, events: ["workspace.changed"] })
  const focus = (displayName, branch, terminals = []) =>
    worker.emit("workspace.changed", { context: { displayName, branch, terminals } })

  await focus("be-2", "fix/a")
  await focus("be-2", "fix/a", [{ id: "t1" }])
  await focus("app", "main")
  assert.deepEqual(calls(), [
    "account select --agent claude --account client-id --json",
    "account select --agent codex --account team-id --json",
  ])
  await worker.deactivate()
  cleanup()
})

test("retries the selection for the same workspace after a failed select", async () => {
  const { calls, failCli, cleanup } = stubs()
  const host = mockHost({
    capabilities: ["workspace:read"],
    results: {
      "workspace.list": {
        truncated: false,
        workspaces: [
          { id: "a", kind: "worktree", name: "be-2", branch: "fix/a", path: "/w/widget/be-2", hostId: null },
        ],
      },
    },
  })
  const worker = await mountWorker(main, { host, events: ["workspace.changed"] })
  const focus = () =>
    worker.emit("workspace.changed", { context: { displayName: "be-2", branch: "fix/a", terminals: [] } })

  failCli(true)
  await focus()
  assert.deepEqual(calls(), [])
  failCli(false)
  await focus()
  assert.deepEqual(calls(), [
    "account select --agent claude --account client-id --json",
    "account select --agent codex --account team-id --json",
  ])
  await worker.deactivate()
  cleanup()
})
