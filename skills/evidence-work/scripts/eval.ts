#!/usr/bin/env bun

import { createHash } from "node:crypto"
import { mkdir, readFile, writeFile } from "node:fs/promises"
import path from "node:path"
import process from "node:process"
import { fileURLToPath } from "node:url"

type EvalMode = "smoke" | "full" | "forced" | "hook"
type Arm = "control" | "auto" | "forced" | "auto-hook"
type Category = "direct" | "research" | "causal-diagnosis" | "decision-advice" | "no-skill"
type ExpectedMode = Exclude<Category, "no-skill"> | "none"

type EvalCase = {
  id: string
  category: Category
  prompt: string
  cwd: string
  read_roots: string[]
  expected_mode: ExpectedMode
  web_access: boolean
  required_context: string[]
  success_criteria: string[]
  forbidden_claims: string[]
  critical_failure_conditions: string[]
  privacy_class: "sanitized" | "private"
  smoke: boolean
}

type RunSpec = {
  id: string
  case_id: string
  category: Category
  expected_mode: ExpectedMode
  arm: Arm
  repeat: number
  cwd: string
  read_roots: string[]
  web_access: boolean
  skill_enabled: boolean
  prompt: string
  command_args: string[]
  privacy_class: EvalCase["privacy_class"]
}

type Args = {
  mode: EvalMode
  cases: string
  privateCases?: string
  runId: string
  dryRun: boolean
  caseIds: string[]
  forcedCases: string[]
  model: string
  reasoning: string
  outDir: string
  codexBin: string
  summarizeRun?: string
}

type RunResult = RunSpec & {
  exit_code: number
  duration_ms: number
  usage: Record<string, number>
  event_types: Record<string, number>
  item_types: Record<string, number>
  tool_calls: number
  subagent_calls: number
  final_answer: string
}

const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const skillRoot = path.resolve(scriptDir, "..")
const repoRoot = path.resolve(skillRoot, "../..")
const defaultCases = path.join(skillRoot, "evals", "cases.jsonl")
const safeIdPattern = /^[a-z0-9][a-z0-9-]*$/

function usage(): never {
  throw new Error(
    "usage: eval.ts --mode smoke|full|forced|hook [--cases PATH] [--private-cases PATH] [--case-ids id,id] [--run-id ID] [--forced-cases id,id] [--out-dir PATH] [--codex-bin PATH] [--summarize-run PATH] [--dry-run]",
  )
}

function parseArgs(argv: string[]): Args {
  const args: Args = {
    mode: "smoke",
    cases: defaultCases,
    runId: new Date().toISOString().replaceAll(/[:.]/g, "-").toLowerCase(),
    dryRun: false,
    caseIds: [],
    forcedCases: [],
    model: "gpt-5.6-sol",
    reasoning: "high",
    outDir: path.join(repoRoot, "data", "evaluations", "evidence-work"),
    codexBin: "codex",
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === "--dry-run") {
      args.dryRun = true
      continue
    }
    const value = argv[index + 1]
    if (!value) usage()
    if (arg === "--mode") args.mode = value as EvalMode
    else if (arg === "--cases") args.cases = value
    else if (arg === "--private-cases") args.privateCases = value
    else if (arg === "--case-ids") args.caseIds = value.split(",").filter(Boolean)
    else if (arg === "--run-id") args.runId = value
    else if (arg === "--forced-cases") args.forcedCases = value.split(",").filter(Boolean)
    else if (arg === "--model") args.model = value
    else if (arg === "--reasoning") args.reasoning = value
    else if (arg === "--out-dir") args.outDir = value
    else if (arg === "--codex-bin") args.codexBin = value
    else if (arg === "--summarize-run") args.summarizeRun = value
    else usage()
    index += 1
  }

  if (!["smoke", "full", "forced", "hook"].includes(args.mode)) usage()
  if (!safeIdPattern.test(args.runId)) throw new Error("--run-id must be a lowercase slug")
  if (args.mode === "forced" && args.forcedCases.length === 0) {
    throw new Error("--forced-cases is required in forced mode")
  }
  return args
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(item => typeof item === "string")
}

function validateCase(value: unknown, source: string, line: number): EvalCase {
  if (!value || typeof value !== "object") throw new Error(`${source}:${line}: case must be an object`)
  const item = value as Record<string, unknown>
  const categories: Category[] = ["direct", "research", "causal-diagnosis", "decision-advice", "no-skill"]
  const expectedModes: ExpectedMode[] = ["direct", "research", "causal-diagnosis", "decision-advice", "none"]
  const requiredStrings = ["id", "category", "prompt", "cwd", "expected_mode", "privacy_class"]
  for (const field of requiredStrings) {
    if (typeof item[field] !== "string" || item[field] === "") {
      throw new Error(`${source}:${line}: ${field} must be a non-empty string`)
    }
  }
  if (!categories.includes(item.category as Category)) throw new Error(`${source}:${line}: invalid category`)
  if (!safeIdPattern.test(item.id as string)) throw new Error(`${source}:${line}: id must be a lowercase slug`)
  if (!expectedModes.includes(item.expected_mode as ExpectedMode))
    throw new Error(`${source}:${line}: invalid expected_mode`)
  if (!["sanitized", "private"].includes(item.privacy_class as string)) {
    throw new Error(`${source}:${line}: invalid privacy_class`)
  }
  if (typeof item.web_access !== "boolean" || typeof item.smoke !== "boolean") {
    throw new Error(`${source}:${line}: web_access and smoke must be boolean`)
  }
  const arrayFields = [
    "read_roots",
    "required_context",
    "success_criteria",
    "forbidden_claims",
    "critical_failure_conditions",
  ]
  for (const field of arrayFields) {
    if (!isStringArray(item[field])) throw new Error(`${source}:${line}: ${field} must be a string array`)
  }
  if ((item.success_criteria as string[]).length === 0) {
    throw new Error(`${source}:${line}: success_criteria must not be empty`)
  }
  if (item.category === "no-skill" && item.expected_mode !== "none") {
    throw new Error(`${source}:${line}: no-skill cases must expect none`)
  }
  return item as EvalCase
}

async function loadCases(file: string, expectedPrivacy?: EvalCase["privacy_class"]): Promise<EvalCase[]> {
  const text = await readFile(file, "utf8")
  const cases = text
    .split("\n")
    .map(line => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      try {
        return validateCase(JSON.parse(line), file, index + 1)
      } catch (error) {
        if (error instanceof SyntaxError) throw new Error(`${file}:${index + 1}: invalid JSON`)
        throw error
      }
    })
  const seen = new Set<string>()
  for (const item of cases) {
    if (seen.has(item.id)) throw new Error(`${file}: duplicate id ${item.id}`)
    if (expectedPrivacy && item.privacy_class !== expectedPrivacy) {
      throw new Error(`${file}: ${item.id} must use privacy_class=${expectedPrivacy}`)
    }
    seen.add(item.id)
  }
  return cases
}

function armsFor(mode: EvalMode): Arm[] {
  if (mode === "smoke") return ["control", "auto", "forced"]
  if (mode === "full") return ["control", "auto"]
  if (mode === "hook") return ["auto", "auto-hook"]
  return ["forced"]
}

function repeatsFor(mode: EvalMode): number {
  return mode === "full" ? 3 : 1
}

function makePrompt(item: EvalCase, arm: Arm): string {
  return arm === "forced" ? `Use $evidence-work.\n${item.prompt}` : item.prompt
}

function resolveFromRepo(value: string): string {
  return path.isAbsolute(value) ? value : path.resolve(repoRoot, value)
}

function buildCommandArgs(item: EvalCase, arm: Arm, repeat: number, args: Args): string[] {
  const runId = `${item.id}-${arm}-r${repeat}`
  const outputFile = path.resolve(args.outDir, args.runId, "runs", runId, "final.md")
  const command = [
    "exec",
    "--ephemeral",
    "--json",
    "--sandbox",
    "read-only",
    "--model",
    args.model,
    "-c",
    `model_reasoning_effort=\"${args.reasoning}\"`,
    "-c",
    `features.hooks=${arm === "auto-hook" ? "true" : "false"}`,
    "-C",
    resolveFromRepo(item.cwd),
    "-o",
    outputFile,
  ]
  if (arm === "control") {
    command.push("-c", `skills.config=[{path=\"${path.join(skillRoot, "SKILL.md")}\",enabled=false}]`)
  }
  if (arm === "auto-hook") command.push("--dangerously-bypass-hook-trust")
  if (item.web_access) command.push("--search")
  for (const root of item.read_roots) command.push("--add-dir", resolveFromRepo(root))
  command.push(makePrompt(item, arm))
  return command
}

function buildRuns(cases: EvalCase[], args: Args): RunSpec[] {
  const selected = cases.filter(item => {
    if (args.caseIds.length > 0 && !args.caseIds.includes(item.id)) return false
    if (args.mode === "smoke" || args.mode === "hook") return item.smoke
    if (args.mode === "forced") return args.forcedCases.includes(item.id)
    return true
  })
  const runs: RunSpec[] = []
  for (const item of selected) {
    for (let repeat = 1; repeat <= repeatsFor(args.mode); repeat += 1) {
      for (const arm of armsFor(args.mode)) {
        runs.push({
          id: `${item.id}-${arm}-r${repeat}`,
          case_id: item.id,
          category: item.category,
          expected_mode: item.expected_mode,
          arm,
          repeat,
          cwd: item.cwd,
          read_roots: item.read_roots,
          web_access: item.web_access,
          skill_enabled: arm !== "control",
          prompt: makePrompt(item, arm),
          command_args: buildCommandArgs(item, arm, repeat, args),
          privacy_class: item.privacy_class,
        })
      }
    }
  }
  return runs
}

function countBy(values: string[]): Record<string, number> {
  const counts: Record<string, number> = {}
  for (const value of values) counts[value] = (counts[value] ?? 0) + 1
  return counts
}

function parseEvents(stdout: string) {
  const events: Record<string, unknown>[] = []
  const invalidLines: string[] = []
  for (const line of stdout
    .split("\n")
    .map(value => value.trim())
    .filter(Boolean)) {
    try {
      const parsed = JSON.parse(line)
      if (parsed && typeof parsed === "object") events.push(parsed as Record<string, unknown>)
      else invalidLines.push(line)
    } catch {
      invalidLines.push(line)
    }
  }
  return { events, invalidLines }
}

function extractMetrics(events: Record<string, unknown>[]) {
  const eventTypes: string[] = []
  const itemTypes: string[] = []
  let usage: Record<string, number> = {}
  let finalAnswer = ""
  let toolCalls = 0
  let subagentCalls = 0

  for (const event of events) {
    if (typeof event.type === "string") eventTypes.push(event.type)
    if (event.type === "turn.completed" && event.usage && typeof event.usage === "object") {
      usage = Object.fromEntries(
        Object.entries(event.usage as Record<string, unknown>).filter(
          (entry): entry is [string, number] => typeof entry[1] === "number",
        ),
      )
    }
    if (event.type !== "item.completed" || !event.item || typeof event.item !== "object") continue
    const item = event.item as Record<string, unknown>
    const itemType = typeof item.type === "string" ? item.type : "unknown"
    itemTypes.push(itemType)
    if (itemType === "agent_message" && typeof item.text === "string") finalAnswer = item.text
    if (!["agent_message", "error", "reasoning"].includes(itemType)) toolCalls += 1
    const serialized = JSON.stringify(item)
    if (/spawn_agent|subagent|collaboration_tool_call/i.test(serialized)) subagentCalls += 1
  }

  return {
    usage,
    finalAnswer,
    eventTypes: countBy(eventTypes),
    itemTypes: countBy(itemTypes),
    toolCalls,
    subagentCalls,
  }
}

async function runProcess(command: string, args: string[]) {
  const started = performance.now()
  const processHandle = Bun.spawn([command, ...args], { stdout: "pipe", stderr: "pipe" })
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(processHandle.stdout).text(),
    new Response(processHandle.stderr).text(),
    processHandle.exited,
  ])
  return { stdout, stderr, exitCode, durationMs: Math.round(performance.now() - started) }
}

async function verifySkillVisibility(args: Args, runs: RunSpec[]) {
  if (runs.length === 0) throw new Error("no eval runs were selected")
  const probe = "Evidence evaluation preflight."
  const base = [
    "debug",
    "prompt-input",
    "-c",
    "features.hooks=false",
    "-c",
    `model=\"${args.model}\"`,
    "-c",
    `model_reasoning_effort=\"${args.reasoning}\"`,
  ]
  const disabled = `skills.config=[{path=\"${path.join(skillRoot, "SKILL.md")}\",enabled=false}]`
  const control = await runProcess(args.codexBin, [...base, "-c", disabled, probe])
  const enabled = await runProcess(args.codexBin, [...base, probe])
  const controlVisible = control.stdout.includes("evidence-work")
  const enabledVisible = enabled.stdout.includes("evidence-work")
  if (control.exitCode !== 0 || enabled.exitCode !== 0 || controlVisible || !enabledVisible) {
    throw new Error(
      `skill visibility preflight failed: control_exit=${control.exitCode} enabled_exit=${enabled.exitCode} control_visible=${controlVisible} enabled_visible=${enabledVisible}`,
    )
  }
  return { control_visible: controlVisible, enabled_visible: enabledVisible }
}

function redactRun(run: RunSpec): RunSpec {
  if (run.privacy_class !== "private") return run
  const redactedPrompt = "[PRIVATE PROMPT REDACTED]"
  const redactedPath = "[PRIVATE PATH REDACTED]"
  const privatePaths = new Set([run.cwd, ...run.read_roots].flatMap(value => [value, resolveFromRepo(value)]))
  return {
    ...run,
    prompt: redactedPrompt,
    cwd: redactedPath,
    read_roots: run.read_roots.map(() => redactedPath),
    command_args: run.command_args.map(value => {
      if (value === run.prompt) return redactedPrompt
      return privatePaths.has(value) ? redactedPath : value
    }),
  }
}

async function executeRun(args: Args, run: RunSpec): Promise<RunResult> {
  const runRoot = path.resolve(args.outDir, args.runId, "runs", run.id)
  await mkdir(runRoot, { recursive: true })
  const result = await runProcess(args.codexBin, run.command_args)
  await writeFile(path.join(runRoot, "events.jsonl"), result.stdout)
  await writeFile(path.join(runRoot, "stderr.log"), result.stderr)
  const parsed = parseEvents(result.stdout)
  const metrics = extractMetrics(parsed.events)
  const finalFile = path.join(runRoot, "final.md")
  let finalAnswer = metrics.finalAnswer
  try {
    const fromFile = await readFile(finalFile, "utf8")
    if (fromFile.trim()) finalAnswer = fromFile
    else await writeFile(finalFile, finalAnswer)
  } catch {
    await writeFile(finalFile, finalAnswer)
  }
  const metadata: RunResult & { invalid_event_lines: string[] } = {
    ...redactRun(run),
    exit_code: result.exitCode,
    duration_ms: result.durationMs,
    usage: metrics.usage,
    event_types: metrics.eventTypes,
    item_types: metrics.itemTypes,
    tool_calls: metrics.toolCalls,
    subagent_calls: metrics.subagentCalls,
    final_answer: finalAnswer,
    invalid_event_lines: parsed.invalidLines,
  }
  const { final_answer: _finalAnswer, ...persistedMetadata } = metadata
  await writeFile(path.join(runRoot, "metadata.json"), `${JSON.stringify(persistedMetadata, null, 2)}\n`)
  return metadata
}

function stableCandidateOrder(results: RunResult[], key: string): RunResult[] {
  return [...results].sort((left, right) => {
    const leftHash = createHash("sha256").update(`${key}:${left.id}`).digest("hex")
    const rightHash = createHash("sha256").update(`${key}:${right.id}`).digest("hex")
    return leftHash.localeCompare(rightHash)
  })
}

async function renderReports(args: Args, cases: EvalCase[], results: RunResult[]) {
  const runRoot = path.resolve(args.outDir, args.runId)
  const caseById = new Map(cases.map(item => [item.id, item]))
  const groups = new Map<string, RunResult[]>()
  for (const result of results) {
    const key = `${result.case_id}:r${result.repeat}`
    groups.set(key, [...(groups.get(key) ?? []), result])
  }

  const markdown: string[] = [
    "# Evidence Work Blind Comparison",
    "",
    "Score the candidates before opening `arm-key.json`.",
    "",
  ]
  const armKey: Record<string, Record<string, Arm>> = {}
  const ratings: Record<string, unknown>[] = []

  for (const [comparisonId, group] of groups) {
    const item = caseById.get(group[0].case_id)
    if (!item) continue
    const displayedPrompt = item.privacy_class === "private" ? "[PRIVATE PROMPT REDACTED]" : item.prompt
    markdown.push(
      `### Comparison ${comparisonId}`,
      "",
      `Prompt: ${displayedPrompt}`,
      "",
      `Expected mode: ${item.expected_mode}`,
      "",
      "Required context:",
    )
    if (item.required_context.length === 0) markdown.push("- (none)")
    for (const context of item.required_context) markdown.push(`- ${context}`)
    markdown.push("", "Success criteria:")
    for (const criterion of item.success_criteria) markdown.push(`- ${criterion}`)
    markdown.push("", "Forbidden claims:")
    if (item.forbidden_claims.length === 0) markdown.push("- (none)")
    for (const claim of item.forbidden_claims) markdown.push(`- ${claim}`)
    markdown.push("", "Critical failure conditions:")
    if (item.critical_failure_conditions.length === 0) markdown.push("- (none)")
    for (const condition of item.critical_failure_conditions) markdown.push(`- ${condition}`)
    markdown.push("")
    armKey[comparisonId] = {}
    const labels: string[] = []
    stableCandidateOrder(group, `${args.runId}:${comparisonId}`).forEach((candidate, index) => {
      const label = String.fromCharCode(65 + index)
      labels.push(label)
      armKey[comparisonId][label] = candidate.arm
      const displayedAnswer =
        item.privacy_class === "private"
          ? candidate.final_answer.replaceAll(item.prompt, "[PRIVATE PROMPT REDACTED]")
          : candidate.final_answer
      markdown.push(`## Candidate ${label}`, "", displayedAnswer.trim() || "(empty response)", "")
    })
    const candidateScores = Object.fromEntries(
      labels.map(label => [
        label,
        {
          target_specific: null,
          facts_supported_or_qualified: null,
          claim_types_separated: null,
          answers_actual_question: null,
          avoids_generic_padding: null,
          quality_justifies_cost: null,
          critical_failure: null,
          notes: "",
        },
      ]),
    )
    ratings.push({
      comparison_id: comparisonId,
      candidate_labels: labels,
      candidate_scores: candidateScores,
      overall_preference: null,
      notes: "",
    })
  }

  const usageTotals: Record<string, number> = {}
  for (const result of results) {
    for (const [name, value] of Object.entries(result.usage)) usageTotals[name] = (usageTotals[name] ?? 0) + value
  }
  const summary = {
    run_id: args.runId,
    mode: args.mode,
    execution: {
      planned: results.length,
      completed: results.filter(result => result.exit_code === 0).length,
      failed: results.filter(result => result.exit_code !== 0).length,
      total_tool_calls: results.reduce((sum, result) => sum + result.tool_calls, 0),
      total_subagent_calls: results.reduce((sum, result) => sum + result.subagent_calls, 0),
      usage: usageTotals,
    },
    ratings_status: "pending-human-review",
  }

  await writeFile(path.join(runRoot, "comparison.md"), `${markdown.join("\n").trim()}\n`)
  await writeFile(path.join(runRoot, "ratings.jsonl"), `${ratings.map(item => JSON.stringify(item)).join("\n")}\n`)
  await writeFile(path.join(runRoot, "arm-key.json"), `${JSON.stringify(armKey, null, 2)}\n`)
  await writeFile(path.join(runRoot, "summary.json"), `${JSON.stringify(summary, null, 2)}\n`)
}

async function summarizeRatings(runRoot: string) {
  const resolvedRoot = path.resolve(runRoot)
  const [ratingsText, armKeyText, summaryText] = await Promise.all([
    readFile(path.join(resolvedRoot, "ratings.jsonl"), "utf8"),
    readFile(path.join(resolvedRoot, "arm-key.json"), "utf8"),
    readFile(path.join(resolvedRoot, "summary.json"), "utf8"),
  ])
  const ratings = ratingsText
    .split("\n")
    .map(line => line.trim())
    .filter(Boolean)
    .map(line => JSON.parse(line) as Record<string, unknown>)
  const armKey = JSON.parse(armKeyText) as Record<string, Record<string, Arm>>
  const summary = JSON.parse(summaryText) as Record<string, unknown>
  const expectedComparisonIds = Object.keys(armKey)
  const actualComparisonIds = ratings.map(rating => String(rating.comparison_id ?? ""))
  const actualComparisonSet = new Set(actualComparisonIds)
  const missingComparisons = expectedComparisonIds.filter(id => !actualComparisonSet.has(id))
  const unexpectedComparisons = [...actualComparisonSet].filter(id => !armKey[id])
  const duplicateComparisons = actualComparisonIds.filter((id, index) => actualComparisonIds.indexOf(id) !== index)
  const rubricFields = [
    "target_specific",
    "facts_supported_or_qualified",
    "claim_types_separated",
    "answers_actual_question",
    "avoids_generic_padding",
    "quality_justifies_cost",
  ]
  const preferenceByArm: Record<string, number> = { control: 0, auto: 0, forced: 0, "auto-hook": 0, tie: 0 }
  const knownArms: Arm[] = ["control", "auto", "forced", "auto-hook"]
  const rubricPassesByArm = Object.fromEntries(
    knownArms.map(arm => [arm, Object.fromEntries(rubricFields.map(field => [field, 0]))]),
  ) as Record<Arm, Record<string, number>>
  const candidatesByArm = Object.fromEntries(knownArms.map(arm => [arm, 0])) as Record<Arm, number>
  const criticalFailuresByArm = Object.fromEntries(knownArms.map(arm => [arm, 0])) as Record<Arm, number>
  let complete = true
  let autoControlComparisons = 0
  let autoWins = 0
  let controlWins = 0
  let autoControlTies = 0
  if (missingComparisons.length > 0 || unexpectedComparisons.length > 0 || duplicateComparisons.length > 0) {
    complete = false
  }

  for (const rating of ratings) {
    const comparisonId = String(rating.comparison_id ?? "")
    const preference = rating.overall_preference
    const comparisonArms = Object.values(armKey[comparisonId] ?? {})
    const preferenceArm =
      typeof preference === "string" && preference !== "tie" ? armKey[comparisonId]?.[preference] : undefined
    if (preference === "tie") preferenceByArm.tie += 1
    else if (preferenceArm) {
      preferenceByArm[preferenceArm] += 1
    } else complete = false
    if (comparisonArms.includes("auto") && comparisonArms.includes("control")) {
      autoControlComparisons += 1
      if (preferenceArm === "auto") autoWins += 1
      else if (preferenceArm === "control") controlWins += 1
      else if (preference === "tie") autoControlTies += 1
    }

    if (!rating.candidate_scores || typeof rating.candidate_scores !== "object") {
      complete = false
      continue
    }
    const candidateScores = rating.candidate_scores as Record<string, unknown>
    const expectedLabels = Object.keys(armKey[comparisonId] ?? {}).sort()
    const actualLabels = Object.keys(candidateScores).sort()
    if (
      expectedLabels.length === 0 ||
      expectedLabels.length !== actualLabels.length ||
      expectedLabels.some((label, index) => label !== actualLabels[index])
    ) {
      complete = false
      continue
    }
    for (const [label, rawScore] of Object.entries(candidateScores)) {
      const arm = armKey[comparisonId]?.[label]
      if (!arm || !rawScore || typeof rawScore !== "object") {
        complete = false
        continue
      }
      const score = rawScore as Record<string, unknown>
      candidatesByArm[arm] += 1
      if (score.critical_failure === true) criticalFailuresByArm[arm] += 1
      else if (score.critical_failure !== false) complete = false
      for (const field of rubricFields) {
        if (score[field] === true) rubricPassesByArm[arm][field] += 1
        else if (score[field] !== false) complete = false
      }
    }
  }

  summary.ratings_status = complete ? "complete" : "partial"
  summary.human_ratings = {
    comparisons: ratings.length,
    missing_comparisons: missingComparisons,
    unexpected_comparisons: unexpectedComparisons,
    duplicate_comparisons: [...new Set(duplicateComparisons)],
    preference_by_arm: preferenceByArm,
    auto_vs_control: {
      comparisons: autoControlComparisons,
      auto_wins: autoWins,
      control_wins: controlWins,
      ties: autoControlTies,
      preference_rate: autoControlComparisons === 0 ? 0 : autoWins / autoControlComparisons,
      loss_rate: autoControlComparisons === 0 ? 0 : controlWins / autoControlComparisons,
    },
    candidates_by_arm: candidatesByArm,
    critical_failures_by_arm: criticalFailuresByArm,
    rubric_passes_by_arm: rubricPassesByArm,
    rubric_pass_rates_by_arm: Object.fromEntries(
      knownArms.map(arm => [
        arm,
        Object.fromEntries(
          rubricFields.map(field => [
            field,
            candidatesByArm[arm] === 0 ? 0 : rubricPassesByArm[arm][field] / candidatesByArm[arm],
          ]),
        ),
      ]),
    ),
  }
  await writeFile(path.join(resolvedRoot, "summary.json"), `${JSON.stringify(summary, null, 2)}\n`)
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`)
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.summarizeRun) {
    await summarizeRatings(args.summarizeRun)
    return
  }
  const cases = await loadCases(path.resolve(args.cases), "sanitized")
  if (args.privateCases) cases.push(...(await loadCases(path.resolve(args.privateCases), "private")))
  const combinedIds = new Set<string>()
  for (const item of cases) {
    if (combinedIds.has(item.id)) throw new Error(`duplicate id across public/private cases: ${item.id}`)
    combinedIds.add(item.id)
  }
  const unknownCaseIds = args.caseIds.filter(id => !combinedIds.has(id))
  if (unknownCaseIds.length > 0) throw new Error(`unknown case ids: ${unknownCaseIds.join(",")}`)
  const runs = buildRuns(cases, args)
  const caseCount = new Set(runs.map(run => run.case_id)).size
  const plan = {
    mode: args.mode,
    run_id: args.runId,
    repo_root: repoRoot,
    skill_path: path.join(skillRoot, "SKILL.md"),
    case_count: caseCount,
    run_count: runs.length,
    runs: runs.map(redactRun),
  }
  if (args.dryRun) {
    process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`)
    return
  }
  const runRoot = path.resolve(args.outDir, args.runId)
  await mkdir(runRoot, { recursive: true })
  await writeFile(path.join(runRoot, "plan.json"), `${JSON.stringify(plan, null, 2)}\n`)
  const preflight = await verifySkillVisibility(args, runs)
  await writeFile(path.join(runRoot, "preflight.json"), `${JSON.stringify(preflight, null, 2)}\n`)
  const results: RunResult[] = []
  for (const run of runs) results.push(await executeRun(args, run))
  await renderReports(args, cases, results)
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
})
