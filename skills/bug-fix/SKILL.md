---
name: bug-fix
description: >
  When a bug report or error occurs (e.g. a stack trace), a skill that always runs commands yourself, automated tests, and UI verification with Playwright or similar through reproduction and fix verification, applies minimally effective fixes to the root cause, and owns validation and factual verification end to end. Use for debugging and bug-fix tasks.
---

# Bug Fix

## Steps

1. Read the error details and stack trace carefully, always inspect the related code and files yourself, and identify a concrete root cause.
2. If the root cause cannot be determined because information is insufficient, explicitly state what is missing and how, and report it to the developer.
3. Once the root cause is known, choose a fix that is **minimal and effective**.
4. Apply the fix.
5. Always run lint, format, build, and test locally yourself and confirm that types, syntax, and tests all pass.
6. For fixes involving the frontend or UI, **UI tests with Playwright or similar, or verification in a real browser, are mandatory**. If automated tests alone are not enough, open the UI yourself and **visually confirm that it is fixed**.
7. If tests or UI checks still show failures or unfixed behavior, **reproduce the steps, screen, and error logs yourself**, then return to step 1 and repeat.
8. When everything is resolved, finish by stating **which commands you used to verify and what evidence led you to conclude the issue is fixed**.

## Notes

- Never stop at guesses or “probably fine”; **facts from actually running, observing, and verifying are required**.
- If no Playwright or other E2E/UI tests exist, state that explicitly, then perform and record manual verification.
- Always share the fix process and verification status in pull requests or reports.
