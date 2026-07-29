# Troubleshooting

## Dev server

**`serve.sh` times out.** The tail of the server log is printed on failure — read it
before retrying. A first `next dev` compile on a cold `.next` can exceed the default
timeout; raise `dev.readyTimeoutSec` in the config rather than re-running blindly.

**The base server fails to start but head works.** Almost always dependencies: the
lockfile moved between the merge-base and HEAD, so the symlinked `node_modules` is wrong.
Re-run `base-worktree.sh` with `--install "<install command>"`.

**Port already in use.** `serve.sh` reuses whatever already answers on that port. That is
usually convenient, but if a stale server from another branch is listening you will
silently screenshot the wrong code. Check what is on the port before a base capture.

## Capture

**`Selector ... has no bounding box` / times out.** The element is not on that route, or
not visible yet. Re-run one target with `--headed --only <id>` and watch.

**Screenshot is blank or half-rendered.** Add `{"waitFor": "<selector>"}` to `setup`
instead of increasing `wait`. Blank pages are caught by `validate.mjs`, not silently
shipped.

**Image is enormous.** The element is taller than `MAX_VIEWPORT_HEIGHT` (4000 CSS px), so
the clip fell back to a full-page shot. Narrow the `selector`.

**Text is unreadably small.** Do not fix this with zoom. The capture deliberately grows
the viewport rather than scaling down, because the wording is what reviewers read. If it
still looks wrong, pick a narrower viewport from `config.viewports`.

**Locale shots are all identical.** `validate.mjs` fails the run. Check that the locale
prefix is right for the framework (`/en/foo`; the default locale has no prefix) and that
the route actually re-renders — some apps cache the language in a cookie that outlives
the navigation.

## Upload

**`No saved GitHub session`** or **`the saved session expired`.** Run
`upload-assets.mjs --login`, sign in in the window that opens, and re-run. The session
file lives at `~/.config/pr-ui-screenshot/github-storage-state.json` with mode 600.

There is no token-only alternative. GitHub exposes no API for `user-attachments`:
`/upload/policies/assets` is CSRF-guarded and rejects PATs (422), and personal access
tokens do not authenticate github.com web pages at all. A logged-in browser session is
the only way to mint those URLs.

**`Could not find the comment box`.** GitHub has migrated that page to the React editor,
which does not expose an addressable file input. Update `FILE_INPUTS` / `TEXTAREAS` in
`scripts/upload-assets.mjs`; the fallback that clicks _Paste, drop, or click to add
files_ and catches the `filechooser` event is the more durable path.

**Did the upload post a comment?** No. The comment box is used only as an upload form:
the draft is cleared after each file and the Comment button is never clicked. If you ever
see a stray empty comment, that is a bug worth reporting.

**A URL 404s when you curl it.** Expected. `user-attachments/assets/…` redirects to a
session-signed asset URL that refuses anonymous clients. Check it in a logged-in browser.

## PR body

**`Heading ... appears N times`.** The body has duplicate section headings. Fix the body
by hand; the script refuses to guess which one to replace.

**`Align section.heading with the template`.** `section.heading` in the config and the
first heading in the template disagree. They must match exactly, or a second run would
append a new section instead of updating the existing one.

**The section was appended at the bottom instead of in place.** The body has no such
heading and none of `section.insertBefore` matched. Add the right anchors to the config.
