## Audio capture via libavdevice/libavformat (dlopen at runtime).

import osproc, strutils
import scope

# ── libav C helper bindings ──────────────────────────────────────────

{.compile: "avhelper.c".}
{.passL: "-ldl".}

type
  AVFormatContext = object
  AVPacket = object

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

# ── Audio capture ────────────────────────────────────────────────────

type
  AudioCapture* = object
    fmtCtx: ptr AVFormatContext
    packet: ptr AVPacket
    streamIdx: cint
    live*: bool

proc startAudio*(): AudioCapture =
  let monitor = findMonitorSource()
  if monitor.len == 0: return

  if av_helper_init() < 0: return

  var ctx: ptr AVFormatContext = nil
  if av_helper_open_pulse(addr ctx, monitor.cstring) < 0: return
  if av_helper_find_stream_info(ctx) < 0:
    av_helper_close(addr ctx)
    return

  let idx = av_helper_find_audio_stream(ctx)
  let pkt = av_helper_packet_alloc()
  if pkt == nil:
    av_helper_close(addr ctx)
    return

  AudioCapture(fmtCtx: ctx, packet: pkt, streamIdx: idx.cint, live: true)

proc stop*(cap: var AudioCapture) =
  if cap.live:
    if cap.packet != nil: av_helper_packet_free(addr cap.packet)
    if cap.fmtCtx != nil: av_helper_close(addr cap.fmtCtx)

proc sourceLabel*(cap: AudioCapture): string =
  if cap.live: "LIVE" else: "NO SIGNAL"

proc readSamples*(cap: var AudioCapture, scope: var Scope) =
  if not cap.live: return

  const frameSize = 4  # 2ch × 16-bit
  var total = 0
  while total < scope.samplesL.len:
    let ret = av_helper_read_frame(cap.fmtCtx, cap.packet)
    if ret < 0: break
    if av_helper_packet_stream(cap.packet) == cap.streamIdx:
      let data = av_helper_packet_data(cap.packet)
      let size = av_helper_packet_size(cap.packet)
      for i in 0..<(size div frameSize):
        if total >= scope.samplesL.len: break
        let off = i * frameSize
        let left = cast[int16]((data[off + 1].uint16 shl 8) or data[off].uint16)
        let right = cast[int16]((data[off + 3].uint16 shl 8) or data[off + 2].uint16)
        scope.samplesL[total] = left.float / 32768.0
        scope.samplesR[total] = right.float / 32768.0
        total += 1
    av_helper_packet_unref(cap.packet)
    if total > 0: break
  scope.sampleCount = total
