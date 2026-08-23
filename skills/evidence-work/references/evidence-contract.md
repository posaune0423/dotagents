# Evidence Contract

Build an internal evidence packet before presenting a material conclusion. Keep it proportional: stable, low-stakes explanations need less ceremony than a current market investigation or a decision with significant cost.

## Claim types

Use these distinctions internally and expose them in natural language when they matter:

| Type               | Meaning                                                          | Minimum support                                                 |
| ------------------ | ---------------------------------------------------------------- | --------------------------------------------------------------- |
| `verified_fact`    | Directly observed or checked in this task                        | Atomic claim, source locator, scope, and time when relevant     |
| `user_observation` | Information supplied by the user but not independently confirmed | Its origin and the limits of relying on it                      |
| `reported_opinion` | A source's analysis, forecast, or recommendation                 | Source identity; do not promote it to fact                      |
| `assumption`       | Necessary but unverified premise                                 | Why it is needed and how it could change the result             |
| `inference`        | Interpretation drawn from facts or observations                  | Its premises and material assumptions                           |
| `recommendation`   | Proposed action or decision                                      | Supporting facts/inferences plus the user's value or constraint |
| `unknown`          | Material question not settled by available evidence              | The cheapest next validation step                               |

## Rules

- Keep `verified_fact` atomic. Cite the actual URL, file and line, command output, test, dataset, or other locator that supports it.
- Preserve source hierarchy and scope. Prefer primary material, official records, repository state, direct measurements, and reproducible tests; label secondary reporting and commentary accordingly.
- Do not present a user statement or a source's opinion as independently verified fact.
- Make an `inference` traceable to facts or user observations and state any premise that is doing real work.
- A `recommendation` requires evidence and an identified objective, value, or constraint. If either is missing, return a hypothesis or an `unknown`, not a confident recommendation.
- Check time, jurisdiction, implementation, cohort, and other scope boundaries before applying evidence to the target.
- Do not attach citations after deciding the conclusion merely for appearance. Revisit the conclusion if the evidence does not actually support it.

## Final answer

Do not expose internal identifiers unless the user requests an audit trail. Use clear boundaries such as **Confirmed**, **Interpretation**, **Recommendation**, and **Unknown** where they improve decision-making. Separate local checks, CI, merge, deployment, and live evidence rather than implying that one proves another.
