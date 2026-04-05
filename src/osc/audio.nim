## Audio capture: tries ffmpeg (PulseAudio monitor) → parec → demo signal.

import osproc, streams, strutils, math
import scope

type
  AudioMode* = enum
    amLive   ## Capturing real audio via ffmpeg/parec
    amDemo   ## Built-in synthesized waveforms

  AudioCapture* = object
    mode*: AudioMode
    process: Process
    stream: Stream
    phase: float
    demoFreqL*, demoFreqR*: float
    demoPreset*: int

proc findMonitorSource(): string =
  ## Find the PulseAudio monitor for the default audio sink.
  try:
    let inspect = execProcess("wpctl",
      args = ["inspect", "@DEFAULT_AUDIO_SINK@"],
      options = {poUsePath, poStdErrToStdOut})
    for line in inspect.splitLines():
      if "node.name" in line:
        let eq = line.find("=")
        if eq >= 0:
          return line[eq+1..^1].strip().strip(chars = {'"', ' '}) & ".monitor"
  except: discard
  ""

proc startAudio*(): AudioCapture =
  ## Try real audio capture, fall back to demo.
  let monitor = findMonitorSource()
  if monitor.len > 0:
    try:
      let p = startProcess("ffmpeg",
        args = ["-f", "pulse", "-i", monitor,
                "-f", "s16le", "-ac", "2", "-ar", "44100",
                "-flush_packets", "1", "-fflags", "nobuffer",
                "-loglevel", "quiet", "pipe:1"],
        options = {poUsePath})
      return AudioCapture(mode: amLive, process: p, stream: p.outputStream,
                          demoFreqL: 440.0, demoFreqR: 330.0)
    except OSError: discard

  try:
    let p = startProcess("parec",
      args = ["--format=s16le", "--channels=2", "--rate=44100",
              "--latency-msec=20"],
      options = {poUsePath})
    return AudioCapture(mode: amLive, process: p, stream: p.outputStream,
                        demoFreqL: 440.0, demoFreqR: 330.0)
  except OSError: discard

  AudioCapture(mode: amDemo, demoFreqL: 440.0, demoFreqR: 330.0)

proc stop*(cap: var AudioCapture) =
  if cap.mode == amLive:
    cap.process.terminate()
    cap.process.close()

proc sourceLabel*(cap: AudioCapture): string =
  if cap.mode == amLive: "LIVE" else: "DEMO"

proc cyclePreset*(cap: var AudioCapture) =
  ## Cycle through demo frequency ratios for interesting Lissajous patterns.
  if cap.mode != amDemo: return
  cap.demoPreset = (cap.demoPreset + 1) mod 4
  case cap.demoPreset
  of 0: cap.demoFreqL = 440.0; cap.demoFreqR = 330.0   # 4:3
  of 1: cap.demoFreqL = 440.0; cap.demoFreqR = 440.0   # 1:1
  of 2: cap.demoFreqL = 440.0; cap.demoFreqR = 220.0   # 2:1
  of 3: cap.demoFreqL = 440.0; cap.demoFreqR = 293.3   # 3:2
  else: discard

proc readSamples*(cap: var AudioCapture, scope: var Scope) =
  case cap.mode
  of amLive:
    const frameSize = 4  # 2 channels × 16-bit
    const maxFrames = 2048
    var buf: array[maxFrames * frameSize, uint8]
    let bytesRead = cap.stream.readData(addr buf[0], maxFrames * frameSize)
    if bytesRead <= 0: return
    scope.sampleCount = min(bytesRead div frameSize, scope.samplesL.len)
    for i in 0..<scope.sampleCount:
      let off = i * frameSize
      let left = cast[int16]((buf[off + 1].uint16 shl 8) or buf[off].uint16)
      let right = cast[int16]((buf[off + 3].uint16 shl 8) or buf[off + 2].uint16)
      scope.samplesL[i] = left.float / 32768.0
      scope.samplesR[i] = right.float / 32768.0

  of amDemo:
    scope.sampleCount = scope.samplesL.len
    let cycles = 3.0 / scope.timeDiv
    let drift = sin(cap.phase * 0.3) * 0.1
    let rL = cap.demoFreqL / 440.0
    let rR = cap.demoFreqR / 440.0
    for i in 0..<scope.sampleCount:
      let t = cap.phase + (i.float / scope.sampleCount.float) * cycles * 2.0 * PI
      scope.samplesL[i] = sin(t * rL) * 0.7 +
                           sin(t * rL * 2.0) * 0.15 +
                           sin(t * rL * 3.0 + drift) * 0.08
      scope.samplesR[i] = sin(t * rR + 0.5) * 0.7 +
                           sin(t * rR * 2.0 + 0.3) * 0.2
    cap.phase += 0.05
