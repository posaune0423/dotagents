// Pure routing rules for the account-router worker. The resolver
// (scripts/agent-account.sh) decides the account; this module only turns its
// answer into what Orca needs: a launch command or Orca account ids.

const ROUTED_AGENTS = new Set(["claude", "codex"])

/** Parses the resolver's `account=` / `claude=` / `codex=` lines; null when it named no account. */
export function parseResolution(stdout) {
  const result = {}
  for (const line of stdout.split("\n")) {
    const eq = line.indexOf("=")
    if (eq <= 0) continue
    const key = line.slice(0, eq)
    if (key === "account" || key === "claude" || key === "codex") result[key] = line.slice(eq + 1)
  }
  return result.account ? result : null
}

/** Orca's worktree ids look like `<repo id>::<absolute path>`; other ids carry no path. */
export function workspacePath(workspaceId) {
  if (typeof workspaceId !== "string") return null
  const sep = workspaceId.indexOf("::")
  if (sep < 0) return null
  const path = workspaceId.slice(sep + 2)
  return path.startsWith("/") ? path : null
}

const quote = value => `'${value}'`

/**
 * The launch command with both config directories set in front of it, or null to leave it.
 * Both are set for either agent so agents it starts (Codex from Claude, say) use the same account.
 * `ORCA_CLAUDE_INJECTED_CONFIG_DIR=` makes Orca's `claude` shell function honour our directory
 * instead of re-reading its own account pointer.
 */
export function launchCommand(agent, command, resolution) {
  if (!ROUTED_AGENTS.has(agent) || !resolution) return null
  const { claude, codex } = resolution
  if ([claude, codex].some(dir => dir?.includes("'"))) return null
  const prefix = []
  if (claude) prefix.push(`CLAUDE_CONFIG_DIR=${quote(claude)}`, "ORCA_CLAUDE_INJECTED_CONFIG_DIR=")
  if (codex) prefix.push(`CODEX_HOME=${quote(codex)}`, `ORCA_CODEX_HOME=${quote(codex)}`)
  return prefix.length ? `${prefix.join(" ")} ${command}` : null
}

const MANAGED_DIR = {
  claude: /\/claude-profiles\/([^/]+)\/home\/?$/,
  codex: /\/codex-accounts\/([^/]+)\/home\/?$/,
}

/** Orca account ids for the directories Orca manages; other directories are skipped. */
export function accountIds(resolution) {
  const ids = {}
  for (const tool of ["claude", "codex"]) {
    const match = resolution?.[tool]?.match(MANAGED_DIR[tool])
    if (match) ids[tool] = match[1]
  }
  return ids
}

/** Paths of the workspaces matching the focused workspace context (name and branch). */
export function matchWorkspacePaths(workspaces, context) {
  if (!context) return []
  return workspaces.filter(ws => ws.name === context.displayName && ws.branch === context.branch).map(ws => ws.path)
}
