## Audio capture via libavdevice/libavformat (direct C bindings),
## with fallback to ffmpeg subprocess, then demo signal.

import osproc, streams, strutils, math
import scope

# ── libav C helper bindings ──────────────────────────────────────────

{.compile: "avhelper.c".}
{.passL: "-ldl".}

type
  AVFormatContext = object  # opaque, only used as pointer
  AVPacket = object         # opaque, only used as pointer

proc av_helper_init(): cint {.importc, cdecl.}
proc av_helper_open_pulse(ctx: ptr ptr AVFormatContext,
    device: cstring): cint {.importc, cdecl.}
proc av_helper_find_stream_info(ctx: ptr AVFormatContext): cint
    {.importc, cdecl.}
proc av_helper_find_audio_stream(ctx: ptr AVFormatContext): cint
    {.importc, cdecl.}
proc av_helper_read_frame(ctx: ptr AVFormatContext,
    pkt: ptr AVPacket): cint {.importc, cdecl.}
proc av_helper_packet_stream(pkt: ptr AVPacket): cint {.importc, cdecl.}
proc av_helper_packet_data(pkt: ptr AVPacket): ptr UncheckedArray[uint8]
    {.importc, cdecl.}
proc av_helper_packet_size(pkt: ptr AVPacket): cint {.importc, cdecl.}
proc av_helper_packet_alloc(): ptr AVPacket {.importc, cdecl.}
proc av_helper_packet_unref(pkt: ptr AVPacket) {.importc, cdecl.}
proc av_helper_packet_free(pkt: ptr ptr AVPacket) {.importc, cdecl.}
proc av_helper_close(ctx: ptr ptr AVFormatContext) {.importc, cdecl.}

# ── Monitor source detection ─────────────────────────────────────────

proc findMonitorSource(): string =
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

# ── Audio capture types ──────────────────────────────────────────────

type
  AudioMode* = enum
    amLibav   ## Direct libav capture (fastest, no subprocess)
    amLive    ## ffmpeg/parec subprocess fallback
    amDemo    ## Built-in synthesized waveforms

  AudioCapture* = object
    mode*: AudioMode
    # libav state
    fmtCtx: ptr AVFormatContext
    packet: ptr AVPacket
    streamIdx: cint
    # subprocess fallback
    process: Process
    stream: Stream
    # demo state
    phase: float
    demoFreqL*, demoFreqR*: float
    demoPreset*: int

# ── Start / stop ─────────────────────────────────────────────────────

proc startAudio*(): AudioCapture =
  let monitor = findMonitorSource()
  if monitor.len > 0:
    # Try direct libav first (dlopen at runtime, no dev packages needed)
    block libav:
      if av_helper_init() < 0: break libav
      var ctx: ptr AVFormatContext = nil
      if av_helper_open_pulse(addr ctx, monitor.cstring) < 0: break libav
      if av_helper_find_stream_info(ctx) < 0:
        av_helper_close(addr ctx)
        break libav
      let idx = av_helper_find_audio_stream(ctx)
      let pkt = av_helper_packet_alloc()
      if pkt != nil:
        return AudioCapture(
          mode: amLibav, fmtCtx: ctx, packet: pkt,
          streamIdx: idx.cint,
          demoFreqL: 440.0, demoFreqR: 330.0)
      av_helper_close(addr ctx)

    # Fallback: ffmpeg subprocess
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

  # Fallback: demo
  AudioCapture(mode: amDemo, demoFreqL: 440.0, demoFreqR: 330.0)

proc stop*(cap: var AudioCapture) =
  case cap.mode
  of amLibav:
    if cap.packet != nil:
      av_helper_packet_free(addr cap.packet)
    if cap.fmtCtx != nil:
      av_helper_close(addr cap.fmtCtx)
  of amLive:
    cap.process.terminate()
    cap.process.close()
  of amDemo:
    discard

proc sourceLabel*(cap: AudioCapture): string =
  case cap.mode
  of amLibav: "LIVE"
  of amLive:  "LIVE"
  of amDemo:  "DEMO"

# ── Preset cycling ───────────────────────────────────────────────────

proc cyclePreset*(cap: var AudioCapture) =
  if cap.mode != amDemo: return
  cap.demoPreset = (cap.demoPreset + 1) mod 4
  case cap.demoPreset
  of 0: cap.demoFreqL = 440.0; cap.demoFreqR = 330.0   # 4:3
  of 1: cap.demoFreqL = 440.0; cap.demoFreqR = 440.0   # 1:1
  of 2: cap.demoFreqL = 440.0; cap.demoFreqR = 220.0   # 2:1
  of 3: cap.demoFreqL = 440.0; cap.demoFreqR = 293.3   # 3:2
  else: discard

# ── Sample reading ───────────────────────────────────────────────────

proc readSamples*(cap: var AudioCapture, scope: var Scope) =
  case cap.mode
  of amLibav:
    # Read frames directly from libav — no subprocess, no pipe
    const frameSize = 4  # 2ch × 16-bit
    var totalSamples = 0
    while totalSamples < scope.samplesL.len:
      let ret = av_helper_read_frame(cap.fmtCtx, cap.packet)
      if ret < 0: break
      if av_helper_packet_stream(cap.packet) == cap.streamIdx:
        let data = av_helper_packet_data(cap.packet)
        let size = av_helper_packet_size(cap.packet)
        let frames = size div frameSize
        for i in 0..<frames:
          if totalSamples >= scope.samplesL.len: break
          let off = i * frameSize
          let left = cast[int16]((data[off + 1].uint16 shl 8) or data[off].uint16)
          let right = cast[int16]((data[off + 3].uint16 shl 8) or data[off + 2].uint16)
          scope.samplesL[totalSamples] = left.float / 32768.0
          scope.samplesR[totalSamples] = right.float / 32768.0
          totalSamples += 1
      av_helper_packet_unref(cap.packet)
      if totalSamples > 0: break  # got some data, render it
    scope.sampleCount = totalSamples

  of amLive:
    const frameSize = 4
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
