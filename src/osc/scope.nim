## Oscilloscope: trace rendering, graticule grid, and HUD overlay.

import illwill, strutils
import phosphor

type
  DisplayMode* = enum
    ModeYT   ## Time-domain: x=time, y=amplitude
    ModeXY   ## Lissajous:   x=left, y=right

  GridStyle* = enum
    gsGrid     ## Full graticule
    gsOff      ## No grid

  Scope* = object
    phosphor*: PhosphorBuffer
    mode*: DisplayMode
    samplesL*, samplesR*: seq[float]
    sampleCount*: int
    gain*: float       # amplitude scaling (volts/div)
    timeDiv*: float    # horizontal zoom (time/div)
    frozen*: bool
    grid*: GridStyle

proc initScope*(w, h: int): Scope =
  Scope(
    phosphor: initPhosphor(w, h),
    mode: ModeYT,
    samplesL: newSeq[float](4096),
    samplesR: newSeq[float](4096),
    sampleCount: 0,
    gain: 5.0,
    timeDiv: 2.25,
    frozen: false,
    grid: gsOff
  )

proc w*(s: Scope): int = s.phosphor.w
proc h*(s: Scope): int = s.phosphor.h

proc resize*(scope: var Scope, w, h: int) =
  if w == scope.w and h == scope.h: return
  scope.phosphor = initPhosphor(w, h)

# ── Trace rendering ──────────────────────────────────────────────────

proc renderTrace*(scope: var Scope) =
  if scope.sampleCount < 2: return

  let w = scope.w
  let pixH = scope.phosphor.pixH
  let cy = pixH.float / 2.0
  let gain = scope.gain

  case scope.mode
  of ModeYT:
    let visible = max(int(scope.sampleCount.float / scope.timeDiv), 2)
    var prevX, prevY: float
    var first = true
    for col in 0..<w:
      let sIdx = min((col * visible) div w, scope.sampleCount - 1)
      let y = cy - scope.samplesL[sIdx] * gain * cy * 0.5
      let x = col.float
      if first:
        scope.phosphor.plotDot(x, y)
      else:
        scope.phosphor.plotLine(prevX, prevY, x, y)
      first = false
      prevX = x
      prevY = y

  of ModeXY:
    var prevX, prevY: float
    var first = true
    let step = max(scope.sampleCount div 1024, 1)
    for i in countup(0, scope.sampleCount - 1, step):
      let x = (1.0 + scope.samplesL[i] * gain * 0.5) * w.float / 2.0
      let y = (1.0 - scope.samplesR[i] * gain * 0.5) * pixH.float / 2.0
      if first:
        scope.phosphor.plotDot(x, y)
      else:
        scope.phosphor.plotLine(prevX, prevY, x, y)
      first = false
      prevX = x
      prevY = y

# ── Graticule ────────────────────────────────────────────────────────

proc drawGraticule*(tb: var TerminalBuffer, w, h: int, grid: GridStyle) =
  if grid == gsOff: return

  let cx = w div 2
  let cy = h div 2

  # Division lines
  for d in 1..<10:
    let x = d * w div 10
    if x > 0 and x < w:
      for y in 0..<h:
        tb.write(x, y, fgGreen, styleDim, "│")
  for d in 1..<8:
    let y = d * h div 8
    if y > 0 and y < h:
      for x in 0..<w:
        tb.write(x, y, fgGreen, styleDim, "─")

  # Center crosshair
  for x in 0..<w: tb.write(x, cy, fgGreen, styleDim, "─")
  for y in 0..<h: tb.write(cx, y, fgGreen, styleDim, "│")
  tb.write(cx, cy, fgGreen, "┼")

  # Intersections
  for dx in 1..<10:
    let x = dx * w div 10
    if x > 0 and x < w:
      for dy in 1..<8:
        let y = dy * h div 8
        if y > 0 and y < h:
          tb.write(x, y, fgGreen, styleDim, "┼")

# ── HUD ──────────────────────────────────────────────────────────────

proc drawHUD*(tb: var TerminalBuffer, w, h: int, scope: Scope,
              source: string) =
  let modeStr = case scope.mode
    of ModeYT: "Y-T"
    of ModeXY: "X-Y"
  let gainStr = " G:" & formatFloat(scope.gain, ffDecimal, 1)
  let tdStr = if scope.mode == ModeYT:
                " T:" & formatFloat(scope.timeDiv, ffDecimal, 1)
              else: ""
  let freezeStr = if scope.frozen: " ▌▌" else: ""
  tb.write(1, 0, fgGreen, styleBright,
           " " & modeStr & gainStr & tdStr & freezeStr & " ")
  tb.write(w - source.len - 2, 0, fgGreen, styleDim, source)

  let help = " m:mode +/-:gain [/]:time g:grid spc:freeze q:quit "
  tb.write(w - help.len - 1, h - 1, fgGreen, styleDim, help)
