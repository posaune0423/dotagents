# Causal Diagnosis

Use when the request asks why a named system, project, experiment, or business outcome occurred. General failure patterns can generate hypotheses, but they do not establish the cause of this target.

Start with the observed outcome and its measurement boundary. Inspect target-specific artifacts such as repository behavior, configuration, logs, traces, experiment outputs, financial records, production metrics, or test results. Build a causal chain:

```text
outcome -> measurable contributors -> candidate causes -> evidence and counterevidence -> next discriminating check
```

Rank causes by explanatory support and expected contribution. For each material candidate, name what would disprove it or distinguish it from alternatives. If the evidence cannot identify a cause, say so and propose the cheapest measurement or experiment that would.

Do not claim a root cause from a single correlated observation, and do not call a design or deployment issue resolved without the relevant runtime evidence.
