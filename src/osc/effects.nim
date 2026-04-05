## CRT turn-on and turn-off animations
## Ported from AetherTune's Rust/ratatui implementation

import illwill, os, times, math, std/random

const
  # Turn-on phase timing (ms)
  OnFlashMs     = 60
  OnGlitchMs    = 200
  OnPhosphorMs  = 500
  OnStaticMs    = 650
  OnBeamMs      = 1100
  OnTotalMs     = 1200

  # Turn-off phase timing (ms)
  OffCollapseMs = 500
  OffSqueezeMs  = 800
  OffDotMs      = 1200
  OffFadeMs     = 1600

  GlitchChars = ["█", "▓", "▒", "░", "▄", "▀", "■", "□",
                 "╬", "╠", "╣", "═", "║", "·", ":", "!",
                 "@", "#", "$", "%", "^", "&", "*"]
  NoiseChars  = ["░", "▒", "▓", "│", "─", "┼", "╬", "·",
                 ":", ";", "!", "?", "$", "#", "@", "%"]

proc lcg(state: var uint64): uint64 =
  state = state * 6364136223846793005'u64 + 1'u64
  result = state

proc elapsedMs(start: Time): int =
  int((getTime() - start).inMilliseconds)

proc brightColor(b: float): ForegroundColor =
  if b > 0.8: fgWhite elif b > 0.4: fgGreen else: fgGreen

proc crtTurnOn*(tb: var TerminalBuffer, w, h: int) =
  let start = getTime()
  var rng = initRand(42)

  while true:
    let elapsed = elapsedMs(start)
    if elapsed >= OnTotalMs: break
    tb = newTerminalBuffer(w, h)

    if elapsed < OnFlashMs:
      # Phase 1: White flash — high-voltage discharge
      let c = if elapsed < OnFlashMs div 2: fgWhite else: fgGreen
      for y in 0..<h:
        for x in 0..<w:
          tb.write(x, y, c, styleReverse, " ")

    elif elapsed < OnGlitchMs:
      # Phase 2: Glitch burst — scattered block characters
      let count = 8 + (elapsed - OnFlashMs) div 4
      for i in 0..<count:
        let ch = GlitchChars[rng.rand(GlitchChars.high)]
        let color = if rng.rand(2) == 0: fgGreen
                    elif rng.rand(2) == 1: fgGreen
                    else: fgWhite
        tb.write(rng.rand(w - 1), rng.rand(h - 1), color, ch)

    elif elapsed < OnPhosphorMs:
      # Phase 3: Phosphor ramp — screen fills with brightening blocks
      let p = (elapsed - OnGlitchMs).float / (OnPhosphorMs - OnGlitchMs).float
      let ch = if p < 0.4: "░" elif p < 0.8: "▒" else: "▓"
      let color = if p < 0.4: fgGreen elif p < 0.7: fgGreen else: fgWhite
      for y in 0..<h:
        for x in 0..<w:
          tb.write(x, y, color, ch)

    elif elapsed < OnStaticMs:
      # Phase 4: Static noise burst
      var seed = uint64(elapsed) * 7919
      for y in 0..<h:
        for x in 0..<w:
          let r = lcg(seed)
          let ch = NoiseChars[int(r shr 16) mod NoiseChars.len]
          let color = [fgGreen, fgGreen, fgWhite, fgGreen][int(r shr 24) mod 4]
          tb.write(x, y, color, ch)

    elif elapsed < OnBeamMs:
      # Phase 5: Beam sweep — electron beam scans top to center
      let beamRow = int((elapsed - OnStaticMs).float /
                        (OnBeamMs - OnStaticMs).float * (h.float / 2.0))
      for y in 0..<h:
        let dist = abs(y - beamRow)
        if dist == 0:
          for x in 0..<w: tb.write(x, y, fgWhite, styleBright, "━")
        elif dist == 1:
          for x in 0..<w: tb.write(x, y, fgGreen, "─")
        elif dist <= 3 and y < beamRow:
          for x in 0..<w: tb.write(x, y, fgGreen, styleDim, "─")

    tb.display()
    sleep(16)

proc crtTurnOff*(tb: var TerminalBuffer, w, h: int) =
  let start = getTime()
  let cx = w div 2
  let cy = h div 2

  while true:
    let elapsed = elapsedMs(start)
    if elapsed >= OffFadeMs: break
    tb = newTerminalBuffer(w, h)

    if elapsed < OffCollapseMs:
      # Phase 1: Vertical collapse to center row
      let t = elapsed.float / OffCollapseMs.float
      let halfH = int((1.0 - t) * (h.float / 2.0))
      for y in max(cy - halfH, 0)..<min(cy + halfH + 1, h):
        let b = 1.0 - abs(y - cy).float / max(halfH, 1).float * 0.6
        let ch = if b > 0.8: "▓" elif b > 0.6: "▒" elif b > 0.3: "░" else: "·"
        for x in 0..<w:
          tb.write(x, y, brightColor(b), ch)

    elif elapsed < OffSqueezeMs:
      # Phase 2: Horizontal squeeze to dot
      let t = (elapsed - OffCollapseMs).float / (OffSqueezeMs - OffCollapseMs).float
      let eased = 1.0 - (1.0 - t) * (1.0 - t)
      let halfW = int((1.0 - eased) * (w.float / 2.0))
      let rows = if halfW > 2: @[cy - 1, cy, cy + 1] else: @[cy]
      for y in rows:
        if y < 0 or y >= h: continue
        let isCentre = y == cy
        for x in max(cx - halfW, 0)..<min(cx + halfW + 1, w):
          let b = (if isCentre: 1.0 else: 0.55) *
                  (1.0 - abs(x - cx).float / max(halfW, 1).float * 0.4)
          tb.write(x, y, brightColor(b), if isCentre: "━" else: "─")

    elif elapsed < OffDotMs:
      # Phase 3: Bright dot with phosphor glow
      let t = (elapsed - OffSqueezeMs).float / (OffDotMs - OffSqueezeMs).float
      let glowR = max(int(3.0 * (1.0 - t)), 1)
      for dy in -glowR..glowR:
        for dx in (-glowR * 2)..(glowR * 2):
          let dist = sqrt((dx.float / 2.0) * (dx.float / 2.0) + dy.float * dy.float)
          if dist > glowR.float: continue
          let (px, py) = (cx + dx, cy + dy)
          if px < 0 or px >= w or py < 0 or py >= h: continue
          let b = (1.0 - t * 0.3) * (1.0 - dist / glowR.float)
          let ch = if dx == 0 and dy == 0: "●"
                   elif dist < glowR.float * 0.4: "░"
                   else: "·"
          tb.write(px, py, brightColor(b), ch)

    else:
      # Phase 4: Fade to black
      let b = 1.0 - (elapsed - OffDotMs).float / (OffFadeMs - OffDotMs).float
      if b > 0.05:
        tb.write(cx, cy, (if b > 0.5: fgGreen else: fgGreen), "·")

    tb.display()
    sleep(16)
