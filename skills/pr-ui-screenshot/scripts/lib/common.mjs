// Shared CLI plumbing for the pr-ui-screenshot scripts.
import { createRequire } from "node:module"
import { join } from "node:path"
import { pathToFileURL } from "node:url"

export function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

export function log(message) {
  process.stderr.write(`${message}\n`)
}

// Long flags only, `--flag value`, plus valueless flags listed in `booleans`.
export function parseArgs(argv, { flags, booleans = [], usage, defaults = {} }) {
  const args = { ...defaults }
  let i = 0
  while (i < argv.length) {
    const arg = argv[i]
    if (arg === "-h" || arg === "--help") {
      process.stdout.write(usage)
      process.exit(0)
    }
    if (booleans.includes(arg)) {
      args[arg.replace(/^--/, "")] = true
      i += 1
      continue
    }
    if (!flags.includes(arg)) {
      process.stderr.write(`Unknown arg: ${arg}\n${usage}`)
      process.exit(1)
    }
    const value = argv[i + 1]
    if (value === undefined || value.startsWith("--")) {
      process.stderr.write(`Missing value for ${arg}\n${usage}`)
      process.exit(1)
    }
    args[arg.replace(/^--/, "")] = value
    i += 2
  }
  return args
}

// Playwright belongs to the project under test, not to this skill — resolve it from
// there so we drive the exact version the repo already installs.
export async function loadChromium(repoRoot) {
  const require = createRequire(join(repoRoot, "package.json"))
  for (const name of ["playwright", "playwright-core"]) {
    let entry
    try {
      entry = require.resolve(name)
    } catch {
      continue
    }
    // playwright ships CommonJS, so import() may expose it under `default`.
    const mod = await import(pathToFileURL(entry).href)
    const chromium = mod.chromium ?? mod.default?.chromium
    if (chromium) return chromium
  }
  return fail(
    `Could not resolve a usable "playwright" from ${repoRoot}. Install it there ` +
      `(e.g. pnpm add -D playwright && pnpm exec playwright install chromium).`,
  )
}
