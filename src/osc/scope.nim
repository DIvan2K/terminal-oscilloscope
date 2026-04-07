## Oscilloscope state — display mode and sample buffers.

type
  DisplayMode* = enum
    ModeYT   ## Time-domain: x=time, y=amplitude
    ModeXY   ## Lissajous:   x=left, y=right

  Scope* = object
    mode*: DisplayMode
    samplesL*, samplesR*: seq[float]
    sampleCount*: int
    gain*: float
    timeDiv*: float

proc initScope*(w, h: int): Scope =
  Scope(
    mode: ModeYT,
    samplesL: newSeq[float](4096),
    samplesR: newSeq[float](4096),
    sampleCount: 0,
    gain: 6.5,
    timeDiv: 3.4
  )

proc resize*(scope: var Scope, w, h: int) =
  discard  # scope doesn't depend on terminal size
