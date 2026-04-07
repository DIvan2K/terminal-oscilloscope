## CRT turn-on and turn-off animations using direct ANSI output.
## Uses the same block characters as the original illwill version.

import os, times, math, std/random
import term

const
  OnFlashMs     = 60
  OnGlitchMs    = 200
  OnPhosphorMs  = 500
  OnStaticMs    = 650
  OnBeamMs      = 1100
  OnTotalMs     = 1200

  OffCollapseMs = 500
  OffSqueezeMs  = 800
  OffDotMs      = 1200
  OffFadeMs     = 1600

  GlitchChars = ["█", "▓", "▒", "░", "▄", "▀", "■", "□",
                 "╬", "╠", "╣", "═", "║", "·", ":", "!",
                 "@", "#", "$", "%", "^", "&", "*"]
  NoiseChars  = ["░", "▒", "▓", "│", "─", "┼", "╬", "·",
                 ":", ";", "!", "?", "$", "#", "@", "%"]

proc elapsedMs(start: Time): int =
  int((getTime() - start).inMilliseconds)

proc lcg(state: var uint64): uint64 =
  state = state * 6364136223846793005'u64 + 1'u64
  result = state

proc goto(buf: var string, x, y: int) =
  buf.add "\x1b["
  buf.add $(y + 1)
  buf.add ";"
  buf.add $(x + 1)
  buf.add "H"

proc crtTurnOn*(c: Canvas) =
  let start = getTime()
  var rng = initRand(42)
  let w = c.w
  let h = c.h
  var buf = newStringOfCap(w * h * 12)

  while true:
    let elapsed = elapsedMs(start)
    if elapsed >= OnTotalMs: break
    buf.setLen(0)
    buf.add "\x1b[H"  # cursor home

    if elapsed < OnFlashMs:
      # Phase 1: White flash
      let ansi = if elapsed < OnFlashMs div 2: c.ansiFor(tHot) else: c.ansiFor(tBright)
      buf.add "\x1b[0m"
      buf.add ansi
      for y in 0..<h:
        for x in 0..<w:
          buf.add "█"

    elif elapsed < OnGlitchMs:
      # Phase 2: Glitch burst
      buf.add "\x1b[0m"
      # Fill with spaces first
      for i in 0..<w*h: buf.add " "
      let count = 8 + (elapsed - OnFlashMs) div 4
      for i in 0..<count:
        let gx = rng.rand(w - 1)
        let gy = rng.rand(h - 1)
        let ch = GlitchChars[rng.rand(GlitchChars.high)]
        let tint = if rng.rand(2) == 0: tBright else: tHot
        buf.goto(gx, gy)
        buf.add "\x1b[0m"
        buf.add c.ansiFor(tint)
        buf.add ch

    elif elapsed < OnPhosphorMs:
      # Phase 3: Phosphor ramp
      let p = (elapsed - OnGlitchMs).float / (OnPhosphorMs - OnGlitchMs).float
      let ch = if p < 0.4: "░" elif p < 0.8: "▒" else: "▓"
      let tint = if p < 0.4: tDim elif p < 0.7: tNormal else: tBright
      buf.add "\x1b[0m"
      buf.add c.ansiFor(tint)
      for y in 0..<h:
        for x in 0..<w:
          buf.add ch

    elif elapsed < OnStaticMs:
      # Phase 4: Static noise
      var seed = uint64(elapsed) * 7919
      for y in 0..<h:
        for x in 0..<w:
          let r = lcg(seed)
          let ch = NoiseChars[int(r shr 16) mod NoiseChars.len]
          let tint = [tNormal, tBright, tHot, tNormal][int(r shr 24) mod 4]
          buf.add "\x1b[0m"
          buf.add c.ansiFor(tint)
          buf.add ch

    elif elapsed < OnBeamMs:
      # Phase 5: Beam sweep to center
      buf.add "\x1b[0m"
      for i in 0..<w*h: buf.add " "
      let beamRow = int((elapsed - OnStaticMs).float /
                        (OnBeamMs - OnStaticMs).float * (h.float / 2.0))
      for y in 0..<h:
        let dist = abs(y - beamRow)
        if dist <= 3:
          buf.goto(0, y)
          if dist == 0:
            buf.add "\x1b[0m"
            buf.add c.ansiFor(tHot)
            for x in 0..<w: buf.add "━"
          elif dist == 1:
            buf.add "\x1b[0m"
            buf.add c.ansiFor(tBright)
            for x in 0..<w: buf.add "─"
          elif y < beamRow:
            buf.add "\x1b[0m"
            buf.add c.ansiFor(tDim)
            for x in 0..<w: buf.add "─"

    buf.add "\x1b[0m"
    stdout.write buf
    stdout.flushFile()
    sleep(16)

proc crtTurnOff*(c: Canvas) =
  let start = getTime()
  let w = c.w
  let h = c.h
  let cx = w div 2
  let cy = h div 2
  var buf = newStringOfCap(w * h * 12)

  while true:
    let elapsed = elapsedMs(start)
    if elapsed >= OffFadeMs: break
    buf.setLen(0)
    buf.add "\x1b[H\x1b[0m"
    for i in 0..<w*h: buf.add " "

    if elapsed < OffCollapseMs:
      # Phase 1: Vertical collapse
      let t = elapsed.float / OffCollapseMs.float
      let halfH = int((1.0 - t) * (h.float / 2.0))
      for y in max(cy - halfH, 0)..<min(cy + halfH + 1, h):
        let b = 1.0 - abs(y - cy).float / max(halfH, 1).float * 0.6
        let ch = if b > 0.8: "▓" elif b > 0.6: "▒" elif b > 0.3: "░" else: "·"
        let tint = if b > 0.8: tHot elif b > 0.4: tBright else: tNormal
        buf.goto(0, y)
        buf.add "\x1b[0m"
        buf.add c.ansiFor(tint)
        for x in 0..<w: buf.add ch

    elif elapsed < OffSqueezeMs:
      # Phase 2: Horizontal squeeze
      let t = (elapsed - OffCollapseMs).float / (OffSqueezeMs - OffCollapseMs).float
      let eased = 1.0 - (1.0 - t) * (1.0 - t)
      let halfW = int((1.0 - eased) * (w.float / 2.0))
      let rows = if halfW > 2: @[cy - 1, cy, cy + 1] else: @[cy]
      for y in rows:
        if y < 0 or y >= h: continue
        let isCentre = y == cy
        buf.goto(max(cx - halfW, 0), y)
        buf.add "\x1b[0m"
        buf.add c.ansiFor(if isCentre: tHot else: tNormal)
        for x in max(cx - halfW, 0)..<min(cx + halfW + 1, w):
          buf.add (if isCentre: "━" else: "─")

    elif elapsed < OffDotMs:
      # Phase 3: Bright dot with glow
      let t = (elapsed - OffSqueezeMs).float / (OffDotMs - OffSqueezeMs).float
      let glowR = max(int(3.0 * (1.0 - t)), 1)
      for dy in -glowR..glowR:
        for dx in (-glowR * 2)..(glowR * 2):
          let dist = sqrt((dx.float / 2.0) * (dx.float / 2.0) + dy.float * dy.float)
          if dist > glowR.float: continue
          let (px, py) = (cx + dx, cy + dy)
          if px < 0 or px >= w or py < 0 or py >= h: continue
          let falloff = 1.0 - dist / glowR.float
          let ch = if dx == 0 and dy == 0: "●"
                   elif dist < glowR.float * 0.4: "░"
                   else: "·"
          let tint = if falloff > 0.7: tHot
                     elif falloff > 0.4: tBright
                     else: tNormal
          buf.goto(px, py)
          buf.add "\x1b[0m"
          buf.add c.ansiFor(tint)
          buf.add ch

    else:
      # Phase 4: Fade to black
      let t = (elapsed - OffDotMs).float / (OffFadeMs - OffDotMs).float
      if t < 0.95:
        buf.goto(cx, cy)
        buf.add "\x1b[0m"
        buf.add c.ansiFor(tDim)
        buf.add "·"

    buf.add "\x1b[0m"
    stdout.write buf
    stdout.flushFile()
    sleep(16)
