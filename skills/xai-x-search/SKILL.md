---
name: xai-x-search
description: A general-purpose research skill that uses xAI (Grok) x_search to quickly investigate X/Web information across any topic and store results with evidence URLs.
disable-model-invocation: true
metadata:
  { "openclaw": { "emoji": "🔎", "requires": { "config": ["skills.entries.xai-x-search.enabled"], "bins": ["bun"] } } }
---

# xAI X Search

## Overview

General-purpose research skill that uses xAI Responses API + `x_search` directly. It is not limited to article writing tasks; it quickly collects “key points + evidence URLs” for any topic.

## When To Use

- You need to quickly check the latest discussions or primary information on X.
- You want to run cross-domain research on new features, competitors, spec changes, or trends.
- You need to save research logs (`json/txt/md`) for follow-up work.

## Input

- The topic to investigate (one sentence is enough).

When details are missing, ask:

- “What should I research with x_search?”

## Workflow

1. Finalize the query
   Define the topic to investigate in one sentence.

2. Run Grok delegate
   Execute with the following command.

- `bun skills/xai-x-search/scripts/xai_x_search.ts --query "..."`

Main options:

- `--locale ja|global`
- `--days 30`
- `--out-dir data/xai-x-search`
- `--dry-run` (check payload without calling the API)

3. Review results
   Check the saved `.md/.txt/.json` files and standard output, then rerun with an adjusted query if needed.

## Output

Store the following files in `data/xai-x-search/`.

- `YYYYMMDD_HHMMSSZ_<locale>_x_search.md`
- `YYYYMMDD_HHMMSSZ_<locale>_x_search.txt`
- `YYYYMMDD_HHMMSSZ_<locale>_x_search.json`

Notes:

- No fixed template formatting is required. Save the model output as-is.
- Keep the reference URLs in the results.

## Hand-off

- Pass the research results directly into planning, specification, writing, or validation tasks.
