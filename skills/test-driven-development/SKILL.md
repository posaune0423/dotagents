---
name: test-driven-development
description: >-
  Red-Green-Refactor workflow for behavior changes: write the failing test first, then the minimal
  code, then refactor. Use when implementing a feature or bug fix in code that has or should have a
  test surface; not for config, docs, or throwaway scripts.
---

# Test-Driven Development

Write the test first, watch it fail for the right reason, write the least code that passes, then clean up. A test you never saw fail proves nothing about what it tests.

## Scope

Apply to new behavior, bug fixes, and refactors of code that has or should have tests. Throwaway prototypes, generated code, configuration, and docs are exempt; if you are unsure whether something counts, ask.

## Cycle

1. **Red.** Write one minimal test for one behavior, named after that behavior, exercising real code rather than a mock. Run it. It must fail because the behavior is missing, not because of a typo or setup error. If it passes, it tests existing behavior; fix the test.
2. **Green.** Write the simplest code that makes it pass. No extra options, no speculative generality, no unrelated cleanup.
3. **Refactor.** With everything green, remove duplication, improve names, extract helpers. Do not add behavior here.
4. Repeat with the next behavior.

For a bug, the first red test is a reproduction of the bug. The fix is not done until that test passes and no other test broke.

## Good tests

| Quality      | Good                                    | Bad                                                 |
| ------------ | --------------------------------------- | --------------------------------------------------- |
| Minimal      | One behavior per test; split on "and"   | `test('validates email and domain and whitespace')` |
| Clear        | Name states the behavior                | `test('test1')`                                     |
| Shows intent | Demonstrates the API you wish you had   | Mirrors the implementation line by line             |
| Real         | Exercises real code; mock only at edges | Asserts on the mock instead of the code             |

## When the test is hard to write

| Problem                 | What it usually means                               |
| ----------------------- | --------------------------------------------------- |
| Do not know how to test | Write the wished-for API and the assertion first    |
| Test too complicated    | The design is too complicated; simplify the API     |
| Must mock everything    | Code is too coupled; inject the dependency          |
| Setup is huge           | Extract helpers; if still huge, simplify the design |

Before adding mocks or test-only helpers, read [testing-anti-patterns.md](testing-anti-patterns.md).
