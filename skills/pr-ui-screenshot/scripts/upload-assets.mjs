#!/usr/bin/env node
// Uploads screenshots to GitHub and returns their user-attachments URLs.
//
// GitHub has no API for user-attachments: /upload/policies/assets is CSRF-guarded and
// ignores PATs entirely (a token gets 422, and PATs do not authenticate github.com web
// pages at all). The only way to a `user-attachments/assets/<uuid>` URL is a real logged-in
// browser session, so this borrows the PR comment box purely as an upload form. Nothing is
// ever posted: the draft is cleared and the Comment button is never clicked.
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, isAbsolute, join, resolve } from "node:path"
import { fail, loadChromium, log, parseArgs } from "./lib/common.mjs"

const USAGE = `Usage: upload-assets.mjs --manifest <file> --repo <owner/name> --pr <n> [options]
       upload-assets.mjs --login

  --manifest <file>     Manifest from capture.mjs; updated in place with the URLs.
  --repo <owner/name>   Repository owning the PR.
  --pr <n>              PR number whose comment box is borrowed as the upload form.
  --config <file>       Output of resolve-config.mjs (supplies repoRoot for Playwright).
  --repo-root <path>    Where to resolve Playwright from, if --config is not given.
  --storage-state <f>   Session file (default ~/.config/pr-ui-screenshot/github-storage-state.json).
  --out-manifest <f>    Write here instead of updating --manifest in place.
  --login               Open a visible browser, wait for you to log in, save the session.

The session file holds live GitHub cookies. It is written 0600 and must never be committed.
`

const DEFAULT_STATE = join(homedir(), ".config", "pr-ui-screenshot", "github-storage-state.json")
const ASSET_RE = /https:\/\/github\.com\/user-attachments\/assets\/[0-9a-fA-F-]+/
const UPLOAD_TIMEOUT_MS = 60000

// Ordered fallbacks: GitHub is mid-migration between the classic Rails editor and the
// React one, and only the classic editor exposes an addressable file input.
const FILE_INPUTS = ["#fc-new_comment_field", "input[type=file].manual-file-chooser", "input[type=file][multiple]"]
const TEXTAREAS = ["#new_comment_field", 'textarea[name="comment[body]"]', "#issue-comment-box textarea"]

const args = parseArgs(process.argv.slice(2), {
  flags: ["--manifest", "--repo", "--pr", "--config", "--repo-root", "--storage-state", "--out-manifest"],
  booleans: ["--login"],
  usage: USAGE,
})

const statePath = args["storage-state"] ?? DEFAULT_STATE

function repoRootFor() {
  if (args["repo-root"]) return args["repo-root"]
  if (args.config) return JSON.parse(readFileSync(args.config, "utf8")).repoRoot
  return process.cwd()
}

function saveState(state) {
  mkdirSync(dirname(statePath), { recursive: true })
  writeFileSync(statePath, JSON.stringify(state, null, 2))
  chmodSync(statePath, 0o600)
}

// Logged-out pages still carry <meta name="user-login" content="">, so the tag's
// presence proves nothing — only a non-empty content value means a live session.
async function currentUser(page) {
  return page
    .locator('meta[name="user-login"]')
    .first()
    .getAttribute("content", { timeout: 5000 })
    .then(value => value?.trim() || null)
    .catch(() => null)
}

async function doLogin(chromium) {
  const browser = await chromium.launch({ headless: false })
  const context = await browser.newContext()
  const page = await context.newPage()
  await page.goto("https://github.com/login", { waitUntil: "domcontentloaded" })
  log("A browser window is open. Log in to GitHub (2FA included); this will continue automatically.")
  log("Nothing you type is read by this script.")
  const deadline = Date.now() + 5 * 60 * 1000
  while (Date.now() < deadline) {
    const user = await currentUser(page)
    if (user) {
      saveState(await context.storageState())
      log(`Signed in as ${user}. Saved session to ${statePath} (mode 600).`)
      await browser.close()
      return
    }
    await page.waitForTimeout(1500)
  }
  await browser.close()
  fail("Timed out waiting for login (5 minutes).")
}

async function firstPresent(page, selectors) {
  for (const selector of selectors) {
    if ((await page.locator(selector).count()) > 0) return page.locator(selector).first()
  }
  return null
}

async function readDraft(textarea) {
  return textarea.inputValue()
}

async function clearDraft(textarea) {
  // GitHub autosaves the comment draft; leaving markup behind would resurface it later.
  await textarea.evaluate(node => {
    node.value = ""
    node.dispatchEvent(new Event("input", { bubbles: true }))
  })
}

async function uploadOne(page, textarea, absPath) {
  const input = await firstPresent(page, FILE_INPUTS)
  if (input) {
    // setInputFiles runs no actionability checks, so a display:none input is fine.
    await input.setInputFiles(absPath)
  } else {
    const chooser = page.waitForEvent("filechooser", { timeout: 15000 })
    await page.getByRole("button", { name: /Paste, drop, or click to add files/i }).click()
    await (await chooser).setFiles(absPath)
  }

  const deadline = Date.now() + UPLOAD_TIMEOUT_MS
  while (Date.now() < deadline) {
    const draft = await readDraft(textarea)
    if (draft.includes("<!-- Failed to upload") || draft.includes("Failed to upload")) {
      await clearDraft(textarea)
      throw new Error("GitHub rejected the upload (size or file type).")
    }
    const match = ASSET_RE.exec(draft)
    if (match) {
      await clearDraft(textarea)
      return match[0]
    }
    await page.waitForTimeout(500)
  }
  await clearDraft(textarea)
  throw new Error(`No attachment URL appeared within ${UPLOAD_TIMEOUT_MS / 1000}s.`)
}

function collectShots(manifest) {
  const shots = []
  for (const pair of manifest.pairs ?? []) {
    for (const side of ["before", "after"]) {
      if (pair[side]?.path && !pair[side].url) shots.push({ label: `${pair.id}/${side}`, shot: pair[side] })
    }
  }
  for (const row of manifest.localeMatrix ?? []) {
    for (const [locale, shot] of Object.entries(row.shots ?? {})) {
      if (shot?.path && !shot.url) shots.push({ label: `${row.id}/${locale}`, shot })
    }
  }
  return shots
}

const chromium = await loadChromium(repoRootFor())

if (args.login) {
  await doLogin(chromium)
  process.exit(0)
}

if (!args.manifest) fail(`--manifest is required\n${USAGE}`)
if (!args.repo) fail(`--repo is required\n${USAGE}`)
if (!args.pr) fail(`--pr is required\n${USAGE}`)
if (!existsSync(statePath)) {
  fail(`No saved GitHub session at ${statePath}.\nRun: upload-assets.mjs --login`)
}

const manifest = JSON.parse(readFileSync(args.manifest, "utf8"))
const shots = collectShots(manifest)
if (shots.length === 0) {
  log("Nothing to upload: every shot already has a URL.")
  process.exit(0)
}

const browser = await chromium.launch({ headless: true })
const context = await browser.newContext({ storageState: statePath })
const page = await context.newPage()
const prUrl = `https://github.com/${args.repo}/pull/${args.pr}`
const response = await page.goto(prUrl, { waitUntil: "domcontentloaded", timeout: 60000 })

const user = await currentUser(page)
if (!user) {
  await browser.close()
  // A private repo answers 404 (not 403) when the session is dead, so say both.
  fail(
    `Not signed in to GitHub, or the saved session expired — ${prUrl} returned ` +
      `HTTP ${response?.status() ?? "?"}.\nRun: upload-assets.mjs --login`,
  )
}
log(`Signed in as ${user}; uploading ${shots.length} image(s) via ${prUrl}`)

const textarea = await firstPresent(page, TEXTAREAS)
if (!textarea) {
  await browser.close()
  fail(
    `Could not find the comment box on ${prUrl}. GitHub may have migrated this page to ` +
      `the React editor; update TEXTAREAS/FILE_INPUTS in upload-assets.mjs.`,
  )
}
await textarea.scrollIntoViewIfNeeded()
await clearDraft(textarea)

const failures = []
let uploaded = 0
for (const { label, shot } of shots) {
  const absPath = isAbsolute(shot.path) ? shot.path : resolve(shot.path)
  if (!existsSync(absPath)) {
    failures.push(`${label}: file not found (${absPath})`)
    continue
  }
  try {
    shot.url = await uploadOne(page, textarea, absPath)
    uploaded += 1
    log(`- ${label} -> ${shot.url}`)
  } catch (error) {
    failures.push(`${label}: ${error.message}`)
  }
  await page.waitForTimeout(1000)
}

await clearDraft(textarea)
await browser.close()

const outManifest = args["out-manifest"] ?? args.manifest
writeFileSync(outManifest, `${JSON.stringify(manifest, null, 2)}\n`)
log(`Uploaded ${uploaded}/${shots.length} image(s); manifest: ${outManifest}`)

if (failures.length > 0) {
  log(`\n${failures.length} upload(s) failed:`)
  for (const entry of failures) log(`  - ${entry}`)
  log("\nThe PR body was NOT modified.")
  process.exit(1)
}
