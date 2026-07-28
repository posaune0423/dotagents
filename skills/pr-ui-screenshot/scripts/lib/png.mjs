// Minimal PNG reader: enough to size, measure, and compare Playwright screenshots
// without an ImageMagick dependency. node's zlib does the only hard part.
//
// Supports non-interlaced colour types 0/2/4/6 at bit depth 8 or 16 — which is what
// Chromium emits. Palette (type 3) and Adam7 interlacing throw rather than guess.
import { readFileSync } from "node:fs"
import { inflateSync } from "node:zlib"

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
// Samples per pixel in the encoded data. Type 3 stores one palette index per pixel.
const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }

function chunks(buf) {
  const out = []
  let offset = 8
  while (offset + 8 <= buf.length) {
    const length = buf.readUInt32BE(offset)
    const type = buf.toString("ascii", offset + 4, offset + 8)
    out.push({ type, data: buf.subarray(offset + 8, offset + 8 + length) })
    offset += 12 + length // length + type + data + crc
  }
  return out
}

/** Reads just the IHDR header. Cheap — no decompression. */
export function readHeader(path) {
  const buf = readFileSync(path)
  if (!buf.subarray(0, 8).equals(SIGNATURE)) throw new Error("not a PNG")
  const ihdr = chunks(buf).find(chunk => chunk.type === "IHDR")
  if (!ihdr) throw new Error("PNG has no IHDR")
  return {
    width: ihdr.data.readUInt32BE(0),
    height: ihdr.data.readUInt32BE(4),
    bitDepth: ihdr.data[8],
    colorType: ihdr.data[9],
    interlace: ihdr.data[12],
    buf,
  }
}

/** Turns one-index-per-pixel palette data into RGB triples via the PLTE chunk. */
function expandPalette(buf, indexes, width, height) {
  const plte = chunks(buf).find(chunk => chunk.type === "PLTE")
  if (!plte) throw new Error("palette PNG has no PLTE chunk")
  const data = Buffer.allocUnsafe(width * height * 3)
  for (let i = 0; i < indexes.length; i += 1) {
    const offset = indexes[i] * 3
    if (offset + 2 >= plte.data.length) throw new Error(`palette index ${indexes[i]} out of range`)
    data[i * 3] = plte.data[offset]
    data[i * 3 + 1] = plte.data[offset + 1]
    data[i * 3 + 2] = plte.data[offset + 2]
  }
  return { width, height, channels: 3, data }
}

function paeth(a, b, c) {
  const p = a + b - c
  const pa = Math.abs(p - a)
  const pb = Math.abs(p - b)
  const pc = Math.abs(p - c)
  if (pa <= pb && pa <= pc) return a
  return pb <= pc ? b : c
}

/**
 * Decodes to 8-bit samples, one byte per channel, row-major.
 * Returns { width, height, channels, data }.
 */
export function decode(path) {
  const { width, height, bitDepth, colorType, interlace, buf } = readHeader(path)
  if (interlace !== 0) throw new Error("interlaced PNG is not supported")
  const channels = CHANNELS[colorType]
  if (!channels) throw new Error(`unsupported PNG colour type ${colorType}`)
  if (![1, 2, 4, 8, 16].includes(bitDepth)) throw new Error(`unsupported PNG bit depth ${bitDepth}`)
  if (bitDepth < 8 && colorType !== 0 && colorType !== 3) {
    throw new Error(`unsupported ${bitDepth}-bit colour type ${colorType}`)
  }
  if (colorType === 3 && bitDepth === 16) throw new Error("16-bit palette PNG is not valid")

  const idat = chunks(buf)
    .filter(chunk => chunk.type === "IDAT")
    .map(chunk => chunk.data)
  if (idat.length === 0) throw new Error("PNG has no IDAT")
  const raw = inflateSync(Buffer.concat(idat))

  // Sub-8-bit samples pack several pixels per byte; filtering then works on 1-byte steps.
  const rowBytes = Math.ceil((width * channels * bitDepth) / 8)
  const pixelBytes = Math.max(1, Math.floor((channels * bitDepth) / 8))
  const expected = (rowBytes + 1) * height
  if (raw.length < expected) throw new Error(`truncated PNG data (${raw.length} < ${expected})`)

  // Undo the per-scanline filters in place, one row at a time.
  const out = Buffer.allocUnsafe(rowBytes * height)
  let prev = Buffer.alloc(rowBytes)
  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (rowBytes + 1)]
    const row = Buffer.from(raw.subarray(y * (rowBytes + 1) + 1, (y + 1) * (rowBytes + 1)))
    for (let i = 0; i < rowBytes; i += 1) {
      const left = i >= pixelBytes ? row[i - pixelBytes] : 0
      const up = prev[i]
      const upLeft = i >= pixelBytes ? prev[i - pixelBytes] : 0
      switch (filter) {
        case 0:
          break
        case 1:
          row[i] = (row[i] + left) & 0xff
          break
        case 2:
          row[i] = (row[i] + up) & 0xff
          break
        case 3:
          row[i] = (row[i] + ((left + up) >> 1)) & 0xff
          break
        case 4:
          row[i] = (row[i] + paeth(left, up, upLeft)) & 0xff
          break
        default:
          throw new Error(`unknown PNG filter ${filter} on row ${y}`)
      }
    }
    row.copy(out, y * rowBytes)
    prev = row
  }

  if (bitDepth === 8) {
    return colorType === 3 ? expandPalette(buf, out, width, height) : { width, height, channels, data: out }
  }

  if (bitDepth === 16) {
    // Drop the low byte of each sample; 8 bits is plenty for these checks.
    const narrowed = Buffer.allocUnsafe(width * height * channels)
    for (let i = 0; i < narrowed.length; i += 1) narrowed[i] = out[i * 2]
    return { width, height, channels, data: narrowed }
  }

  // Unpack sub-byte samples: grayscale scales up to 0..255, palette indexes the PLTE.
  const perByte = 8 / bitDepth
  const max = (1 << bitDepth) - 1
  const raw8 = Buffer.allocUnsafe(width * height)
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const byte = out[y * rowBytes + Math.floor(x / perByte)]
      const shift = 8 - bitDepth * ((x % perByte) + 1)
      const sample = (byte >> shift) & max
      raw8[y * width + x] = colorType === 3 ? sample : Math.round((sample / max) * 255)
    }
  }
  return colorType === 3 ? expandPalette(buf, raw8, width, height) : { width, height, channels: 1, data: raw8 }
}

/**
 * Largest per-channel standard deviation, normalised to 0..1, alpha excluded.
 *
 * Deliberately per-channel rather than pooled: pooling the channels together adds the
 * variance *between* them, so a solid non-grey fill (flat R, G and B, but different
 * means) would score well above zero and sail past the blank check. Taking each channel
 * separately asks the question we actually mean — does anything vary anywhere?
 */
export function standardDeviation(image) {
  const { channels, data } = image
  const colorChannels = channels === 4 ? 3 : channels === 2 ? 1 : channels
  const pixels = data.length / channels
  if (pixels === 0) return 0
  let worst = 0
  for (let c = 0; c < colorChannels; c += 1) {
    let sum = 0
    let sumSquares = 0
    for (let i = c; i < data.length; i += channels) {
      sum += data[i]
      sumSquares += data[i] * data[i]
    }
    const mean = sum / pixels
    worst = Math.max(worst, Math.sqrt(Math.max(0, sumSquares / pixels - mean * mean)) / 255)
  }
  return worst
}

/** Number of differing pixels, or null when the two images differ in size. */
export function differingPixels(a, b) {
  if (a.width !== b.width || a.height !== b.height || a.channels !== b.channels) return null
  const { channels, data } = a
  const other = b.data
  let differing = 0
  for (let i = 0; i < data.length; i += channels) {
    for (let c = 0; c < channels; c += 1) {
      if (data[i + c] !== other[i + c]) {
        differing += 1
        break
      }
    }
  }
  return differing
}
