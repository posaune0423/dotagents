import js from "@eslint/js"
import prettier from "eslint-config-prettier"

export default [
  {
    ignores: [".git/**", "node_modules/**", ".github/**", "**/*.min.*", "**/*.lock", "bun.lockb", "skills/.system/**"],
  },
  {
    files: ["**/*.{js,mjs,cjs,ts,mts,cts}"],
    ...js.configs.recommended,
  },
  prettier,
]
