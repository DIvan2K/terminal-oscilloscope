## Minimal fast terminal canvas — one buffer, one write() per frame.

import terminal

const
  Upper = "▀"
  Lower = "▄"
  Full  = "█"
  MinBright* = 0.02

type
  Tint* = enum
    tNone, tDim, tNormal, tWarm, tHot

  Palette* = object
    hot*: string       # white-hot beam core
    bright*: string    # bright phosphor
    normal*: string    # standard glow
    dim*: string       # faint persistence
    reset*: string

  Canvas* = object
    w*, h*: int
    pixW*, pixH*: int
    pixels*: seq[float]
    buf: string
    pal*: Palette
    thresholds*: array[3, float]  # hot, warm, cool

# ── Built-in palettes ────────────────────────────────────────────────

proc makePalette*(name: string): Palette =
  let reset = "\x1b[0m"
  case name
  of "green":   # P31 — classic oscilloscope
    Palette(hot: "\x1b[1;37m", bright: "\x1b[1;32m",
            normal: "\x1b[32m", dim: "\x1b[2;32m", reset: reset)
  of "amber":   # P12 — warm terminal
    Palette(hot: "\x1b[1;37m", bright: "\x1b[1;33m",
            normal: "\x1b[33m", dim: "\x1b[2;33m", reset: reset)
  of "cyan":    # P7 — tektronix blue-green
    Palette(hot: "\x1b[1;37m", bright: "\x1b[1;36m",
            normal: "\x1b[36m", dim: "\x1b[2;36m", reset: reset)
  of "blue":    # P11 — cool/modern
    Palette(hot: "\x1b[1;37m", bright: "\x1b[1;34m",
            normal: "\x1b[34m", dim: "\x1b[2;34m", reset: reset)
  of "white":   # P4 — TV phosphor
    Palette(hot: "\x1b[1;37m", bright: "\x1b[37m",
            normal: "\x1b[2;37m", dim: "\x1b[2;90m", reset: reset)
  of "red":     # P22-R — radar display
    Palette(hot: "\x1b[1;37m", bright: "\x1b[1;31m",
            normal: "\x1b[31m", dim: "\x1b[2;31m", reset: reset)
  else:         # default to green
    makePalette("green")

# ── Init / resize ───────────────────────────────────────────────────

proc newCanvas*(w, h: int, palette = "green",
                thresholds = [0.7, 0.4, 0.15]): Canvas =
  Canvas(
    w: w, h: h, pixW: w, pixH: h * 2,
    pixels: newSeq[float](w * h * 2),
    buf: newStringOfCap(w * h * 16),
    pal: makePalette(palette),
    thresholds: thresholds
  )

proc resize*(c: var Canvas, w, h: int) =
  if w == c.w and h == c.h: return
  let pal = c.pal
  let thr = c.thresholds
  c = Canvas(
    w: w, h: h, pixW: w, pixH: h * 2,
    pixels: newSeq[float](w * h * 2),
    buf: newStringOfCap(w * h * 16),
    pal: pal, thresholds: thr
  )

# ── Pixel operations ─────────────────────────────────────────────────

proc pixIdx*(c: Canvas, x, y: int): int {.inline.} = y * c.pixW + x

proc addPixel*(c: var Canvas, x, y: int, intensity: float) {.inline.} =
  if x >= 0 and x < c.pixW and y >= 0 and y < c.pixH:
    let i = c.pixIdx(x, y)
    c.pixels[i] = min(c.pixels[i] + intensity, 1.0)

proc decayPixels*(c: var Canvas, factor: float) =
  for i in 0..<c.pixels.len:
    c.pixels[i] *= factor
    if c.pixels[i] < MinBright: c.pixels[i] = 0.0

# ── Flush entire frame ───────────────────────────────────────────────

proc tintFor*(c: Canvas, b: float): Tint {.inline.} =
  if b > c.thresholds[0]: tHot
  elif b > c.thresholds[1]: tWarm
  elif b > c.thresholds[2]: tNormal
  else: tDim

proc ansiFor*(c: Canvas, t: Tint): string {.inline.} =
  case t
  of tHot:    c.pal.hot
  of tWarm: c.pal.bright
  of tNormal: c.pal.normal
  of tDim:    c.pal.dim
  of tNone:   c.pal.reset

proc flush*(c: var Canvas, textOverlays: openArray[(int, int, Tint, string)] = []) =
  c.buf.setLen(0)
  c.buf.add "\x1b[H"

  var last = tNone

  for ty in 0..<c.h:
    let topRow = ty * 2
    let botRow = topRow + 1
    for x in 0..<c.w:
      let topB = if topRow < c.pixH: c.pixels[c.pixIdx(x, topRow)] else: 0.0
      let botB = if botRow < c.pixH: c.pixels[c.pixIdx(x, botRow)] else: 0.0
      let tOn = topB > MinBright
      let bOn = botB > MinBright

      if tOn or bOn:
        let tint = if tOn and bOn: c.tintFor(max(topB, botB))
                   elif tOn: c.tintFor(topB)
                   else: c.tintFor(botB)
        if tint != last:
          c.buf.add "\x1b[0m"
          c.buf.add c.ansiFor(tint)
          last = tint
        if tOn and bOn: c.buf.add Full
        elif tOn: c.buf.add Upper
        else: c.buf.add Lower
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

# ── Terminal setup/teardown ──────────────────────────────────────────

proc initTerm*() =
  stdout.write "\x1b[?1049h\x1b[?25l"
  stdout.flushFile()

proc deinitTerm*() =
  stdout.write "\x1b[?25h\x1b[?1049l"
  stdout.flushFile()

proc termWidth*(): int = terminalWidth()
proc termHeight*(): int = terminalHeight()
