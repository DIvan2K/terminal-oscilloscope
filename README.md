# terminal-oscilloscope

A terminal-based oscilloscope with CRT phosphor physics, written in Nim. Zero dependencies — 200KB binary, just libc.

![demo](demo.gif)

## Features

- **CRT boot/shutdown animations** — phosphor ramp, beam sweep, vertical collapse, dot fade
- **Y-T and X-Y modes** — time-domain waveform or Lissajous figures
- **Phosphor persistence** — beam bloom, decay trails, intensity-based shading
- **Half-block rendering** — 2x vertical resolution using Unicode `▀▄█` characters
- **Live audio capture** — direct libav bindings via dlopen, zero install
- **Threaded audio** — 60fps rendering, audio capture on separate thread
- **6 CRT phosphor palettes** — green, amber, cyan, blue, white, red

## Install

Requires [Nim](https://nim-lang.org/) 2.x.

```bash
git clone https://github.com/rolandnsharp/terminal-oscilloscope.git
cd terminal-oscilloscope
nim c -d:release --threads:on -o:osc src/osc.nim
./osc
```

## Controls

| Key | Action |
|-----|--------|
| `m` | Toggle Y-T / X-Y mode |
| `+` / `-` | Increase / decrease gain (amplitude) |
| `]` / `[` | Zoom in / out time axis |
| `q` | Quit (with CRT shutdown effect) |

## Configuration

Edit the constants at the top of `src/osc.nim`:

```nim
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
```

### Palettes

| Name | Phosphor | Look |
|------|----------|------|
| `green` | P31 | classic oscilloscope |
| `amber` | P12 | warm retro terminal |
| `cyan` | P7 | Tektronix blue-green |
| `blue` | P11 | cool/modern |
| `white` | P4 | TV phosphor |
| `red` | P22-R | radar display |

## Audio

Captures system audio by opening the PulseAudio/PipeWire monitor of your default output sink directly via libavformat and libavdevice. Libraries are loaded at runtime with `dlopen` — no dev packages, no subprocess, no extra dependencies.

## Credits

CRT turn-on/off animations inspired by [AetherTune](https://github.com/nevermore23274/AetherTune).
