import js from "@eslint/js"
import prettier from "eslint-config-prettier"

export default [
  {
    ignores: [
      ".git/**",
      "node_modules/**",
      ".github/**",
      "**/*.min.*",
      "**/*.lock",
      "bun.lockb",
      "skills/.system/**",
      "skills/**/scripts/**/*.ts",
    ],
  },
  {
    files: ["**/*.{js,mjs,cjs,ts,mts,cts}"],
    ...js.configs.recommended,
  },
  {
    // Skill scripts are Node CLIs. `document` and `Event` are here because Playwright
    // `page.evaluate(() => ...)` callbacks are serialised and run in the browser.
    files: ["skills/**/scripts/**/*.{js,mjs,cjs}"],
    languageOptions: {
      globals: {
        AbortSignal: "readonly",
        Buffer: "readonly",
        Event: "readonly",
        URL: "readonly",
        console: "readonly",
        document: "readonly",
        fetch: "readonly",
        process: "readonly",
        setTimeout: "readonly",
        window: "readonly",
      },
    },
  },
  prettier,
]
