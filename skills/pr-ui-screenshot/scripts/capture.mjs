#!/usr/bin/env node
// Drives Playwright over a capture manifest and writes one PNG per target/locale/side.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { join, resolve } from "node:path"
import { fail, loadChromium, log, parseArgs } from "./lib/common.mjs"

const USAGE = `Usage: capture.mjs --config <file> --manifest <file> --base-url <url> [options]

  --config <file>      Output of resolve-config.mjs.
  --manifest <file>    Capture manifest (see references/manifest.md).
  --base-url <url>     Dev server to shoot, e.g. http://localhost:3000.
  --side head|base     Which column these shots belong to (default head).
  --out-dir <dir>      PNG output directory (default $TMPDIR/pr-ui-screenshot/shots).
  --out-manifest <f>   Manifest to write with shot paths merged in (default: in place).
  --only <id,id>       Capture just these manifest ids.
  --retries <n>        Retries per shot before giving up (default 1).
  --headed             Run with a visible browser (debugging).

Locale shots are only taken for --side head; the before/after pair uses --side.
`

const PADDING = 12
const MAX_VIEWPORT_HEIGHT = 4000

function localeUrl(baseUrl, path, locale, locales) {
  const suffix = path.startsWith("/") ? path : `/${path}`
  if (!locale || locale === locales.default || locales.strategy !== "path-prefix") {
    return `${baseUrl}${suffix}`
  }
  return `${baseUrl}/${locale}${suffix === "/" ? "" : suffix}`
}

function cookiesFor(config, baseUrl) {
  const out = []
  for (const cookie of config?.auth?.cookies ?? []) {
    const value = cookie.value ?? (cookie.valueEnv ? process.env[cookie.valueEnv] : undefined)
    if (!value) {
      log(`  ! cookie ${cookie.name} skipped: ${cookie.valueEnv ?? "value"} is not set`)
      continue
    }
    out.push({
      name: cookie.name,
      value,
      domain: cookie.domain ?? new URL(baseUrl).hostname,
      path: cookie.path ?? "/",
    })
  }
  return out
}

async function runSetup(page, steps) {
  for (const step of steps ?? []) {
    if (step.click) await page.locator(step.click).first().click()
    else if (step.fill)
      await page
        .locator(step.fill)
        .first()
        .fill(step.value ?? "")
    else if (step.press) await page.keyboard.press(step.press)
    else if (step.waitFor) await page.locator(step.waitFor).first().waitFor({ state: "visible" })
    else if (step.wait) await page.waitForTimeout(step.wait)
    else if (step.eval) await page.evaluate(step.eval)
    else throw new Error(`Unrecognised setup step: ${JSON.stringify(step)}`)
  }
}

async function settle(page) {
  await page.waitForLoadState("load")
  // networkidle hangs on apps that poll, so cap the wait and carry on.
  await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {})
  await page.evaluate(() => document.fonts?.ready).catch(() => {})
  await page.waitForTimeout(250)
}

async function captureOne(context, target, options) {
  const { url, viewport, outPath } = options
  const page = await context.newPage()
  try {
    await page.setViewportSize({ width: viewport.width, height: viewport.height })
    const response = await page.goto(url, { waitUntil: "commit", timeout: 60000 })
    if (response && response.status() >= 400) {
      throw new Error(`${url} returned HTTP ${response.status()}`)
    }
    await settle(page)
    await runSetup(page, target.setup)
    await settle(page)

    const shot = { path: outPath, url: null }
    if (!target.selector) {
      await page.screenshot({ path: outPath, animations: "disabled", fullPage: Boolean(target.fullPage) })
      const size = page.viewportSize()
      return { ...shot, width: size.width, height: size.height }
    }

    const locator = page.locator(target.selector).first()
    await locator.waitFor({ state: "visible", timeout: 15000 })
    await locator.scrollIntoViewIfNeeded()
    await page.waitForTimeout(150)

    let box = await locator.boundingBox()
    if (!box) throw new Error(`Selector ${target.selector} has no bounding box (is it display:none?)`)

    // Grow the viewport rather than zooming out: shrinking text to fit makes the
    // wording — the thing being reviewed — unreadable.
    const wanted = Math.ceil(box.height + PADDING * 2)
    if (wanted > viewport.height && wanted <= MAX_VIEWPORT_HEIGHT) {
      await page.setViewportSize({ width: viewport.width, height: wanted })
      await page.waitForTimeout(200)
      await locator.scrollIntoViewIfNeeded()
      box = (await locator.boundingBox()) ?? box
    }

    const pageSize = await page.evaluate(() => ({
      width: document.documentElement.scrollWidth,
      height: document.documentElement.scrollHeight,
    }))
    const x = Math.max(0, Math.floor(box.x - PADDING))
    const y = Math.max(0, Math.floor(box.y - PADDING))
    const clip = {
      x,
      y,
      width: Math.min(Math.ceil(box.width + PADDING * 2), pageSize.width - x),
      height: Math.min(Math.ceil(box.height + PADDING * 2), pageSize.height - y),
    }
    if (clip.width <= 0 || clip.height <= 0) throw new Error(`Computed an empty clip for ${target.selector}`)

    const clipped = clip.height + clip.y > page.viewportSize().height
    await page.screenshot({ path: outPath, clip, fullPage: clipped, animations: "disabled" })
    return { ...shot, width: clip.width, height: clip.height }
  } finally {
    await page.close()
  }
}

async function withRetries(label, retries, fn) {
  let lastError
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      return await fn()
    } catch (error) {
      lastError = error
      log(`  ! ${label} attempt ${attempt + 1} failed: ${error.message}`)
    }
  }
  throw lastError
}

const args = parseArgs(process.argv.slice(2), {
  flags: ["--config", "--manifest", "--base-url", "--side", "--out-dir", "--out-manifest", "--only", "--retries"],
  booleans: ["--headed"],
  defaults: { side: "head", retries: "1" },
  usage: USAGE,
})
if (!args.config) fail(`--config is required\n${USAGE}`)
if (!args.manifest) fail(`--manifest is required\n${USAGE}`)
if (!args["base-url"]) fail(`--base-url is required\n${USAGE}`)
if (!["head", "base"].includes(args.side)) fail(`--side must be "head" or "base", got ${args.side}`)

const config = JSON.parse(readFileSync(args.config, "utf8"))
const manifest = JSON.parse(readFileSync(args.manifest, "utf8"))
const baseUrl = args["base-url"].replace(/\/$/, "")
const side = args.side
const retries = Number(args.retries)
const only = args.only ? new Set(args.only.split(",").map(entry => entry.trim())) : null
// Default outside the repo: screenshots are build artefacts, and writing them into the
// working tree invites accidental commits.
const outDir = resolve(args["out-dir"] ?? join(process.env.TMPDIR ?? "/tmp", "pr-ui-screenshot", "shots"))
mkdirSync(outDir, { recursive: true })

const viewports = new Map((config.viewports ?? []).map(entry => [entry.name, entry]))
const defaultViewport = viewports.get(config.defaultViewport) ?? config.viewports?.[0]
if (!defaultViewport) fail("Config has no viewports.")

const locales = config.locales ?? { list: [], default: "", strategy: "path-prefix" }
const chromium = await loadChromium(config.repoRoot)
const browser = await chromium.launch({ headless: !args.headed })
const context = await browser.newContext({
  deviceScaleFactor: 2,
  reducedMotion: "reduce",
  locale: locales.default || undefined,
})
// Auth cookies must exist before the first navigation: apps commonly read the token
// once at module-load time, so setting them afterwards is too late.
const cookies = cookiesFor(config, baseUrl)
if (cookies.length > 0) await context.addCookies(cookies)

const failures = []
let taken = 0

function viewportFor(target) {
  return viewports.get(target.viewport) ?? defaultViewport
}

function shotPath(id, locale, sideName) {
  const safe = String(id).replace(/[^\w.-]+/g, "-")
  return join(outDir, `${safe}__${locale || "default"}__${sideName}.png`)
}

for (const target of manifest.pairs ?? []) {
  if (only && !only.has(target.id)) continue
  if (side === "base" && target.captureBase === false) continue
  const locale = target.locale ?? locales.default
  const url = localeUrl(baseUrl, target.path, locale, locales)
  const label = `${target.id} [${side}]`
  log(`- ${label} ${url}`)
  try {
    const shot = await withRetries(label, retries, () =>
      captureOne(context, target, {
        url,
        viewport: viewportFor(target),
        outPath: shotPath(target.id, locale, side),
      }),
    )
    target[side === "head" ? "after" : "before"] = { ...shot, alt: `${target.label ?? target.id}-${side}` }
    taken += 1
  } catch (error) {
    failures.push(`${label}: ${error.message}`)
  }
}

if (side === "head") {
  for (const target of manifest.localeMatrix ?? []) {
    if (only && !only.has(target.id)) continue
    target.shots = target.shots ?? {}
    for (const locale of target.locales ?? locales.list) {
      const url = localeUrl(baseUrl, target.path, locale, locales)
      const label = `${target.id} [${locale}]`
      log(`- ${label} ${url}`)
      try {
        const shot = await withRetries(label, retries, () =>
          captureOne(context, target, {
            url,
            viewport: viewportFor(target),
            outPath: shotPath(target.id, locale, "head"),
          }),
        )
        target.shots[locale] = { ...shot, alt: `${target.label ?? target.id}-${locale}` }
        taken += 1
      } catch (error) {
        failures.push(`${label}: ${error.message}`)
      }
    }
  }
}

await context.close()
await browser.close()

manifest.localeColumns = manifest.localeColumns ?? locales.list
const outManifest = args["out-manifest"] ?? args.manifest
writeFileSync(outManifest, `${JSON.stringify(manifest, null, 2)}\n`)
log(`Captured ${taken} screenshot(s) into ${outDir}; manifest: ${outManifest}`)

if (failures.length > 0) {
  log(`\n${failures.length} capture(s) failed:`)
  for (const entry of failures) log(`  - ${entry}`)
  process.exit(1)
}
