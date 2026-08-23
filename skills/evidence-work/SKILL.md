---
name: evidence-work
description: Handle specialist explanations, source-backed research, target-specific causal diagnosis, or business/personal decisions when the answer depends on evidence, scope, and user context. Do not use for casual everyday questions or implementation tasks.
---

# Evidence Work

Use this skill when a plausible general answer would be insufficient because the task depends on current sources, a named entity or repository, causal evidence, or the user's actual constraints. Keep the main conversation and final judgment with the main agent.

## First decide whether this applies

Do not load this skill for casual everyday questions, lightweight brainstorming, or implementation work already covered by the development, debugging, and testing workflows. A concise direct answer remains appropriate when its accuracy does not depend on specialist, current, target-specific, or user-specific evidence.

When it does apply, normalize the request before answering:

```text
mode: direct | research | causal-diagnosis | decision-advice
goal:
deliverable:
scope:
freshness:
stakes:
available_evidence:
assumptions:
missing_decision_changing_context:
```

Retrieve discoverable context from the permitted source of truth before asking. Ask one concise question only when its answer would materially change the conclusion, scope, or authorized action. State low-risk assumptions rather than blocking on them.

Read the common [evidence contract](references/evidence-contract.md) before forming a conclusion, then read only the reference for the selected mode:

- [Specialist explanation](references/direct.md): a domain concept or mechanism such as a prop AMM.
- [Source-backed research](references/research.md): a named entity, market, protocol, or broad factual investigation.
- [Causal diagnosis](references/causal-diagnosis.md): why a target system, project, or experiment produced an outcome.
- [Decision advice](references/decision-advice.md): business or personal decisions grounded in external and user-specific context.

## Delegation

Use a read-only subagent only when it owns an evidence lane that is independent of the main synthesis and is worth the added latency and tokens:

- `researcher` for source, repository, or primary-material collection.
- `evidence-analyst` for independent comparisons, causal decomposition, sensitivity, or alternative hypotheses.
- `evidence-auditor` for a high-impact claim's support, coverage, source quality, or scope.

Do not delegate routine specialist explanations merely to appear thorough. Do not hand personal or business recommendations to a subagent: it may supply evidence and analysis, but the main agent owns the user's context, trade-offs, and final recommendation.

Give every delegated lane a bounded brief: objective, exact lane, permitted sources/tools, exclusions, required evidence packet, and stop condition. Integrate the returned material under the evidence contract rather than treating it as a conclusion.

## Stop condition

Finish when the requested deliverable is supported to a level proportionate to its stakes, material uncertainty is visible, and a further search or delegation would not change the conclusion. Do not pad the answer with generic frameworks or unsupported recommendations.
