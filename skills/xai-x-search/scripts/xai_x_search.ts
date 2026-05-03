#!/usr/bin/env bun

/**
 * Run generic research with xAI (Grok) + x_search and save raw artifacts.
 *
 * Requires:
 *   XAI_API_KEY in env, project .env, or skill-local .env
 *
 * Usage:
 *   bun skills/xai-x-search/scripts/xai_x_search.ts --query "OpenAI API changelog"
 *   bun skills/xai-x-search/scripts/xai_x_search.ts --query "X API rate limits" --locale global --days 7
 */

import fs from "node:fs"
import path from "node:path"
import process from "node:process"
import { fileURLToPath } from "node:url"

type Json = null | boolean | number | string | Json[] | { [k: string]: Json }

const DEFAULT_BASE_URL = "https://api.x.ai"
const DEFAULT_MODEL = "grok-4-1-fast-reasoning"

function stdout(line: string): void {
  process.stdout.write(`${line}\n`)
}

function stderr(line: string): void {
  process.stderr.write(`${line}\n`)
}

function hasWorkspaceMarker(dir: string): boolean {
  return (
    fs.existsSync(path.join(dir, "AGENTS.md")) ||
    fs.existsSync(path.join(dir, "SOUL.md")) ||
    fs.existsSync(path.join(dir, ".git")) ||
    fs.existsSync(path.join(dir, "package.json"))
  )
}

function findProjectRoot(startDir: string): string | null {
  let dir = path.resolve(startDir)
  while (true) {
    if (hasWorkspaceMarker(dir)) return dir
    const parent = path.dirname(dir)
    if (parent === dir) return null
    dir = parent
  }
}

function projectRoot(): string {
  const scriptDir = path.dirname(fileURLToPath(import.meta.url))
  return findProjectRoot(process.cwd()) ?? findProjectRoot(scriptDir) ?? path.resolve(scriptDir, "..")
}

function skillRoot(): string {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
}

function loadDotenv(dotenvPath: string): Record<string, string> {
  if (!fs.existsSync(dotenvPath)) return {}

  const out: Record<string, string> = {}
  const lines = fs.readFileSync(dotenvPath, "utf8").split(/\r?\n/)

  for (const raw of lines) {
    const line = raw.trim()
    if (!line || line.startsWith("#")) continue

    const eq = line.indexOf("=")
    if (eq === -1) continue

    const key = line.slice(0, eq).trim()
    let value = line.slice(eq + 1).trim()
    if (!key) continue

    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1)
    }
    out[key] = value
  }

  return out
}

function timestampSlug(d: Date): string {
  const iso = d.toISOString()
  const y = iso.slice(0, 4)
  const m = iso.slice(5, 7)
  const day = iso.slice(8, 10)
  const hh = iso.slice(11, 13)
  const mm = iso.slice(14, 16)
  const ss = iso.slice(17, 19)
  return `${y}${m}${day}_${hh}${mm}${ss}Z`
}

function parseArgs(argv: string[]) {
  const args = {
    query: "",
    locale: "ja" as "ja" | "global",
    days: 30,
    out_dir: "data/xai-x-search",
    xai_api_key: "",
    xai_base_url: "",
    xai_model: "",
    dry_run: false,
    raw_json: false,
  }

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    const next = () => (i + 1 < argv.length ? argv[++i] : "")

    if (a === "--query") args.query = next()
    else if (a === "--locale") {
      const v = next().trim().toLowerCase()
      args.locale = v === "global" ? "global" : "ja"
    } else if (a === "--days") args.days = Number(next())
    else if (a === "--out-dir") args.out_dir = next() || args.out_dir
    else if (a === "--xai_api_key") args.xai_api_key = next()
    else if (a === "--xai_base_url") args.xai_base_url = next()
    else if (a === "--xai_model") args.xai_model = next()
    else if (a === "--dry-run") args.dry_run = true
    else if (a === "--raw-json") args.raw_json = true
    else if (a === "-h" || a === "--help") {
      stdout(`Usage:
  bun skills/xai-x-search/scripts/xai_x_search.ts --query "..."

Options:
  --query TEXT       research query (required)
  --locale L         ja or global (default: ja)
  --days N           lookback hint in days (default: 30)
  --out-dir DIR      output directory (default: data/xai-x-search)
  --dry-run          print request payload and exit
  --raw-json         also print raw JSON response to stderr
`)
      process.exit(0)
    }
  }

  if (!Number.isFinite(args.days) || args.days <= 0) args.days = 30
  return args
}

function getConfig(args: ReturnType<typeof parseArgs>) {
  const projectDotenv = loadDotenv(path.join(projectRoot(), ".env"))
  const skillDotenv = loadDotenv(path.join(skillRoot(), ".env"))
  const getStr = (envKey: string, cliValue: string, fallback: string) =>
    cliValue || process.env[envKey] || projectDotenv[envKey] || skillDotenv[envKey] || fallback

  const xai_api_key = getStr("XAI_API_KEY", args.xai_api_key, "")
  const xai_base_url = getStr("XAI_BASE_URL", args.xai_base_url, DEFAULT_BASE_URL).replace(/\/+$/, "")
  const xai_model = getStr("XAI_MODEL", args.xai_model, DEFAULT_MODEL)

  return { xai_api_key, xai_base_url, xai_model }
}

function buildPrompt(input: { query: string; locale: "ja" | "global"; days: number; nowIso: string }): string {
  const localeLine =
    input.locale === "ja"
      ? "検索は日本語圏情報を優先し、必要に応じて英語の一次情報を補完する。"
      : "検索はグローバル一次情報（英語中心）を優先する。"

  return `日本語で回答して。

調査クエリ: ${input.query}
時点: ${input.nowIso}
検索窓の目安: 直近${input.days}日（仕様や規約は常に最新優先）

方針:
- ${localeLine}
- x_search を使って情報を収集する。
- 不明な点は不明と明記する。推測を事実として書かない。
- URLを必ず残す。
- 出力はMarkdownにする。

出力項目:
- Query
- Quick Answer
- Key Findings
- Caveats / Risks
- Sources (URL list)
`
}

async function postJson(
  url: string,
  headers: Record<string, string>,
  payload: Json,
  timeoutMs: number,
): Promise<unknown> {
  const ac = new AbortController()
  const t = setTimeout(() => ac.abort(), timeoutMs)

  try {
    const res = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: ac.signal,
    })

    const text = await res.text()
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${text.slice(0, 4000)}`)
    }

    return JSON.parse(text) as unknown
  } finally {
    clearTimeout(t)
  }
}

function extractText(resp: unknown): string {
  if (resp && typeof resp === "object") {
    const r = resp as { [k: string]: unknown }
    const out = r.output

    if (Array.isArray(out)) {
      const parts: string[] = []
      for (const item of out) {
        if (!item || typeof item !== "object") continue
        const content = (item as { [k: string]: unknown }).content
        if (!Array.isArray(content)) continue
        for (const c of content) {
          if (!c || typeof c !== "object") continue
          const text = (c as { [k: string]: unknown }).text
          if (typeof text === "string" && text.trim()) parts.push(text)
        }
      }
      if (parts.length) return parts.join("\n").trim()
    }

    for (const key of ["output_text", "text", "content"]) {
      const v = r[key]
      if (typeof v === "string" && v.trim()) return v.trim()
    }
  }

  return JSON.stringify(resp, null, 2)
}

function saveFile(outDir: string, filename: string, content: string): string {
  const root = projectRoot()
  const absDir = path.isAbsolute(outDir) ? outDir : path.join(root, outDir)
  fs.mkdirSync(absDir, { recursive: true })
  const filePath = path.join(absDir, filename)
  fs.writeFileSync(filePath, content, "utf8")
  return filePath
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const cfg = getConfig(args)

  if (!args.query.trim()) {
    stderr('Missing --query. Example: --query "X API recent search rate limits"')
    process.exit(2)
  }

  const now = new Date()
  const prompt = buildPrompt({
    query: args.query.trim(),
    locale: args.locale,
    days: args.days,
    nowIso: now.toISOString(),
  })

  const payload: Json = {
    model: cfg.xai_model,
    input: prompt,
    tools: [{ type: "x_search" }],
  }

  if (args.dry_run) {
    stdout(JSON.stringify(payload, null, 2))
    return
  }

  if (!cfg.xai_api_key.trim()) {
    stderr("Missing XAI_API_KEY. Set it in env, project .env, or skill .env.")
    process.exit(2)
  }

  const url = `${cfg.xai_base_url}/v1/responses`
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${cfg.xai_api_key}`,
  }

  const response = await postJson(url, headers, payload, 180_000)
  const text = extractText(response)

  const ts = timestampSlug(now)
  const base = `${ts}_${args.locale}_x_search`

  const md = `# xAI x_search Result\n\n## Meta\n- Timestamp (UTC): ${now.toISOString()}\n- Query: ${args.query.trim()}\n- Locale: ${args.locale}\n\n---\n\n${text}\n`

  const jsonFile = saveFile(
    args.out_dir,
    `${base}.json`,
    JSON.stringify(
      {
        timestamp: now.toISOString(),
        query: args.query.trim(),
        params: {
          locale: args.locale,
          days: args.days,
          model: cfg.xai_model,
          base_url: cfg.xai_base_url,
          out_dir: args.out_dir,
        },
        request: payload,
        response,
        extracted_text: text,
      },
      null,
      2,
    ),
  )

  const txtFile = saveFile(args.out_dir, `${base}.txt`, text)
  const mdFile = saveFile(args.out_dir, `${base}.md`, md)

  stderr(`Saved: ${path.relative(process.cwd(), jsonFile)}`)
  stderr(`Saved: ${path.relative(process.cwd(), txtFile)}`)
  stderr(`Saved: ${path.relative(process.cwd(), mdFile)}`)

  if (args.raw_json) {
    stderr(JSON.stringify(response, null, 2))
  }

  stdout(text)
}

main().catch((err: unknown) => {
  stderr(String(err))
  process.exit(1)
})
