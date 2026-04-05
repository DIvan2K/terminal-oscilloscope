## Phosphor buffer with CRT physics: persistence decay, beam bloom,
## and half-block rendering with intensity-based shading.

import illwill, math

const
  PhosphorDecay*  = 0.60   # per-frame persistence (P31 green phosphor)
  BeamIntensity*  = 0.9    # brightness at beam impact
  BloomInner*     = 0.25   # glow spread to adjacent pixels
  BloomOuter*     = 0.08   # faint halo from electron scatter
  MinBright*      = 0.02   # below this, phosphor is considered off

type
  Intensity* = enum
    iHot     ## beam core — white-hot
    iBright  ## fluoro green phosphor
    iMedium  ## green glow
    iDim     ## faint persistence trail

  PhosphorBuffer* = object
    w*, h*: int          # terminal columns/rows
    pixH*: int           # pixel height (2× rows via half-blocks)
    data*: seq[float]    # brightness per pixel [w × pixH]

proc initPhosphor*(w, h: int): PhosphorBuffer =
  let pixH = h * 2
  PhosphorBuffer(w: w, h: h, pixH: pixH, data: newSeq[float](w * pixH))

proc idx(pb: PhosphorBuffer, x, y: int): int {.inline.} =
  y * pb.w + x

proc add(pb: var PhosphorBuffer, x, y: int, intensity: float) {.inline.} =
  if x >= 0 and x < pb.w and y >= 0 and y < pb.pixH:
    pb.data[pb.idx(x, y)] = min(pb.data[pb.idx(x, y)] + intensity, 1.0)

proc decay*(pb: var PhosphorBuffer) =
  for i in 0..<pb.data.len:
    pb.data[i] *= PhosphorDecay
    if pb.data[i] < MinBright:
      pb.data[i] = 0.0

proc plotDot*(pb: var PhosphorBuffer, fx, fy: float) =
  ## Deposit a phosphor dot with physics-based bloom.
  let x = int(fx)
  let y = int(fy)
  if x < 0 or x >= pb.w or y < 0 or y >= pb.pixH: return

  # Beam impact
  pb.add(x, y, BeamIntensity)
  # Inner bloom — phosphor scatter
  pb.add(x, y - 1, BloomInner)
  pb.add(x, y + 1, BloomInner)
  pb.add(x - 1, y, BloomInner * 0.5)
  pb.add(x + 1, y, BloomInner * 0.5)
  # Outer bloom — electron scatter
  pb.add(x, y - 2, BloomOuter)
  pb.add(x, y + 2, BloomOuter)
  pb.add(x - 1, y - 1, BloomOuter)
  pb.add(x + 1, y - 1, BloomOuter)
  pb.add(x - 1, y + 1, BloomOuter)
  pb.add(x + 1, y + 1, BloomOuter)

proc plotLine*(pb: var PhosphorBuffer, x0, y0, x1, y1: float) =
  ## Interpolated line of phosphor dots between two points.
  let steps = max(int(max(abs(x1 - x0), abs(y1 - y0))), 1)
  for i in 0..steps:
    let t = i.float / steps.float
    pb.plotDot(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)

# ── Half-block rendering ────────────────────────────────────────────

proc toIntensity*(b: float): Intensity =
  if b > 0.7: iHot elif b > 0.4: iBright elif b > 0.15: iMedium else: iDim

proc writePhosphor*(tb: var TerminalBuffer, x, y: int, ch: string,
                    intensity: Intensity) =
  case intensity
  of iHot:    tb.write(x, y, fgWhite, styleBright, ch)
  of iBright: tb.write(x, y, fgGreen, styleBright, ch)
  of iMedium: tb.write(x, y, fgGreen, ch)
  of iDim:    tb.write(x, y, fgGreen, styleDim, ch)

proc render*(pb: PhosphorBuffer, tb: var TerminalBuffer) =
  ## Blit the phosphor buffer to the terminal using half-block characters.
  for ty in 0..<pb.h:
    let topRow = ty * 2
    let botRow = ty * 2 + 1
    for x in 0..<pb.w:
      let topB = if topRow < pb.pixH: pb.data[pb.idx(x, topRow)] else: 0.0
      let botB = if botRow < pb.pixH: pb.data[pb.idx(x, botRow)] else: 0.0

      if topB > MinBright or botB > MinBright:
        let tOn = topB > MinBright
        let bOn = botB > MinBright
        if tOn and bOn:
          tb.writePhosphor(x, ty, "█", toIntensity(max(topB, botB)))
        elif tOn:
          tb.writePhosphor(x, ty, "▀", toIntensity(topB))
        else:
          tb.writePhosphor(x, ty, "▄", toIntensity(botB))
