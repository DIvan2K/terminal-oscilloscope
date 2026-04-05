# terminal-oscilloscope

A terminal-based oscilloscope with CRT phosphor physics, written in Nim using [illwill](https://github.com/johnnovak/illwill).

![demo](demo.gif)

## Features

- **CRT boot/shutdown animations** — phosphor ramp, beam sweep, vertical collapse, dot fade
- **Y-T and X-Y modes** — time-domain waveform or Lissajous figures
- **Phosphor persistence** — beam bloom, decay trails, intensity-based shading
- **Half-block rendering** — 2x vertical resolution using Unicode `▀▄█` characters
- **Live audio capture** — direct libav bindings via dlopen, zero dependencies

## Install

Requires [Nim](https://nim-lang.org/) 2.x.

```bash
git clone https://github.com/rolandnsharp/terminal-oscilloscope.git
cd terminal-oscilloscope
nimble build
./osc
```

## Controls

| Key | Action |
|-----|--------|
| `m` | Toggle Y-T / X-Y mode |
| `+` / `-` | Increase / decrease gain (amplitude) |
| `]` / `[` | Zoom in / out time axis |
| `q` | Quit (with CRT shutdown effect) |

## Audio

Captures system audio by opening the PulseAudio/PipeWire monitor of your default output sink directly via libavformat and libavdevice. Libraries are loaded at runtime with `dlopen` — no dev packages, no subprocess, no extra dependencies.

## Credits

CRT turn-on/off animations inspired by [AetherTune](https://github.com/nevermore23274/AetherTune).
