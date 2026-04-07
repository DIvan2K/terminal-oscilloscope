## Terminal oscilloscope with CRT phosphor physics.
## Zero dependencies beyond Nim stdlib + libav (dlopen at runtime).

import os
import posix/termios as ptermios
from posix import read
import osc/canvas/[term, effects]
import osc/[scope, audio]

# ── Configuration ────────────────────────────────────────────────────
# Edit these to tune the look.

const
  # Phosphor physics
  Decay = 0.85           # persistence per frame (0.0–1.0)
  Beam = 0.4             # intensity at beam impact
  Bloom = 0.08           # horizontal glow spread

  # Phosphor glow thresholds
  HotGlow = 0.7          # white-hot beam core
  WarmGlow = 0.4         # bright phosphor
  CoolGlow = 0.15        # dim persistence trail

  # Palette: green, amber, cyan, blue, white, red
  Palette = "green"

# ── Audio thread via Channel ─────────────────────────────────────────

type AudioFrame = object
  samples: array[4096, array[2, float]]
  count: int

var
  audioChan: Channel[AudioFrame]
  audioRunning: bool

proc audioThread(aud: ptr AudioCapture) {.thread.} =
  var scope = initScope(1, 1)
  while audioRunning:
    aud[].readSamples(scope)
    if scope.sampleCount > 0:
      var frame: AudioFrame
      frame.count = min(scope.sampleCount, 4096)
      for i in 0..<frame.count:
        frame.samples[i] = [scope.samplesL[i], scope.samplesR[i]]
      audioChan.send(frame)

# ── Raw terminal input ───────────────────────────────────────────────

var savedTermios: ptermios.Termios

proc setRawMode() =
  discard tcGetAttr(0.cint, addr savedTermios)
  var raw = savedTermios
  raw.c_lflag = raw.c_lflag and not (ECHO or ICANON)
  raw.c_cc[VMIN] = 0.char
  raw.c_cc[VTIME] = 0.char
  discard tcSetAttr(0.cint, TCSANOW, addr raw)

proc restoreMode() =
  discard tcSetAttr(0.cint, TCSANOW, addr savedTermios)

proc readKey(): char =
  var ch: char
  if read(0.cint, addr ch, 1) == 1: ch else: '\0'

# ── Phosphor ─────────────────────────────────────────────────────────

proc plotDot(c: var Canvas, fx, fy: float) =
  let x = int(fx); let y = int(fy)
  c.addPixel(x, y, Beam)
  c.addPixel(x - 1, y, Bloom)
  c.addPixel(x + 1, y, Bloom)

proc plotLine(c: var Canvas, x0, y0, x1, y1: float) =
  let steps = max(int(max(abs(x1 - x0), abs(y1 - y0))), 1)
  for i in 0..steps:
    let t = i.float / steps.float
    c.plotDot(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)

proc renderTrace(c: var Canvas, scope: Scope) =
  if scope.sampleCount < 2: return
  let w = c.pixW; let h = c.pixH
  let cy = h.float / 2.0; let gain = scope.gain

  case scope.mode
  of ModeYT:
    let visible = max(int(scope.sampleCount.float / scope.timeDiv), 2)
    var px, py: float; var first = true
    for col in 0..<w:
      let s = min((col * visible) div w, scope.sampleCount - 1)
      let x = col.float; let y = cy - scope.samplesL[s] * gain * cy * 0.5
      if first: c.plotDot(x, y) else: c.plotLine(px, py, x, y)
      first = false; px = x; py = y
  of ModeXY:
    var px, py: float; var first = true
    let step = max(scope.sampleCount div 1024, 1)
    for i in countup(0, scope.sampleCount - 1, step):
      let x = (1.0 + scope.samplesL[i] * gain * 0.5) * w.float / 2.0
      let y = (1.0 - scope.samplesR[i] * gain * 0.5) * h.float / 2.0
      if first: c.plotDot(x, y) else: c.plotLine(px, py, x, y)
      first = false; px = x; py = y

# ── Main ─────────────────────────────────────────────────────────────

proc main() =
  initTerm()
  setRawMode()

  var w = termWidth(); var h = termHeight()
  var c = newCanvas(w, h, Palette, [HotGlow, WarmGlow, CoolGlow])
  crtTurnOn(c)
  var scope = initScope(w, h)
  var aud = startAudio()
  var running = true

  audioChan.open()
  audioRunning = true
  var aThread: Thread[ptr AudioCapture]
  createThread(aThread, audioThread, addr aud)

  while running:
    let nw = termWidth(); let nh = termHeight()
    if nw != w or nh != h:
      w = nw; h = nh; c.resize(w, h); scope.resize(w, h)

    let got = audioChan.tryRecv()
    if got.dataAvailable:
      scope.sampleCount = got.msg.count
      for i in 0..<got.msg.count:
        scope.samplesL[i] = got.msg.samples[i][0]
        scope.samplesR[i] = got.msg.samples[i][1]

    c.decayPixels(Decay)
    c.renderTrace(scope)

    let hud = " " & (if scope.mode == ModeYT: "Y-T" else: "X-Y") &
              " G:" & $scope.gain & " "
    let help = " m:mode +/-:gain [/]:time q:quit "
    c.flush([(1, 0, tBright, hud),
             (w - help.len - 1, h - 1, tDim, help)])

    sleep(16)

    case readKey()
    of 'q', '\x1b': running = false
    of 'm': scope.mode = if scope.mode == ModeYT: ModeXY else: ModeYT
    of '+', '=': scope.gain = min(scope.gain * 1.3, 20.0)
    of '-': scope.gain = max(scope.gain / 1.3, 0.5)
    of ']': scope.timeDiv = min(scope.timeDiv * 1.5, 16.0)
    of '[': scope.timeDiv = max(scope.timeDiv / 1.5, 0.25)
    else: discard

  audioRunning = false
  joinThread(aThread)
  audioChan.close()
  aud.stop()
  crtTurnOff(c)
  restoreMode()
  deinitTerm()

when isMainModule:
  main()
