---
name: pr-ui-screenshot
description: >-
  Capture before/after and all-locale UI screenshots for a PR, upload them to GitHub, and
  rewrite only the screenshot section of the PR body. Use when a frontend change alters UI
  or wording and the PR needs comparison images, or when the user asks to attach, update,
  or regenerate PR screenshots.
---

# PR UI screenshots

Turns a frontend diff into the screenshot section of a PR body: work out what changed,
shoot it at the merge-base and at HEAD, shoot every locale when wording moved, verify the
images are real, upload them to GitHub, and replace that one section.

Runs end to end without confirmation. The safety net is Phase 4 — nothing is uploaded and
the PR body is never touched unless the images pass validation.

## Prerequisites

- `git`, `gh` (authenticated), and `node` on PATH. Nothing else — the scripts decode
  PNGs with node's built-in `zlib`, so there is no ImageMagick/`jq`/`curl` dependency.
- Playwright installed **in the target repo** (`pnpm exec playwright install chromium`).
  The scripts resolve it from there, not from this skill.
- A saved GitHub session for uploads. First time only:
  `node <skill>/scripts/upload-assets.mjs --login`
- An open PR for the current branch.

Below, `<skill>` is this directory and `<w>` a scratch dir (`$TMPDIR/pr-ui-screenshot`).

## Phase 0: Resolve config

```bash
<skill>/scripts/resolve-config.mjs --explain > <w>/config.json
```

Layers, later winning: bundled `presets/default.json` → `presets/<owner>-<repo>.json` →
`<repo>/.claude/pr-ui-screenshot.json` → `<repo>/.agents/pr-ui-screenshot.json` →
`$PR_UI_SCREENSHOT_CONFIG`.

Project settings belong at `<repo>/.claude/pr-ui-screenshot.json`, committed to the repo
they describe — that keeps a private codebase's routes, locales and cookies out of this
skill. See [references/config.md](references/config.md) for the keys.

If `dev.command`, `locales`, or `section.heading` are clearly wrong for the repo and no
project config exists, write one and tell the user you did. Do not guess silently.

## Phase 1: Decide what to capture

**Read [references/capture-targets.md](references/capture-targets.md) before this step.**
It is the judgement-heavy part and the one that makes runs wrong.

In short: diff against the merge-base, classify the changed paths using `detect.*` from
the config, then trace changed components and translation keys to routes that actually
render them. Write `<w>/manifest.json` in the shape documented in
[references/manifest.md](references/manifest.md).

Rules that matter:

- Translation files changed → the all-locale table is required.
- Existing UI changed → before/after is required; capture the base side.
- Genuinely new UI → `"captureBase": false`, which renders `---` in the 旧 cell.
- Only logic/tests/types changed → produce nothing, tell the user, stop.

## Phase 2: Serve HEAD and the merge-base

```bash
head_url=$(<skill>/scripts/serve.sh --dir "$(git rev-parse --show-toplevel)" \
  --port "$(<skill>/scripts/resolve-config.mjs --get dev.port)" \
  --command "$(<skill>/scripts/resolve-config.mjs --get dev.command)" \
  --timeout "$(<skill>/scripts/resolve-config.mjs --get dev.readyTimeoutSec)" --pid-file <w>/head.pid)

base_dir=$(<skill>/scripts/base-worktree.sh --install "$(<skill>/scripts/resolve-config.mjs --get install.command)")
base_url=$(<skill>/scripts/serve.sh --dir "$base_dir" \
  --port "$(<skill>/scripts/resolve-config.mjs --get dev.basePort)" \
  --command "$(<skill>/scripts/resolve-config.mjs --get dev.command)" \
  --timeout "$(<skill>/scripts/resolve-config.mjs --get dev.readyTimeoutSec)" --pid-file <w>/base.pid)
```

`serve.sh` reuses a server that already answers on the port. `base-worktree.sh` checks
out the merge-base detached under `$TMPDIR` and shares `node_modules` when the lockfile
is unchanged; the repo's own working tree is never modified. Skip the base server
entirely when every pair is `captureBase: false`.

## Phase 3: Capture

```bash
node <skill>/scripts/capture.mjs --config <w>/config.json --manifest <w>/manifest.json \
  --base-url "$head_url" --side head
node <skill>/scripts/capture.mjs --config <w>/config.json --manifest <w>/manifest.json \
  --base-url "$base_url" --side base
```

Runs at `deviceScaleFactor: 2` with animations disabled, seeds auth cookies before the
first navigation, and frames `selector` with padding — growing the viewport rather than
zooming out, so wording stays readable. Locale shots are taken on the head side only.

Set the env var named by `auth.cookies[].valueEnv` first if any target needs login.
Debug a single target with `--headed --only <id>`.

## Phase 4: Validate — the gate

```bash
<skill>/scripts/validate.mjs --manifest <w>/manifest.json
```

Fails on missing or unreadable files, images below the size floor, blank images, a
before/after pair that is **pixel-identical**, and a locale set where every locale
rendered the same.

A failure here is a real finding, not noise. Identical before/after means the captured
screen does not contain the change; identical locales mean the locale never switched.
Fix the manifest and re-capture. Do not lower the thresholds to get past it, and do not
proceed to Phase 5 on a failing manifest.

## Phase 5: Upload

```bash
node <skill>/scripts/upload-assets.mjs --config <w>/config.json --manifest <w>/manifest.json \
  --repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
  --pr "$(gh pr view --json number --jq .number)"
```

GitHub has no API for `user-attachments`, so this drives a logged-in browser session and
borrows the PR's comment box as an upload form. **Nothing is posted** — the draft is
cleared after each file and Comment is never clicked. Shots that already have a `url` are
skipped, so a partial run is safe to repeat. If any upload fails the script exits
non-zero and the PR body is left alone.

## Phase 6: Rewrite the section

```bash
gh pr view --json body --jq .body > <w>/body.md
node <skill>/scripts/render-section.mjs --config <w>/config.json \
  --manifest <w>/manifest.json --out <w>/section.md
node <skill>/scripts/replace-section.mjs --config <w>/config.json \
  --body <w>/body.md --section <w>/section.md --out <w>/new-body.md
diff <w>/body.md <w>/new-body.md
<skill>/../create-pr/scripts/pr-body-update.sh --file <w>/new-body.md
```

`render-section.mjs` fills the template named by `section.template`
(`templates/default.md`, or `templates/ja-before-after-locales.md` for the Japanese
旧/新 layout) — edit that file, or point `section.template` at your own, to change the
layout. `replace-section.mjs` swaps only the lines from `section.heading` to the next
same-level heading; it refuses to run on a duplicated heading and refuses when the
template's heading disagrees with the config. Everything else in the body, including
CodeRabbit's block and CRLF line endings, is preserved byte for byte.

Reuse `create-pr`'s `pr-body-update.sh`: it updates via GraphQL and verifies the result.

## Phase 7: Clean up and report

```bash
<skill>/scripts/serve.sh --stop --pid-file <w>/head.pid
<skill>/scripts/serve.sh --stop --pid-file <w>/base.pid
<skill>/scripts/base-worktree.sh --remove
```

Only stop servers this run started. Keep the worktree if more runs are expected — reusing
it skips the slow first compile.

Report: which screens were captured, at which viewport and locales, the PR URL, and
anything you deliberately left out (a route you could not reach, a locale that needs
login). If validation failed and you stopped, say that plainly — do not present a partial
run as finished.

## Notes

- Never lower a validation threshold to make a run pass.
- Never click Comment during upload.
- The session file holds live GitHub cookies. It is mode 600 and must not be committed.
- Templates are prettier-ignored on purpose; their block tags must stay on their own lines.
- Config keys: [references/config.md](references/config.md).
- More detail: [references/troubleshooting.md](references/troubleshooting.md).
