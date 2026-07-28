# Capture manifest

The manifest is the contract between the phases. You author it in Phase 1; `capture.mjs`
fills in `path`/`width`/`height`, `upload-assets.mjs` fills in `url`, and
`render-section.mjs` reads the result. Every script accepts and returns the same file.

## Shape

The file is read with `JSON.parse`: comments and trailing commas are **not** allowed.
The annotations below are only there to explain the fields.

<!-- prettier-ignore -->
```jsonc
{
  "pairs": [                            // before/after table; one entry per row
    {
      "id": "newsletter-consent-modal", // required, unique; used in filenames
      "label": "NewsletterConsentModal", // shown in alt text; defaults to id
      "path": "/account/notifications", // route to visit, without a locale prefix
      "viewport": "sm",                 // name from config.viewports; else config.defaultViewport
      "selector": "[role=dialog]",      // element to frame; omit to shoot the whole viewport
      "fullPage": false,                // only meaningful when selector is omitted
      "locale": "ja",                   // defaults to config.locales.default
      "captureBase": true,              // false for brand-new UI that cannot exist on base
      "setup": [{ "click": "text=お知らせ" }, { "waitFor": "[role=dialog]" }]
    }
  ],
  "localeMatrix": [                     // all-locales table; no locale/captureBase
    {
      "id": "consent-modal-copy",
      "label": "consent modal",
      "path": "/account/notifications",
      "viewport": "sm",
      "selector": "[role=dialog]",
      "locales": ["ja", "en"],          // optional subset; defaults to config.locales.list
      "setup": []
    }
  ]
}
```

## setup steps

Applied in order, after load and before measuring. One key per step:

| Step                               | Effect                              |
| ---------------------------------- | ----------------------------------- |
| `{"click": "<selector>"}`          | Click the first match.              |
| `{"fill": "<selector>", "value":}` | Fill an input.                      |
| `{"press": "Escape"}`              | Press a key.                        |
| `{"waitFor": "<selector>"}`        | Wait until the element is visible.  |
| `{"wait": 500}`                    | Wait N milliseconds. Use sparingly. |
| `{"eval": "<js>"}`                 | Run JS in the page. Last resort.    |

Prefer `waitFor` over `wait`: a fixed sleep is the usual cause of a blank screenshot
that only fails on a slow machine.

## Fields the scripts add

`capture.mjs` writes a shot object onto `pairs[].before`, `pairs[].after`, and
`localeMatrix[].shots["<locale>"]`:

```jsonc
{ "path": "/abs/path.png", "url": null, "width": 375, "height": 640, "alt": "NewsletterConsentModal-head" }
```

`width`/`height` are **CSS pixels** (the clip size), not the PNG's pixel dimensions —
the browser runs at `deviceScaleFactor: 2`, so the file is twice as large. Those CSS
values become the `<img width height>` attributes, which is what makes the image render
at a sane size in the PR.

`upload-assets.mjs` sets `url`, and skips any shot that already has one — so a partly
finished run can be re-run without re-uploading.

## Choosing `selector`

Frame the smallest element that fully contains the change plus enough surrounding
context to be recognisable. A modal's `[role=dialog]`, a card's root, a form's
`<form>`. Avoid `body` (captures unrelated chrome and makes before/after diffs noisy)
and avoid the changed text node itself (no context).

Verify the selector resolves to exactly one visible element before capturing; a
selector matching nothing fails after a 15s timeout per attempt.
