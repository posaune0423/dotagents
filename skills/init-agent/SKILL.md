---
name: init-agent
description: >
  Initialize a repository for agents: scaffold AGENTS.md and docs/
  (PRD, STRUCTURE, TECHNOLOGY, specs/ph01) from templates, link
  .agents/{skills,commands,rules} into .cursor, .claude, and .codex, and link
  CLAUDE.md to AGENTS.md. Use for init-agent requests or agent setup in a checkout.
---

# init-agent

## 1. Run the script

Run it from this skill's installed location, passing the project root:

```bash
bash /path/to/init-agent/scripts/init-agent.sh /path/to/project
```

Do not copy or install this skill into the target repository.
The script copies each file under [assets/templates/](assets/templates/) that does
not exist yet (`AGENTS.md`, `docs/PRD.md`, `docs/STRUCTURE.md`,
`docs/TECHNOLOGY.md`, `docs/specs/ph01.md`), creates `.agents/{skills,commands,rules}`,
links each under `.cursor`, `.claude`, and `.codex`, and links `CLAUDE.md` to
`AGENTS.md`. It prints `created:` or `kept:` per file and never overwrites one.
Pass `--links-only` when the user wants only the links; the project must then
already have `AGENTS.md`.

Existing correct links are reused. Conflicting real files/directories and links
to other targets are preserved and stop the script; inspect and reconcile them
before rerunning. Keep empty source directories in Git with `.gitkeep` when needed.

## 2. Fill the created files

Only files the script reported as `created:` are yours to fill. Leave `kept:` files
alone unless the user asks to revise them.

Inspect the README, task runner (`justfile`, `package.json`, `Makefile`), CI config,
lockfiles, and directory layout, then fill each created file from what is actually
there. Ask the user only for what the repository cannot tell you, such as product
goals for `docs/PRD.md` or the scope of the first phase in `docs/specs/ph01.md`.

- `AGENTS.md` follows the layout of Orca's AGENTS.md: Checks, Repo Rules, Docs,
  Code Style, First Class Citizens, Footguns. Replace the gate and iteration
  commands with the repository's real ones. Delete any section or bullet that
  does not apply rather than leaving a placeholder. Keep long detail in
  `docs/` and link to it.
- In `docs/`, write only what you verified. Mark unknowns under 未決事項 instead
  of guessing.
- Remove every `init-agent:` comment. `rg -n 'init-agent:' AGENTS.md docs` must
  print nothing when you finish.

Do not copy global or session instructions, subagent catalogs, or skill tutorials
into `AGENTS.md`. Encode mechanically enforceable rules in existing tooling when
that is in scope.

## 3. Verify

All links resolve, a second run prints no `created:` lines, and no `init-agent:`
comments remain.
