#!/usr/bin/env node
// Polls a URL until it answers. Replaces a curl loop so the skill needs no curl.
//
// Usage: wait-for-http.mjs <url> [timeoutSeconds] [--pid <n>]
//   timeoutSeconds 0 means "probe exactly once" (the is-it-already-running check).
//   --pid makes the wait abort as soon as that process dies, so a dev server that
//   crashes on startup reports immediately instead of burning the whole timeout.
const [url, timeoutArg, ...rest] = process.argv.slice(2)
if (!url) {
  process.stderr.write("Usage: wait-for-http.mjs <url> [timeoutSeconds] [--pid <n>]\n")
  process.exit(2)
}

const timeoutSec = Number(timeoutArg ?? 0)
const pidIndex = rest.indexOf("--pid")
const pid = pidIndex >= 0 ? Number(rest[pidIndex + 1]) : null

const sleep = ms => new Promise(done => setTimeout(done, ms))

async function probe() {
  try {
    // Any HTTP answer means the server is up; a 404 on the ready path still proves that.
    const response = await fetch(url, { signal: AbortSignal.timeout(5000), redirect: "manual" })
    return response.status < 500
  } catch {
    return false
  }
}

function alive() {
  if (pid === null) return true
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

const deadline = Date.now() + timeoutSec * 1000
let reported = 0
do {
  if (await probe()) process.exit(0)
  if (!alive()) {
    process.stderr.write("Dev server process exited before becoming ready.\n")
    process.exit(3)
  }
  const elapsed = Math.round((Date.now() - (deadline - timeoutSec * 1000)) / 1000)
  if (elapsed - reported >= 15) {
    reported = elapsed
    process.stderr.write(`  ... still compiling (${elapsed}s elapsed)\n`)
  }
  await sleep(1000)
} while (Date.now() < deadline)

process.exit(1)
