# Deciding what to capture from a diff

This is the part no script can do for you: turning `git diff` into a list of screens.
Get it wrong and the run still "succeeds" — it just uploads pictures of the wrong thing.
The `before == after` check in `validate.mjs` exists to catch exactly that mistake.

## 1. Classify the diff

```bash
base="$(git merge-base "origin/$(gh pr view --json baseRefName --jq .baseRefName)" HEAD)"
git diff --name-only "$base"...HEAD
git diff "$base"...HEAD -- <the interesting paths>
```

Match the changed paths against `detect.translation`, `detect.component`, and
`detect.route` from the resolved config.

| What changed                       | What you owe the PR       |
| ---------------------------------- | ------------------------- |
| Translation files only             | the all-locales table     |
| A component's markup or styles     | the before/after table    |
| Both                               | both tables               |
| Only logic, tests, types, comments | nothing — say so and stop |

Do not produce a table you have no changes for. An empty `| 旧 | 新 |` header with no
rows is worse than omitting the section.

## 2. Translation changes → which screen shows the string

The changed keys are the anchor. For a repo whose translation keys are the source
strings themselves rather than dotted ids, take the changed JSON keys and grep for them:

```bash
git diff "$base"...HEAD -- 'locale/ja/*.json' | rg '^[+-]\s+"' | head -40
rg -F 'その文言' --glob '*.tsx' -l
```

Then walk from that component to a route that renders it. Only add a locale row for a
screen where the changed copy is actually visible.

## 3. Component changes → which route renders it

```bash
rg -F "ComponentName" --glob '*.tsx' -l          # importers
```

Follow importers until you hit a file under the router directory, then convert the file
path to a URL. For a Next.js pages router: `pages/account/notifications.tsx` →
`/account/notifications`; `pages/[username]/index.tsx` → `/<a real username>`.

Dynamic segments need a real value. Pick one that exists on the dev server's backend and
that renders the changed component; hard-code it in `path`.

## 4. Reaching states that are not a bare URL

Modals, drawers, tabs, and error states need `setup` steps. Keep them minimal and
deterministic — every step is a chance for the base-side capture to diverge for reasons
unrelated to the diff.

If a screen needs login, set the auth cookie env var named by `auth.cookies[].valueEnv`
before running. Capture logs `! cookie ... skipped` when it is missing, and you will
usually get a redirect to the top page instead of the screen you wanted.

## 5. Before/after honesty

- Brand-new UI that cannot exist on the base commit: set `"captureBase": false`. The
  renderer emits `---` in the 旧 cell, matching existing practice in the repo.
- Changed existing UI: always capture base. If `validate.mjs` reports the pair is
  pixel-identical, your `path`/`selector` does not actually contain the change — fix the
  target, do not silence the check.
- Keep `viewport`, `selector`, and `setup` identical across both sides. Any difference
  there shows up as a visual diff that has nothing to do with the PR.

## 6. Non-deterministic content

When the dev server talks to a real backend, feeds and counters change between the two
captures and swamp the real diff. Narrow `selector` to the component under change rather
than the page, and prefer routes whose content is static.
