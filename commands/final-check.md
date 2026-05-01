# Final Check Command

## Steps

1. `bun run check`（`bun run lint` / `bun run format:check` / Bash の lint・format チェックを含む）を実行し、error, warning が出ていないことを確認してください。
2. error, warning が出ている場合は根本原因を特定し、最小限の修正を行ってください。
3. 修正後に再度 `bun run check` を実行し、問題がないことを確認してください。
4. error, warning がなくなるまで 2, 3 を繰り返してください。
