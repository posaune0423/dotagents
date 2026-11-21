<!-- init-agent: fill every section from the repository, delete sections that do not apply, then delete these init-agent comments. Keep only what changes how an agent works here. -->

# Checks

- **Gate**: `just check` runs format, lint, typecheck, and the tests. Run it once when you are done editing, and again after a rebase or fix. Never `--no-verify`.
- **While iterating**: run only what you touched. <!-- init-agent: single-test, typecheck, lint, and format commands for one file or package -->
- CI: `gh pr checks --watch`. Read failures with `gh run view <id> --log-failed`; filter long logs with `grep -nE "error|FAIL"` instead of tailing.

# Repo Rules

- Keep main releasable. Never break CI; if it is broken, fix it first.
<!-- init-agent: repository-specific rules, e.g. generated files not to edit, release or migration steps -->

# Docs

Read the document that covers a behavior before changing it, and update it in the same change.

- [`docs/PRD.md`](docs/PRD.md): what the product does, for whom, and what is out of scope.
- [`docs/STRUCTURE.md`](docs/STRUCTURE.md): directories, module boundaries, and where new code goes.
- [`docs/TECHNOLOGY.md`](docs/TECHNOLOGY.md): stack, versions, and why each was chosen.
- [`docs/specs/`](docs/specs/): one spec per phase (`ph01.md`, `ph02.md`, ...).

# Code Style

## Reuse Before Reimplementing

Before writing new logic at any scale, extend or generalize existing code instead of building a parallel version.

## Comments

Only where the code cannot say it. One line on why, not how.

## File and Module Naming

Name files after what they contain (`tab-group-state.ts`), not after a generic role. Do not use `helpers`, `utils`, `common`, or `misc`.

# First Class Citizens

Every change must consider these areas:

<!-- init-agent: list what this product must never regress, e.g. cross-platform support, mobile, accessibility, i18n, offline -->

# Footguns

<!-- init-agent: areas that break in non-obvious ways, each linked to the doc to read first, e.g. "Before changing auth, read docs/auth.md." -->
