// Routes Claude Code and Codex to the account mapped for each repository owner.
//
// - agent.launch.before: terminal launches get CLAUDE_CONFIG_DIR / CODEX_HOME set in
//   front of the command (Orca overwrites those two in the hook's `env`).
// - workspace.changed: chat sessions are not hooked, so focusing a workspace selects
//   its accounts in Orca (`orca account select`) for the chats launched next.
//
// The mapping itself is answered by dotagents' scripts/agent-account.sh.
import { execFile } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"

import { accountIds, launchCommand, matchWorkspacePaths, parseResolution, workspacePath } from "./routing.js"

const run = promisify(execFile)
const RESOLVE_TIMEOUT_MS = 1500

function firstExisting(candidates) {
  return candidates.find(path => path && existsSync(path)) ?? null
}

// Env overrides first; then the checkout this plugin was loaded from; then the main checkout.
function resolverPath() {
  return firstExisting([
    process.env.AGENT_ACCOUNT_RESOLVER,
    fileURLToPath(new URL("../../../../scripts/agent-account.sh", import.meta.url)),
    `${homedir()}/ghq/github.com/posaune0423/dotagents/scripts/agent-account.sh`,
  ])
}

function orcaCliPath() {
  return firstExisting([
    process.env.AGENT_ACCOUNT_ORCA_CLI,
    process.env.ORCA_CLI_COMMAND,
    "/Applications/Orca.app/Contents/Resources/bin/orca",
  ])
}

// Throws when the resolver is missing so callers log it instead of routing nothing silently.
async function resolve(dir) {
  const resolver = resolverPath()
  if (!resolver) throw new Error("agent-account.sh not found; set AGENT_ACCOUNT_RESOLVER to its path")
  const { stdout } = await run(resolver, ["--dir", dir], { timeout: RESOLVE_TIMEOUT_MS })
  return parseResolution(stdout)
}

export default function activate(orca) {
  orca.hooks.on("agent.launch.before", async (event, next) => {
    const dir = workspacePath(event.workspaceId)
    if (!dir) return undefined
    let resolution
    try {
      resolution = await resolve(dir)
    } catch (error) {
      orca.log(`resolve failed for ${dir}: ${error}`)
      return undefined
    }
    const command = launchCommand(event.agent, event.command, resolution)
    if (!command) return undefined
    orca.log(`${event.agent} in ${dir} -> ${resolution.account}`)
    return next({ ...event, command })
  })

  // Skip terminal churn in the same workspace, but only once its selection fully succeeded:
  // a failed resolve or select is retried on the next event for that workspace.
  let selectedPath = null
  orca.events.on("workspace.changed", async ({ context }) => {
    try {
      const { workspaces } = await orca.host.call("workspace.list", {})
      const paths = matchWorkspacePaths(workspaces, context)
      if (paths.length !== 1 || paths[0] === selectedPath) return
      const path = paths[0]
      const resolution = await resolve(path)
      if (resolution) {
        const cli = orcaCliPath()
        if (!cli) throw new Error("orca CLI not found; set AGENT_ACCOUNT_ORCA_CLI to its path")
        for (const [agent, id] of Object.entries(accountIds(resolution))) {
          await run(cli, ["account", "select", "--agent", agent, "--account", id, "--json"])
        }
        orca.log(`focused ${path} -> ${resolution.account}`)
      }
      selectedPath = path
    } catch (error) {
      orca.log(`account select failed: ${error}`)
    }
  })
}
