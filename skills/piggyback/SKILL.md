---
name: piggyback
description: >-
  One interface for handing a task to another agent's CLI with the model that
  fits the job, instead of spending this session's own budget. Named profiles
  pick the model: `fast` for mechanical text work, `reasoning` for analysis worth
  a stronger model, `long-context` for inputs that do not fit, `code` and
  `review` for work that needs the workspace.

  Reach for it when doing the work inline is expensive or impossible: this
  session's own allowance is exhausted or being conserved, the material is still
  large after filtering, or the job needs many independent calls. Also use it
  when the user asks to run something "on Cursor", "on Antigravity", "on the free
  tier", or to route light work somewhere cheaper.

  Filter with grep, sed, or head before reaching for it. On structured text,
  narrowing with shell tools and reasoning over what is left beats a provider
  round trip, and the reduced remainder is usually small enough that outsourcing
  no longer pays.

  Do not use for work that needs this conversation's accumulated context, for a
  judgement the caller must own, or as a way to escape a refusal. Exhausting the
  whole provider chain is a normal outcome to report, not to work around.
---

# Piggyback

Ride someone else's free tier: hand one self-contained task to whichever
provider still has allowance left.

`scripts/piggyback.sh` is the only entry point. It walks an ordered chain, skips
providers that are out of allowance, and returns the first real answer. Do not
call a provider CLI directly: the exit-code contract below is the only reliable
way to tell an exhausted allowance apart from a stale login or a genuine failure,
and re-deriving that from error text on every call is the mistake this skill
exists to prevent.

## When the main agent should reach for this

Outsource work whose answer needs no judgement you would want to review:
reformatting, extracting, summarising, classifying, drafting text. Do not
outsource anything where being wrong is expensive and hard to notice.

Two questions decide the capability class, and the first one is usually the
answer.

**Does the model have to decide what to run next from what it just saw?**
If no — you already know the command — run it yourself and send only the
_interpretation_. Starting an agent to run `just check` pays agent overhead for
shell you could have run directly. The mechanical half is deterministic and
free; only the reading of the failures needs a model:

```bash
just check 2>&1 | tail -200 >/tmp/out.txt
{ echo 'Group these failures into formatter-fixable and real type errors:'; cat /tmp/out.txt; } >/tmp/task.txt
skills/piggyback/scripts/piggyback.sh --prompt-file /tmp/task.txt
```

**Whose context has to hold the bulk?** Assembling the prompt in a file keeps
the log out of your own context entirely. The saving is not the reading — it is
not having to reason over 5,000 lines.

Default to `inference`. The agentic pool is a few tens of requests per day
across all three providers; the inference pool is around a thousand. Spending an
agentic request on text reformatting means the only quota that can edit files is
gone when you actually need it. Reach for `agentic` when the task genuinely
needs the workspace: run a command, read the file it names, then decide.

Keep inputs small. Groq's free tier allows 8K tokens per minute, so filter with
`grep`/`tail` before sending rather than shipping a whole log.

## Measured routing behaviour

`scripts/eval-routing.sh` runs a host agent against fixtures with every provider
stubbed, so it measures the routing decision without spending any free-tier
quota. Claude Code, six cases, n=1 per cell:

| case                                 | expected | routed |
| ------------------------------------ | -------- | ------ |
| "summarise this on a free provider"  | yes      | yes    |
| triage `just check` failures         | yes      | varies |
| extract unresolved errors from a log | yes      | no     |
| reformat log lines into a table      | yes      | no     |
| needs earlier conversation context   | no       | no     |
| a design judgement                   | no       | no     |

Read this honestly: **autonomous routing barely happens.** The only reliable
trigger is the user asking for it. One case flipped between identical runs, so
n=1 cannot separate description wordings.

The negative cases never misfired, which is the property worth protecting.

More usefully, the refusals were _correct_. Given a 10-line log the agent said
it read it directly because it was ten lines. Given a 1,229-line log it ran
`grep -n`, `grep -A1`, `sort | uniq -c`, narrowed to 16 ERROR lines, and reasoned
over those — the bulk never entered its context either, and the answer was exact
in a way an LLM round trip would not have been.

So the honest scope is narrower than "outsource mechanical text work". Shell
tools already keep the bulk out of context, and they are free, instant, and
exact. This skill earns its place when the reduction step is not available or not
enough: the host allowance is genuinely gone, what remains after filtering is
still large, the work needs many independent calls, or the user asked.

## Profiles: which model for which job

This is the part that replaces reaching for a cheap model tier by hand. A
profile names the model decision once, so a caller never carries provider model
ids around:

```bash
skills/piggyback/scripts/piggyback.sh --profile fast --prompt '...'
skills/piggyback/scripts/piggyback.sh --list-profiles
```

| profile        | capability | for                                                           |
| -------------- | ---------- | ------------------------------------------------------------- |
| `fast`         | inference  | triage, extraction, reformatting. Cheapest, largest allowance |
| `reasoning`    | inference  | analysis worth a stronger model                               |
| `long-context` | inference  | inputs that do not fit a small context (1M-token models)      |
| `code`         | agentic    | writing code; needs the workspace                             |
| `review`       | agentic    | judgement over code: review, design critique                  |

Profiles live in `profiles.conf`, one per line:

```text
name|capability|provider[=model],provider[=model],...
```

`=` separates provider from model because model ids contain colons and slashes
(`nvidia/nemotron-3.5-lightning:free`). A **bare provider name uses that
provider's own default**, which is the only thing that works for Cursor: its
Free plan rejects every named model and routes Auto.

The ordinary availability fallback still applies inside a profile, so a profile
is a preference list, not a single choice. An explicit `--model` outranks the
profile for that one call, and `--write` outranks the profile's capability.

Rosters change without warning. After editing `profiles.conf`, run `--probe`:
it checks each configured default against the provider's live model list without
spending a request.

## Exit-code contract

Every adapter and the router speak exactly these codes.

| Code | Meaning                                                         | Effect on routing             |
| ---- | --------------------------------------------------------------- | ----------------------------- |
| `0`  | Success                                                         | The answer is on stdout       |
| `1`  | The provider failed on the task itself                          | Advances, bounded (see below) |
| `2`  | Usage error                                                     | Stops the chain               |
| `3`  | Allowance or rate limit exhausted                               | Advances to the next provider |
| `4`  | Not authenticated / no key / nothing usable                     | Advances                      |
| `5`  | Binary or dependency missing, or a model the account cannot use | Advances                      |
| `6`  | Timed out                                                       | Advances                      |
| `7`  | Router: no provider in the chain could serve                    | Terminal                      |

`3`–`6` always advance the chain. A `1` also advances, but only up to
`--max-failures` (default 2).

That bound is the compromise. A live run proved that halting on any `1` is
wrong: `gemini-cli` returned an unrecognised tier error and blocked every
remaining provider. The router cannot reliably tell "the task is bad" from
"this provider is broken in a way the classifier does not know", so it keeps
going — but not far enough for a genuinely bad prompt to burn the whole chain.
A task failure never sets a cooldown: nothing is wrong with that provider's
availability.

`7` is terminal for this skill. **Never retry it, and never silently do the task
yourself** — the caller decides whether the work is worth its own budget.

## Failure classification

A provider's stderr is matched, case-insensitively, into one bucket. This runs
**only on a non-zero exit**: an agent transcript can mention a rate limit it
already retried past, and the retired gemini-cli logged exactly that.

| Bucket        | Exit | Examples seen in the wild                                                            |
| ------------- | ---- | ------------------------------------------------------------------------------------ |
| `stale-model` | `5`  | `model_not_found` — Groq dropped the Llama chat models without notice                |
| `auth`        | `4`  | `IneligibleTierError` (retired Gemini tier), `Named models unavailable` (plan limit) |
| `quota`       | `3`  | `429`, `rate limit`, `you have hit your free requests limit`                         |
| `unavailable` | `6`  | `410 github_models_retirement_brownout`, `503`, `overloaded`                         |
| `failed`      | `1`  | anything else — treated as an answer about the task                                  |

Each of the first four is a reason to move on. Getting one of them into the
`failed` bucket is the bug that stalls a chain, so a new pattern belongs here
rather than in an adapter.

## Capability classes

| Class       | Can do                                       | Providers                    |
| ----------- | -------------------------------------------- | ---------------------------- |
| `agentic`   | Read the workspace, edit files, run commands | antigravity, cursor, copilot |
| `inference` | Text in, text out only                       | groq, openrouter, mistral    |

`agentic` ⊇ `inference`: an agentic provider can answer a question, but an
inference-only provider must never receive an editing task. That gate is
enforced in the router, because the failure mode otherwise is a confident
description of work that never happened.

Inference requests deliberately try the inference-only providers first. An
agentic allowance can answer a question, but spending it on something Groq could
have done wastes the only quota that can edit files.

## Workflow

### 1. Check what is available

```bash
skills/piggyback/scripts/piggyback.sh --probe
```

Probes spend no inference requests: every adapter checks credentials or a free
`models` listing, never a completion. `--status` shows the cooldown table.

### 2. Write a self-contained prompt

No provider sees this conversation. The prompt must carry the objective, the
working directory, the exact files or commands, whether edits are allowed, and
what "done" looks like. For `inference` providers it must also carry the code
itself — they cannot read the disk.

### 3. Run it

```bash
skills/piggyback/scripts/piggyback.sh --prompt 'Summarize this diff in 3 lines: ...'
```

Agentic work, read-only:

```bash
skills/piggyback/scripts/piggyback.sh --capability agentic \
  --workspace /path/to/repo \
  --prompt 'Read src/auth/session.ts and list every path returning an expired session. Cite file:line.'
```

Editing, only when the caller explicitly authorized writes:

```bash
skills/piggyback/scripts/piggyback.sh --write --workspace /path/to/repo \
  --prompt-file /tmp/task.md
```

### 4. Report

Return the answer, which provider served it, and what the exit code meant.

## Options

| Option                                          | Default     | Notes                                              |
| ----------------------------------------------- | ----------- | -------------------------------------------------- |
| `--prompt` / `--prompt-file`                    | —           | The task. One is required.                         |
| `--capability inference\|agentic`               | `inference` | `agentic` is needed to touch the workspace.        |
| `--write`                                       | off         | Allows file edits. Implies `--capability agentic`. |
| `--provider <name>`                             | —           | Pin one provider and do not fall back.             |
| `--chain <a,b,c>`                               | see below   | Override the order.                                |
| `--model <id>`                                  | unset       | Usually leave unset; see below.                    |
| `--workspace <path>`                            | cwd         | Working directory for agentic providers.           |
| `--timeout <seconds>`                           | `900`       | Per-provider wall-clock limit.                     |
| `--max-failures <n>`                            | `2`         | Give up after this many task failures.             |
| `--no-cooldown`                                 | off         | Ignore and do not write cooldown state.            |
| `--json`                                        | off         | `{"provider":…,"exit":…,"answer":…}`               |
| `--probe` / `--status` / `--clear-cooldown [p]` | —           | Availability, cooldown table, reset.               |

Default chains, overridable with `PIGGYBACK_CHAIN_INFERENCE`,
`PIGGYBACK_CHAIN_AGENTIC`, or `PIGGYBACK_CHAIN`:

```text
inference: groq, openrouter, mistral, antigravity, cursor, copilot
agentic:   antigravity, cursor, copilot
```

## Configuration

Provider keys go in `skills/piggyback/.env`, which the repository root already
gitignores. Copy the example and fill in whichever providers you have:

```bash
cp skills/piggyback/.env.example skills/piggyback/.env
```

The file is parsed, not sourced — it is configuration, and sourcing it would
execute whatever it contains. Anything already exported wins, so a real
environment variable always overrides the file. `PIGGYBACK_ENV_FILE` points
somewhere else.

## Cooldown

A provider that just reported an exhausted allowance will report it again on the
next task. Without a cooldown, every later request pays the latency of walking
the dead part of the chain — the main cost of stitching small free tiers
together.

State lives in `${XDG_STATE_HOME:-~/.local/state}/piggyback/<provider>.cooldown`
as one epoch expiry per provider. Defaults: quota 1h, auth 15m, missing 1h,
timeout 10m — all overridable via `PIGGYBACK_COOLDOWN_QUOTA` and friends. A
provider that reports its own backoff (OpenRouter sends `retry_after_seconds`
on a contended free model) overrides the table: a 5-second hiccup must not
sideline a provider for an hour. They are
deliberately shorter than a daily reset: a wrong guess costs one wasted probe,
while too long a cooldown silently removes a recovered provider.

## Antigravity replaced the Gemini CLI

`gemini-cli` is no longer a provider here. Gemini Code Assist's OAuth tier for
individuals was discontinued and now answers
`IneligibleTierError: This client is no longer supported ... migrate to the
Antigravity suite`. The `agy` CLI is that migration path, and it is a better
fit anyway: `agy models` is a real availability check that spends no request,
where the gemini adapter could only guess from credentials on disk.

One sharp edge: `agy --print` takes the prompt as its **value**. Passing it bare
makes agy swallow the following flag as the prompt and answer the wrong
question, so the adapter always writes `--print=<prompt>`.

## `--model` is sticky on Cursor

`cursor-agent` persists `--model` account-side, not in a local config file. One
call with a named model pins that choice for every later run, from any client.
On a Free plan that is a trap: named models are rejected outright with
`ActionRequiredError: Named models unavailable. Free plans can only use Auto`,
so a single experiment leaves the provider failing every request afterwards.

The adapter therefore sends `--model auto` on every run rather than omitting the
flag. That makes each call self-contained and repairs a selection some other
client left behind. Verified: passing a named model broke every subsequent run
until an explicit `auto` restored it.

## Why `--model` is usually left unset

Each adapter has a default that matches what its free tier actually exposes.
`cursor-agent models` lists 200+ ids on a Free account — Opus 5, GPT-5.6,
Gemini 3.1 Pro — but the list is aspirational: gating happens at request time,
and every named one is refused. Auto is the only thing a Free plan can route. OpenRouter's `:free` roster changes monthly. Pass
`--model` only after confirming the id is live for that account.

## Adding a provider

This is the extensibility surface. A provider is one executable in
`scripts/providers/<name>.sh` implementing three verbs:

```bash
<adapter> capabilities              # prints 'agentic' or 'inference'
<adapter> probe                     # exit 0 available, 3/4/5 unavailable. Spends no quota.
<adapter> run --prompt-file <path> [--write] [--model <id>] [--workspace <path>] [--timeout <n>]
                                    # answer on stdout, exit per the contract
```

The router discovers adapters by filename and never hardcodes a provider, so
dropping the file in and adding the name to a chain is the whole change.

For anything speaking the OpenAI chat-completions shape, the body is already
written — the adapter is four variables:

```bash
PROVIDER=example
PIGGYBACK_BASE_URL="${PIGGYBACK_EXAMPLE_BASE_URL:-https://api.example.com/v1}"
PIGGYBACK_KEY_VAR="EXAMPLE_API_KEY"
PIGGYBACK_DEFAULT_MODEL="${PIGGYBACK_EXAMPLE_MODEL:-example-small}"

source "${HERE}/../lib/openai_provider.sh"
piggyback_openai_provider_main "$@"
```

`lib/common.sh` supplies the exit codes, the failure classifier, the timeout
watchdog, cooldown state, and `piggyback_openai_chat`. Classify a transcript **only on
a non-zero exit**: some CLIs log transient "quota exhausted" lines during
successful internal retries, and Gemini CLI does exactly this in headless mode.

After adding one, extend `scripts/tests/piggyback.test.sh` — the loop over
`providers/*.sh` already asserts the contract for every adapter present.

## Constraints

- Never call a provider CLI directly. Always go through the router.
- Never pass `--write` unless the caller explicitly authorized edits for this
  task. `--write` lets an agentic provider edit files and run shell commands
  outside this host's permission system.
- Never send secrets, credentials, or `.env` contents in a prompt. It leaves
  this machine, and free tiers commonly reserve the right to train on input.
- Never retry a `7`. One task, one pass through the chain.

## Provider setup

Verified against live endpoints on 2026-09-01.

| Provider    | Free tier                                                             | Setup                                                             | Status         |
| ----------- | --------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------- |
| groq        | 30/min, ~1,000/day, 8K tokens/min                                     | `GROQ_API_KEY` from console.groq.com                              | **round trip** |
| openrouter  | 20/min, 50/day on `:free`                                             | `OPENROUTER_API_KEY`; the `:free` roster shifts, so pin a live id | **round trip** |
| mistral     | free Experiment tier, limits unpublished                              | `MISTRAL_API_KEY`                                                 | **round trip** |
| antigravity | Gemini Flash/Pro, Claude Sonnet/Opus 4.6, GPT-OSS; limits unpublished | `agy login`                                                       | **round trip** |
| cursor      | Hobby, unpublished limits                                             | `cursor-agent login`                                              | auth expired   |
| copilot     | 50/month                                                              | `npm i -g @github/copilot`, then run `copilot` once               | not installed  |

Model rosters change without notice, so `probe` checks each configured default
against the live `/models` list rather than letting a run discover it. Groq's
chat models today are `openai/gpt-oss-20b` (the default), `openai/gpt-oss-120b`,
and `qwen/qwen3.8-27b`.

OpenRouter needs more care. Its `:free` models share an upstream pool, so a
model that lists fine can still answer `429 upstream_provider_shared_pool` with
`retry_after_seconds: 5` — contention, not an exhausted allowance. The router
honours that number instead of the flat quota hour. Not every listed `:free`
model is usable either: some are restricted and answer with an access error.
The default is `nvidia/nemotron-3.5-lightning:free`, confirmed working.

## Providers that were removed

Two adapters were deleted rather than left failing, because neither can recover:

- **gemini-cli** — Gemini Code Assist's OAuth tier for individuals was
  discontinued; it answers `IneligibleTierError` pointing at Antigravity, which
  replaced it here.
- **GitHub Models** — fully retired on 2026-07-30. The playground, catalog,
  inference API and BYOK endpoints are gone for every customer. It still answers
  `410 github_models_retirement_brownout`, but that wording is a leftover: the
  brownouts were the 16 and 23 July rehearsals, and this is the permanent
  shutdown. GitHub points users at Microsoft Foundry or Copilot.

A dead provider left in the chain is not harmless. Each cooldown expiry spends
another round trip discovering the same thing.

## What this skill is not for

A local model server is not a provider here. It spends no allowance, but it
spends the machine's own CPU and thermal budget, and those are different
budgets with different tradeoffs — a chain that silently falls back onto the
laptop's fans is not the same promise as one that falls back onto someone
else's free tier. Local inference is configured separately; this repository
already routes it through `codex/agents/qwen_worker.toml`.

Anything unconfigured reports `4` or `5` and is skipped, so a partially set up
chain works exactly as well as its configured members allow.
