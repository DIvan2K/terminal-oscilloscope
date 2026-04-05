# terminal-oscilloscope

A terminal-based oscilloscope with CRT phosphor physics, written in Nim using [illwill](https://github.com/johnnovak/illwill).

![demo](demo.gif)

## Features

- **CRT boot/shutdown animations** — phosphor ramp, beam sweep, vertical collapse, dot fade
- **Y-T and X-Y modes** — time-domain waveform or Lissajous figures
- **Phosphor persistence** — beam bloom, decay trails, intensity-based shading
- **Half-block rendering** — 2x vertical resolution using Unicode `▀▄█` characters
- **Live audio capture** — visualises system audio via ffmpeg/PulseAudio monitor
- **Demo mode** — built-in synthesised waveforms when no audio source is available

## Install

Requires [Nim](https://nim-lang.org/) 2.x.

```bash
git clone https://github.com/rolandnsharp/terminal-oscilloscope.git
cd terminal-oscilloscope
nimble build
./crt
```

## Controls

| Key | Action |
|-----|--------|
| `m` | Toggle Y-T / X-Y mode |
| `+` / `-` | Increase / decrease gain (amplitude) |
| `]` / `[` | Zoom in / out time axis |
| `g` | Cycle grid: full → crosshair → off |
| `space` | Freeze display |
| `d` | Cycle demo frequency presets |
| `q` | Quit (with CRT shutdown effect) |

## Audio

Captures system audio automatically using `ffmpeg` with the PulseAudio/PipeWire monitor of your default output sink. Falls back to `parec` if available, or a built-in demo signal.

No extra packages needed — just `ffmpeg` (pre-installed on most Linux systems).

## Credits

CRT turn-on/off animations inspired by [AetherTune](https://github.com/nevermore23274/AetherTune).
