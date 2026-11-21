---
name: init-agent
description: >
  Initialize project-local agent settings: link .agents/{skills,commands,rules}
  into .cursor, .claude, and .codex, and CLAUDE.md to AGENTS.md. Use for
  init-agent requests or shared agent setup in a checkout.
---

# init-agent

## Project instructions

Inspect the repository's README, task commands, and existing agent settings.
Preserve an existing `AGENTS.md` unless the user asks to revise it.

When it is missing, write a short `AGENTS.md` containing only repository-specific
information that changes how an agent should work: non-obvious commands,
responsibility boundaries, or important exceptions. A few lines usually suffice;
link to maintained documentation instead of repeating it. If there is nothing
useful to add, a project heading is enough.

Do not copy global/session instructions or add generic engineering advice,
subagent catalogs, skill tutorials, or standard Git/TDD/tool policies. Encode
mechanically enforceable rules in existing tooling when that is in scope.

## Initialize links

Run the script from this skill's installed location, passing the project root:

```bash
bash /path/to/init-agent/scripts/init-agent.sh /path/to/project
```

Do not copy or install this skill into the target repository for setup.
The Unix shell script creates `.agents/{skills,commands,rules}`, links each under
`.cursor`, `.claude`, and `.codex`, and links `CLAUDE.md` to `AGENTS.md`.
Keep empty source directories in Git with `.gitkeep` when needed.

Existing correct links are reused. Conflicting real files/directories and links
to other targets are preserved; inspect and reconcile them before rerunning.
The script does not generate or overwrite project instructions.

Verify that all links resolve and a second run succeeds without changes.
