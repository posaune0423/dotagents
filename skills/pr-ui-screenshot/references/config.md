# Config

`scripts/resolve-config.mjs` merges these layers, later ones winning, objects merged
recursively and arrays replaced wholesale:

1. `presets/default.json` — the built-in baseline shipped with this skill
2. `presets/<owner>-<repo>.json` — an optional bundled preset, matched via `gh repo view`
3. `<repo>/.claude/pr-ui-screenshot.json`
4. `<repo>/.agents/pr-ui-screenshot.json`
5. `$PR_UI_SCREENSHOT_CONFIG` — an explicit path

**Put project settings in the project, at layer 3.** That file is committed to the repo
it describes, so everyone working there gets the right settings with no setup, and
nothing about a private codebase — its name, routes, locales, or cookies — ends up in
this skill. Layer 2 exists for repos that genuinely want their preset bundled here; it
is empty by default and should stay that way for anything non-public.

## Keys

The file is read with `JSON.parse`: comments and trailing commas are **not** allowed.
The annotations below only explain the fields.

<!-- prettier-ignore -->
```jsonc
{
  "dev": {
    "command": "pnpm dev", // "{port}" is substituted if present, else PORT=<n> is exported
    "port": 3000, // head server
    "basePort": 3001, // merge-base server
    "readyPath": "/", // polled until it answers
    "readyTimeoutSec": 240, // raise this for slow first compiles
    "env": {} // extra env for the dev server
  },
  "install": {
    "command": "pnpm install --frozen-lockfile", // run in the base worktree only if the lockfile moved
    "shareNodeModules": true // symlink the parent's node_modules when it did not
  },
  "locales": {
    "list": ["ja", "en"], // column order of the all-locales table
    "default": "ja", // the locale served without a prefix
    "strategy": "path-prefix" // how a locale is forced; only path-prefix is implemented
  },
  "detect": {
    "translation": ["locale/*/*.json"], // a hit here means the locale table is required
    "component": ["src/components/**/*.tsx"],
    "route": ["pages/**/*.tsx", "app/**/page.tsx"]
  },
  "viewports": [{ "name": "sm", "width": 375, "height": 667 }],
  "defaultViewport": "sm",
  "auth": {
    "cookies": [
      {
        "name": "session_token",
        "valueEnv": "MY_DEV_TOKEN", // read from the environment; never store a token here
        "domain": "localhost",
        "path": "/"
      }
    ]
  },
  "section": {
    "heading": "## Screenshots", // the section replaced in the PR body
    "insertBefore": ["## Checklist"], // where to insert it when the heading is absent
    "template": "templates/default.md" // relative to the skill dir, or an absolute path
  }
}
```

`section.heading` must match the first heading in `section.template` exactly, or
`replace-section.mjs` refuses to run — otherwise a second run would append a duplicate
section instead of updating the existing one.

## Bundled templates

| Template                               | Layout                                                                                           |
| -------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `templates/default.md`                 | English `Before \| After` table plus a locale matrix                                             |
| `templates/ja-before-after-locales.md` | Japanese `旧 \| 新` table plus a locale matrix, matching the common Japanese PR-template wording |

Point `section.template` at whichever fits, or at your own file. Editing the template is
the supported way to change the output — no script changes needed. Keep `{{#each}}` and
`{{#if}}` tags on their own lines, and note that `skills/*/templates/` is
prettier-ignored so the block tags are not reflowed into the tables.

## Viewports

Prefer the project's own design breakpoints over generic device presets — a repo whose
designs are drawn at 375px should capture at 375px, so reviewers see what the designer
drew.

## Auth

`auth.cookies[].valueEnv` names an environment variable; the value is never written to
the config. Cookies are seeded before the first navigation because apps commonly read
their token once at module load, which makes a later `addCookies` too late.
