## Audio capture via libavdevice/libavformat using Nim's dynlib pragma.
## Libraries are loaded at runtime — no dev packages, no C helper file.

import osproc, strutils
import scope

# ── libav dynlib bindings ────────────────────────────────────────────

const
  avformat = "libavformat.so(|.61|.60|.59)"
  avdevice = "libavdevice.so(|.61|.60|.59)"
  avcodec  = "libavcodec.so(|.61|.60|.59)"

type
  AVFormatContext = object  # opaque
  AVInputFormat = object    # opaque

  # AVPacket layout — must match FFmpeg 5.x/6.x/7.x:
  # buf(8), pts(8), dts(8), data(8), size(4), stream_index(4)
  AVPacket = object
    buf: pointer
    pts: int64
    dts: int64
    data: ptr UncheckedArray[uint8]
    size: cint
    stream_index: cint

const AVMEDIA_TYPE_AUDIO = 1.cint

proc avdevice_register_all()
    {.importc, dynlib: avdevice, cdecl.}
proc av_find_input_format(name: cstring): ptr AVInputFormat
    {.importc, dynlib: avformat, cdecl.}
proc avformat_open_input(ctx: ptr ptr AVFormatContext, url: cstring,
    fmt: ptr AVInputFormat, options: pointer): cint
    {.importc, dynlib: avformat, cdecl.}
proc avformat_find_stream_info(ctx: ptr AVFormatContext,
    options: pointer): cint
    {.importc, dynlib: avformat, cdecl.}
proc av_find_best_stream(ctx: ptr AVFormatContext, mediaType: cint,
    wanted: cint, related: cint, codec: pointer, flags: cint): cint
    {.importc, dynlib: avformat, cdecl.}
proc av_read_frame(ctx: ptr AVFormatContext, pkt: ptr AVPacket): cint
    {.importc, dynlib: avformat, cdecl.}
proc avformat_close_input(ctx: ptr ptr AVFormatContext)
    {.importc, dynlib: avformat, cdecl.}
proc av_packet_alloc(): ptr AVPacket
    {.importc, dynlib: avcodec, cdecl.}
proc av_packet_unref(pkt: ptr AVPacket)
    {.importc, dynlib: avcodec, cdecl.}
proc av_packet_free(pkt: ptr ptr AVPacket)
    {.importc, dynlib: avcodec, cdecl.}

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

  try:
    avdevice_register_all()
  except: return

  let fmt = av_find_input_format("pulse")
  if fmt == nil: return

  var ctx: ptr AVFormatContext = nil
  if avformat_open_input(addr ctx, monitor.cstring, fmt, nil) < 0: return
  if avformat_find_stream_info(ctx, nil) < 0:
    avformat_close_input(addr ctx)
    return

  let idx = av_find_best_stream(ctx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
  if idx < 0:
    avformat_close_input(addr ctx)
    return

  let pkt = av_packet_alloc()
  if pkt == nil:
    avformat_close_input(addr ctx)
    return

  AudioCapture(fmtCtx: ctx, packet: pkt, streamIdx: idx, live: true)

proc stop*(cap: var AudioCapture) =
  if cap.live:
    if cap.packet != nil: av_packet_free(addr cap.packet)
    if cap.fmtCtx != nil: avformat_close_input(addr cap.fmtCtx)

proc sourceLabel*(cap: AudioCapture): string =
  if cap.live: "LIVE" else: "NO SIGNAL"

proc readSamples*(cap: var AudioCapture, scope: var Scope) =
  if not cap.live: return

  const frameSize = 4  # 2ch × 16-bit

  let ret = av_read_frame(cap.fmtCtx, cap.packet)
  if ret < 0:
    scope.sampleCount = 0
    return

  if cap.packet.stream_index != cap.streamIdx:
    av_packet_unref(cap.packet)
    scope.sampleCount = 0
    return

  let data = cap.packet.data
  let frames = min(cap.packet.size div frameSize, scope.samplesL.len.cint)

  for i in 0..<frames:
    let off = i * frameSize
    let left = cast[int16]((data[off + 1].uint16 shl 8) or data[off].uint16)
    let right = cast[int16]((data[off + 3].uint16 shl 8) or data[off + 2].uint16)
    scope.samplesL[i] = left.float / 32768.0
    scope.samplesR[i] = right.float / 32768.0

  scope.sampleCount = frames
  av_packet_unref(cap.packet)
