#!/usr/bin/env node
// Resolves the pr-ui-screenshot config for a repo and prints the merged JSON.
import { execFileSync } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { fail, parseArgs } from "./lib/common.mjs"

const SKILL_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..")

const USAGE = `Usage: resolve-config.mjs [--repo-root <path>] [--get <path>] [--explain]

Prints the merged pr-ui-screenshot config as JSON on stdout.

Resolution order (later entries override earlier ones, merged recursively):
  1. presets/default.json                       (built-in baseline)
  2. presets/<owner>-<repo>.json                (bundled preset, matched via \`gh repo view\`)
  3. <repo>/.claude/pr-ui-screenshot.json
  4. <repo>/.agents/pr-ui-screenshot.json
  5. $PR_UI_SCREENSHOT_CONFIG                   (explicit path, highest precedence)

  --get <path>   Print one value instead of the whole document, e.g. --get dev.port.
  --explain      List the layers that were applied, on stderr.
`

const args = parseArgs(process.argv.slice(2), {
  flags: ["--repo-root", "--get"],
  booleans: ["--explain"],
  usage: USAGE,
})

function git(cwd, cliArgs) {
  try {
    return execFileSync("git", cliArgs, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim()
  } catch {
    return ""
  }
}

const repoRoot = args["repo-root"] ?? git(process.cwd(), ["rev-parse", "--show-toplevel"])
if (!repoRoot || !existsSync(repoRoot)) fail("Could not determine repo root. Use --repo-root <path>.")

const layers = [join(SKILL_DIR, "presets", "default.json")]

// Must run inside the target repo: `gh repo view` resolves the remote from the cwd,
// so calling it from elsewhere would silently pick the wrong preset.
let nameWithOwner = ""
try {
  nameWithOwner = execFileSync("gh", ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim()
} catch {
  nameWithOwner = ""
}
if (nameWithOwner) {
  const preset = join(SKILL_DIR, "presets", `${nameWithOwner.replace("/", "-")}.json`)
  if (existsSync(preset)) layers.push(preset)
}

for (const candidate of [
  join(repoRoot, ".claude", "pr-ui-screenshot.json"),
  join(repoRoot, ".agents", "pr-ui-screenshot.json"),
]) {
  if (existsSync(candidate)) layers.push(candidate)
}

if (process.env.PR_UI_SCREENSHOT_CONFIG) {
  if (!existsSync(process.env.PR_UI_SCREENSHOT_CONFIG)) {
    fail(`PR_UI_SCREENSHOT_CONFIG points at a missing file: ${process.env.PR_UI_SCREENSHOT_CONFIG}`)
  }
  layers.push(process.env.PR_UI_SCREENSHOT_CONFIG)
}

const isPlainObject = value => value !== null && typeof value === "object" && !Array.isArray(value)

// Objects merge recursively so a project config can override dev.port without
// restating the whole dev block; arrays are replaced wholesale.
function merge(base, override) {
  if (!isPlainObject(base) || !isPlainObject(override)) return override
  const out = { ...base }
  for (const [key, value] of Object.entries(override)) {
    out[key] = key in base ? merge(base[key], value) : value
  }
  return out
}

let config = {}
for (const layer of layers) {
  let parsed
  try {
    parsed = JSON.parse(readFileSync(layer, "utf8"))
  } catch (error) {
    fail(`Config layer is not valid JSON: ${layer}\n  ${error.message}`)
  }
  if (args.explain) process.stderr.write(`config layer: ${layer}\n`)
  config = merge(config, parsed)
}

config.repoRoot = repoRoot
config.skillDir = SKILL_DIR

if (args.get) {
  const value = args.get.split(".").reduce((node, key) => (node == null ? undefined : node[key]), config)
  if (value === undefined) fail(`No such config key: ${args.get}`)
  process.stdout.write(`${typeof value === "object" ? JSON.stringify(value) : String(value)}\n`)
} else {
  process.stdout.write(`${JSON.stringify(config, null, 2)}\n`)
}
