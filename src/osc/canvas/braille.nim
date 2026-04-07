## Braille-dot terminal canvas — 2×4 dots per character cell.
## Each cell maps to a Unicode braille character (U+2800–U+28FF).
##
## Dot layout per cell:
##   ┌───┐
##   │ 0 3 │   bit 0 = top-left,     bit 3 = top-right
##   │ 1 4 │   bit 1 = mid-left,     bit 4 = mid-right
##   │ 2 5 │   bit 2 = bottom-left,  bit 5 = bottom-right
##   │ 6 7 │   bit 6 = low-left,     bit 7 = low-right
##   └───┘
##
## Resolution: terminal columns × 2, terminal rows × 4

import terminal
import term except Canvas, newCanvas, resize, pixIdx, addPixel, decayPixels, flush

const MinBright* = 0.02

type
  BrailleCanvas* = object
    w*, h*: int           # terminal columns/rows
    pixW*, pixH*: int     # pixel dimensions (w*2, h*4)
    pixels*: seq[float]   # brightness per pixel [pixW * pixH]
    buf: string
    pal*: Palette
    thresholds*: array[3, float]

# ── Init / resize ───────────────────────────────────────────────────

proc newBrailleCanvas*(w, h: int, palette = "green",
                       thresholds = [0.7, 0.4, 0.15]): BrailleCanvas =
  BrailleCanvas(
    w: w, h: h, pixW: w * 2, pixH: h * 4,
    pixels: newSeq[float](w * 2 * h * 4),
    buf: newStringOfCap(w * h * 16),
    pal: makePalette(palette),
    thresholds: thresholds
  )

proc resize*(c: var BrailleCanvas, w, h: int) =
  if w == c.w and h == c.h: return
  let pal = c.pal
  let thr = c.thresholds
  c = BrailleCanvas(
    w: w, h: h, pixW: w * 2, pixH: h * 4,
    pixels: newSeq[float](w * 2 * h * 4),
    buf: newStringOfCap(w * h * 16),
    pal: pal, thresholds: thr
  )

# ── Pixel operations ─────────────────────────────────────────────────

proc pixIdx*(c: BrailleCanvas, x, y: int): int {.inline.} = y * c.pixW + x

proc addPixel*(c: var BrailleCanvas, x, y: int, intensity: float) {.inline.} =
  if x >= 0 and x < c.pixW and y >= 0 and y < c.pixH:
    let i = c.pixIdx(x, y)
    c.pixels[i] = min(c.pixels[i] + intensity, 1.0)

proc decayPixels*(c: var BrailleCanvas, factor: float) =
  for i in 0..<c.pixels.len:
    c.pixels[i] *= factor
    if c.pixels[i] < MinBright: c.pixels[i] = 0.0

# ── Braille encoding ─────────────────────────────────────────────────
# Braille base: U+2800
# Bit positions within the cell:
#   col 0: bits 0,1,2,6 (top to bottom)
#   col 1: bits 3,4,5,7 (top to bottom)

const DotBits = [
  [0u8, 1, 2, 6],  # left column: rows 0-3
  [3u8, 4, 5, 7],  # right column: rows 0-3
]

proc brailleChar(pattern: uint8): string =
  ## Convert an 8-bit dot pattern to a UTF-8 braille character.
  let codepoint = 0x2800 + pattern.int
  # UTF-8 encode: braille is U+2800..U+28FF (3 bytes)
  result = newString(3)
  result[0] = char(0xE0 or (codepoint shr 12))
  result[1] = char(0x80 or ((codepoint shr 6) and 0x3F))
  result[2] = char(0x80 or (codepoint and 0x3F))

# ── Flush ────────────────────────────────────────────────────────────

proc tintFor*(c: BrailleCanvas, b: float): Tint {.inline.} =
  if b > c.thresholds[0]: tHot
  elif b > c.thresholds[1]: tWarm
  elif b > c.thresholds[2]: tNormal
  else: tDim

proc ansiFor*(c: BrailleCanvas, t: Tint): string {.inline.} =
  case t
  of tHot:    c.pal.hot
  of tWarm: c.pal.bright
  of tNormal: c.pal.normal
  of tDim:    c.pal.dim
  of tNone:   c.pal.reset

proc flush*(c: var BrailleCanvas,
            textOverlays: openArray[(int, int, Tint, string)] = []) =
  c.buf.setLen(0)
  c.buf.add "\x1b[H"

  var last = tNone

  for ty in 0..<c.h:
    for tx in 0..<c.w:
      # Build the 8-bit dot pattern for this cell
      var pattern: uint8 = 0
      var maxB: float = 0.0
      var anyLit = false

      for col in 0..1:
        for row in 0..3:
          let px = tx * 2 + col
          let py = ty * 4 + row
          if px < c.pixW and py < c.pixH:
            let b = c.pixels[c.pixIdx(px, py)]
            if b > MinBright:
              pattern = pattern or (1u8 shl DotBits[col][row])
              if b > maxB: maxB = b
              anyLit = true

      if anyLit:
        let tint = c.tintFor(maxB)
        if tint != last:
          c.buf.add "\x1b[0m"
          c.buf.add c.ansiFor(tint)
          last = tint
        c.buf.add brailleChar(pattern)
      else:
        if last != tNone:
          c.buf.add c.pal.reset
          last = tNone
        c.buf.add " "

  c.buf.add "\x1b[0m"

  for (x, y, tint, text) in textOverlays:
    if y >= 0 and y < c.h and x >= 0:
      c.buf.add "\x1b["
      c.buf.add $(y + 1)
      c.buf.add ";"
      c.buf.add $(x + 1)
      c.buf.add "H"
      c.buf.add c.ansiFor(tint)
      c.buf.add text

  c.buf.add "\x1b[0m"
  stdout.write c.buf
  stdout.flushFile()

# Terminal setup/teardown and termWidth/termHeight — use from term.nim
