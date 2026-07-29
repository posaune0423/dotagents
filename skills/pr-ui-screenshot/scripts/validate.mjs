#!/usr/bin/env node
// Rejects screenshots that are blank, tiny, or prove the wrong thing was captured.
import { readFileSync } from "node:fs"
import { fail, numberArg, parseArgs } from "./lib/common.mjs"
import { decode, differingPixels, standardDeviation } from "./lib/png.mjs"

const USAGE = `Usage: validate.mjs --manifest <file> [options]

  --manifest <file>    Manifest written by capture.mjs.
  --min-stddev <f>     Reject images flatter than this (default 0.005; blank == 0).
  --min-width <n>      Reject images narrower than this (default 80).
  --min-height <n>     Reject images shorter than this (default 60).

Checks performed:
  * every referenced PNG exists, decodes, and is bigger than the minimums
  * no image is a flat single colour (a blank or still-loading page)
  * before != after for every pair that has both -- identical images mean the capture
    target does not actually contain the change
  * locale shots are not all identical            -- the locale never switched

Exits non-zero and lists every problem found. Nothing is uploaded until this passes.
`

const args = parseArgs(process.argv.slice(2), {
  flags: ["--manifest", "--min-stddev", "--min-width", "--min-height"],
  defaults: { "min-stddev": "0.005", "min-width": "80", "min-height": "60" },
  usage: USAGE,
})
if (!args.manifest) fail(`--manifest is required\n${USAGE}`)

const minStddev = numberArg(args, "min-stddev", { min: 0 })
const minWidth = numberArg(args, "min-width", { min: 0, integer: true })
const minHeight = numberArg(args, "min-height", { min: 0, integer: true })

const manifest = JSON.parse(readFileSync(args.manifest, "utf8"))
const problems = []
const cache = new Map()

/** Decodes once per path; returns null (and records why) when unusable. */
function load(label, path) {
  if (!path) return null
  if (cache.has(path)) return cache.get(path)
  let image = null
  try {
    image = decode(path)
  } catch (error) {
    problems.push(`${label}: ${error.code === "ENOENT" ? "file missing" : `unreadable (${error.message})`} (${path})`)
  }
  cache.set(path, image)
  return image
}

function check(label, path) {
  const image = load(label, path)
  if (!image) return
  if (image.width < minWidth || image.height < minHeight) {
    problems.push(`${label}: too small (${image.width}x${image.height}, minimum ${minWidth}x${minHeight})`)
  }
  if (standardDeviation(image) < minStddev) {
    problems.push(`${label}: looks blank (flat colour) -- the page probably had not rendered yet`)
  }
}

for (const pair of manifest.pairs ?? []) {
  const name = pair.label ?? pair.id
  check(`pair ${name} (before)`, pair.before?.path)
  check(`pair ${name} (after)`, pair.after?.path)
  const before = cache.get(pair.before?.path)
  const after = cache.get(pair.after?.path)
  if (before && after && differingPixels(before, after) === 0) {
    problems.push(`pair ${name}: before and after are pixel-identical -- the captured screen does not show the change`)
  }
}

for (const row of manifest.localeMatrix ?? []) {
  const name = row.label ?? row.id
  const entries = Object.entries(row.shots ?? {})
  for (const [locale, shot] of entries) check(`locale ${name}/${locale}`, shot?.path)

  const images = entries.map(([, shot]) => cache.get(shot?.path)).filter(Boolean)
  if (images.length > 1 && images.every(image => differingPixels(images[0], image) === 0)) {
    problems.push(`locale ${name}: every locale rendered identically -- the locale switch did not take effect`)
  }
}

// An empty manifest is a broken pipeline, not a clean bill of health.
const checked = [...cache.values()].filter(Boolean).length
if (checked === 0) {
  fail(
    "Validation failed: the manifest references no usable images.\n" +
      "  Capture did not run, wrote elsewhere, or every target failed.",
  )
}

if (problems.length > 0) {
  process.stderr.write(`Validation failed (${problems.length} problem(s)):\n`)
  for (const problem of problems) process.stderr.write(`  - ${problem}\n`)
  process.exit(1)
}

process.stdout.write(`Validation passed: ${checked} image(s) checked.\n`)
