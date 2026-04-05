## Terminal oscilloscope with CRT phosphor physics.
##
##   - CRT boot/shutdown animations (ported from AetherTune)
##   - Y-T (time-domain) and X-Y (Lissajous) display modes
##   - Phosphor persistence with bloom and decay
##   - Half-block rendering for 2× vertical resolution
##   - Live audio via libavdevice (dlopen, zero dependencies)

import illwill, os
import osc/[effects, phosphor, scope, audio]

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

proc main() =
  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()

  var w = terminalWidth()
  var h = terminalHeight()
  var tb = newTerminalBuffer(w, h)

  crtTurnOn(tb, w, h)

  var scope = initScope(w, h)
  var audio = startAudio()
  var running = true

  while running:
    let nw = terminalWidth()
    let nh = terminalHeight()
    if nw != w or nh != h:
      w = nw
      h = nh
      scope.resize(w, h)

    if not scope.frozen:
      audio.readSamples(scope)

    scope.phosphor.decay()

    if not scope.frozen:
      scope.renderTrace()

    tb = newTerminalBuffer(w, h)
    scope.phosphor.render(tb)
    drawGraticule(tb, w, h, scope.grid)
    drawHUD(tb, w, h, scope, audio.sourceLabel)
    tb.display()

    let key = getKey()
    case key
    of Key.Q, Key.Escape:
      running = false
    of Key.M:
      scope.mode = if scope.mode == ModeYT: ModeXY else: ModeYT
    of Key.Plus, Key.Equals:
      scope.gain = min(scope.gain * 1.3, 20.0)
    of Key.Minus:
      scope.gain = max(scope.gain / 1.3, 0.5)
    of Key.RightBracket:
      scope.timeDiv = min(scope.timeDiv * 1.5, 16.0)
    of Key.LeftBracket:
      scope.timeDiv = max(scope.timeDiv / 1.5, 0.25)
    of Key.Space:
      scope.frozen = not scope.frozen
    of Key.G:
      scope.grid = case scope.grid
        of gsGrid: gsCross
        of gsCross: gsOff
        of gsOff: gsGrid
    else:
      discard

    sleep(16)

  audio.stop()
  crtTurnOff(tb, w, h)

  tb = newTerminalBuffer(w, h)
  tb.display()
  sleep(100)
  illwillDeinit()
  showCursor()

when isMainModule:
  main()
