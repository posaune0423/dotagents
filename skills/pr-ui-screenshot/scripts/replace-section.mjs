#!/usr/bin/env node
// Replaces exactly one markdown section of a PR body, leaving every other byte untouched.
import { readFileSync, writeFileSync } from "node:fs"
import { fail, parseArgs } from "./lib/common.mjs"

const USAGE = `Usage: replace-section.mjs --body <file> --section <file> [options]

  --body <file>           Current PR body (use \`gh pr view --json body --jq .body\`).
  --section <file>        Replacement section markdown; must start with the target heading.
  --config <file>         Output of resolve-config.mjs; supplies --heading / --insert-before.
  --heading <text>        Section heading to replace, e.g. "## Screenshots".
  --insert-before <list>  Comma-separated headings to insert before when the section is absent.
  --out <file>            Write result here instead of stdout.

Exits non-zero when the section heading appears more than once, or when the
replacement section does not start with the configured heading.
`

// GitHub stores most PR bodies with CRLF. Round-tripping the wrong ending would
// rewrite every line of the body, so normalise for processing and restore at the end.
function detectEol(text) {
  return text.includes("\r\n") ? "\r\n" : "\n"
}

function headingLevel(line) {
  const match = /^(#{1,6})\s+\S/.exec(line)
  return match ? match[1].length : 0
}

// A `##` inside a fenced block is content, not a heading — track fences while scanning.
function headingLines(lines) {
  const result = []
  let fence = null
  for (const [index, line] of lines.entries()) {
    const fenceMatch = /^\s{0,3}(```+|~~~+)/.exec(line)
    if (fenceMatch) {
      const marker = fenceMatch[1][0]
      if (fence === null) {
        fence = marker
      } else if (fence === marker) {
        fence = null
      }
      continue
    }
    if (fence !== null) continue
    const level = headingLevel(line)
    if (level > 0) result.push({ index, level, text: line.trim() })
  }
  return result
}

const args = parseArgs(process.argv.slice(2), {
  flags: ["--body", "--section", "--config", "--heading", "--insert-before", "--out"],
  usage: USAGE,
})
if (!args.body) fail(`--body is required\n${USAGE}`)
if (!args.section) fail(`--section is required\n${USAGE}`)

let heading = args.heading
let insertBefore = args["insert-before"] ? args["insert-before"].split(",") : null
if (args.config) {
  const config = JSON.parse(readFileSync(args.config, "utf8"))
  heading = heading ?? config?.section?.heading
  insertBefore = insertBefore ?? config?.section?.insertBefore ?? []
}
insertBefore = (insertBefore ?? []).map(entry => entry.trim()).filter(Boolean)
if (!heading) fail("No section heading given. Pass --heading or --config.")
heading = heading.trim()

const bodyRaw = readFileSync(args.body, "utf8")
const sectionRaw = readFileSync(args.section, "utf8")
const eol = detectEol(bodyRaw)
const lines = bodyRaw.replace(/\r\n/g, "\n").split("\n")
const section = sectionRaw.replace(/\r\n/g, "\n").replace(/\s+$/, "").split("\n")

const sectionHeading = section.find(line => headingLevel(line) > 0)?.trim()
if (sectionHeading !== heading) {
  fail(
    `Replacement section starts with ${JSON.stringify(sectionHeading ?? null)} but the configured ` +
      `heading is ${JSON.stringify(heading)}. Align section.heading with the template so repeated ` +
      `runs update the same section instead of appending a new one.`,
  )
}

const headings = headingLines(lines)
const matches = headings.filter(entry => entry.text === heading)
if (matches.length > 1) {
  fail(`Heading ${JSON.stringify(heading)} appears ${matches.length} times; refusing to guess which one to replace.`)
}

// Splice `section` in at [start, end) and separate it from the following text with
// exactly one blank line. Only the seam is touched — the rest of the body is passed
// through verbatim, blank runs and all.
function splice(start, end) {
  const tail = lines.slice(end)
  const gap = tail.length > 0 && tail[0].trim() !== "" ? [""] : []
  return [...lines.slice(0, start), ...section, ...gap, ...tail]
}

// Bots put an opening marker comment just above their own heading — CodeRabbit's
// "<!-- auto-generated comment: release notes -->" sits between our section and
// "## Summary by CodeRabbit". Those lines belong to the next section, so hand them
// back rather than swallowing them with the section we are replacing.
function keepTrailingMarkers(start, end) {
  const isComment = line => /^\s*<!--.*-->\s*$/.test(line)
  let cut = end
  while (cut > start + 1 && (isComment(lines[cut - 1]) || lines[cut - 1].trim() === "")) cut -= 1
  // Only give ground when an actual marker is involved; a plain run of blank lines
  // is part of our section and is handled by splice()'s gap logic.
  return lines.slice(cut, end).some(isComment) ? cut : end
}

let out
if (matches.length === 1) {
  const start = matches[0].index
  const next = headings.find(entry => entry.index > start && entry.level <= matches[0].level)
  out = next ? splice(start, keepTrailingMarkers(start, next.index)) : splice(start, lines.length)
} else {
  const anchor = insertBefore
    .map(text => headings.find(entry => entry.text === text.trim()))
    .find(entry => entry !== undefined)
  if (anchor) {
    out = splice(anchor.index, anchor.index)
  } else {
    let end = lines.length
    while (end > 0 && lines[end - 1].trim() === "") end -= 1
    out = [...lines.slice(0, end), "", ...section]
  }
}

let result = out.join(eol)
// Preserve whether the original body ended with a newline.
if (bodyRaw.endsWith("\n") && !result.endsWith(eol)) result += eol

if (args.out) {
  writeFileSync(args.out, result)
  process.stderr.write(`Wrote ${args.out}\n`)
} else {
  process.stdout.write(result)
}
