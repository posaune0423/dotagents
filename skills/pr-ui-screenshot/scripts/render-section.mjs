#!/usr/bin/env node
// Turns an uploaded manifest into the PR screenshot section, using a user-editable template.
import { readFileSync, writeFileSync } from "node:fs"
import { isAbsolute, resolve } from "node:path"
import { fail, parseArgs } from "./lib/common.mjs"

const USAGE = `Usage: render-section.mjs --manifest <file> [options]

  --manifest <file>   Manifest with uploaded URLs (see references/manifest.md).
  --config <file>     Output of resolve-config.mjs; supplies the template path and locales.
  --template <file>   Template to render; overrides the one named in --config.
  --out <file>        Write result here instead of stdout.

Template syntax (deliberately tiny, no dependencies):
  {{name}}                        value lookup, HTML is inserted verbatim
  {{this}}                        the current item inside an each block
  {{#each rows}} … {{/each}}      on their own lines: repeat the enclosed lines
  {{#each cols}}…{{/each}}        inline on one line: repeat within that line
  {{#if name}} … {{/if}}          on their own lines: keep the lines when truthy
`

function lookup(scope, name) {
  if (name === "this") return scope.this
  for (let i = scope.stack.length - 1; i >= 0; i -= 1) {
    const frame = scope.stack[i]
    if (frame && typeof frame === "object" && name in frame) return frame[name]
  }
  return undefined
}

function truthy(value) {
  return Array.isArray(value) ? value.length > 0 : Boolean(value)
}

function renderInline(line, scope) {
  const withEach = line.replace(/\{\{#each\s+([\w.]+)\}\}([\s\S]*?)\{\{\/each\}\}/g, (_, name, inner) => {
    const items = lookup(scope, name)
    if (!Array.isArray(items)) return ""
    return items.map(item => renderInline(inner, { stack: [...scope.stack, item], this: item })).join("")
  })
  return withEach.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, name) => {
    const value = lookup(scope, name)
    return value === undefined || value === null ? "" : String(value)
  })
}

// Block tags are recognised only when a line contains nothing else, so inline
// `{{#each}}` inside a table row is left for renderInline to handle.
function blockTag(line) {
  const match = /^\s*\{\{([#/])(each|if)(?:\s+([\w.]+))?\}\}\s*$/.exec(line)
  if (!match) return null
  return { close: match[1] === "/", kind: match[2], name: match[3] }
}

function renderLines(lines, scope) {
  const out = []
  let i = 0
  while (i < lines.length) {
    const tag = blockTag(lines[i])
    if (!tag || tag.close) {
      out.push(renderInline(lines[i], scope))
      i += 1
      continue
    }
    let depth = 1
    let end = i + 1
    while (end < lines.length && depth > 0) {
      const inner = blockTag(lines[end])
      if (inner) depth += inner.close ? -1 : 1
      if (depth > 0) end += 1
    }
    if (depth !== 0) fail(`Unclosed {{#${tag.kind} ${tag.name}}} in template.`)
    const body = lines.slice(i + 1, end)
    const value = lookup(scope, tag.name)
    if (tag.kind === "each") {
      const items = Array.isArray(value) ? value : []
      for (const item of items) out.push(...renderLines(body, { stack: [...scope.stack, item], this: item }))
    } else if (truthy(value)) {
      out.push(...renderLines(body, scope))
    }
    i = end + 1
  }
  return out
}

function imgTag(shot, alt) {
  if (!shot || !shot.url) return "---"
  const parts = ["<img"]
  if (shot.width) parts.push(`width="${shot.width}"`)
  if (shot.height) parts.push(`height="${shot.height}"`)
  parts.push(`alt="${(shot.alt ?? alt ?? "image").replace(/"/g, "&quot;")}"`)
  parts.push(`src="${shot.url}" />`)
  return parts.join(" ")
}

const args = parseArgs(process.argv.slice(2), {
  flags: ["--manifest", "--config", "--template", "--out"],
  usage: USAGE,
})
if (!args.manifest) fail(`--manifest is required\n${USAGE}`)

const manifest = JSON.parse(readFileSync(args.manifest, "utf8"))
let config = null
if (args.config) config = JSON.parse(readFileSync(args.config, "utf8"))

let templatePath = args.template
if (!templatePath) {
  const named = config?.section?.template
  if (!named) fail("No template given. Pass --template, or --config with section.template set.")
  templatePath = isAbsolute(named) ? named : resolve(config.skillDir ?? ".", named)
}

const locales = manifest.localeColumns ?? config?.locales?.list ?? []
const pairs = (manifest.pairs ?? []).map(pair => ({
  label: pair.label ?? pair.id ?? "",
  before: imgTag(pair.before, `${pair.label ?? pair.id ?? "image"}-before`),
  after: imgTag(pair.after, `${pair.label ?? pair.id ?? "image"}-after`),
}))
const localeRows = (manifest.localeMatrix ?? []).map(row => ({
  label: row.label ?? row.id ?? "",
  cells: locales.map(locale => imgTag(row.shots?.[locale], `${row.label ?? row.id ?? "image"}-${locale}`)),
}))

const view = {
  pairs,
  hasPairs: pairs.length > 0,
  locales,
  localeRows,
  hasLocaleMatrix: localeRows.length > 0 && locales.length > 0,
  heading: config?.section?.heading ?? "## Screenshots",
}

const template = readFileSync(templatePath, "utf8").replace(/\r\n/g, "\n")
const rendered = renderLines(template.split("\n"), { stack: [view], this: view })
  // Inline `{{#each}}` leaves a trailing separator space on table header rows.
  .map(line => line.replace(/[ \t]+$/, ""))
  .join("\n")
  .replace(/\n{3,}/g, "\n\n")
  .replace(/\s+$/, "")

if (args.out) {
  writeFileSync(args.out, `${rendered}\n`)
  process.stderr.write(`Wrote ${args.out}\n`)
} else {
  process.stdout.write(`${rendered}\n`)
}
