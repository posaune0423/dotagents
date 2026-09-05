---
name: bug-fix
description: Fix a reported bug or error from reproduction through verified fix: find the root cause, apply the minimal change, and prove it with tests or a real browser check. Use for debugging and bug-fix tasks.
---

# Bug Fix

Own the fix from reproduction to verified result.

- Reproduce first. Read the error and the code it points at yourself; do not diagnose from the report alone. If the report lacks what you need to reproduce it, name exactly what is missing and stop there.
- Fix the root cause with the smallest effective change. Do not paper over a symptom or widen the change into a refactor.
- Verify with the project's own checks for what you touched. For UI changes, also confirm in a real browser or with a Playwright check; when no UI test exists, say so and record the manual check you did.
- If verification still fails, return to reproduction. Never adjust the test or the expectation to get green.
- Report which commands you ran and what evidence shows the bug is gone, and put the same in the PR description or report.
