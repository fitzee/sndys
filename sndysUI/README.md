# sndysUI

Desktop audio analysis front-end for the sndys toolbox. Built in pure Modula-2 with [m2gfx](https://github.com/fitzee/mx) (SDL2) for rendering and the full m2audio/m2wav DSP stack for analysis.

## Build

```bash
cd sndysUI
mx build
```

Requires SDL2 and SDL2_ttf (`brew install sdl2 sdl2_ttf` on macOS).

## Run

```bash
.mx/bin/sndysUI samples/celtic.wav
```

Or launch without arguments and use the toolbar.

## Features

- **Waveform display** with click-drag selection
- **Audio playback** via SDL2 queued output (Space to play/stop)
- **Overview tab**: file info, RMS/peak/crest, key detection, BPM estimation
- **Spectrum tab**: magnitude spectrogram and chromagram heatmaps
- **Tempo tab**: BPM, beat strength, onset detection
- **Harmonic tab**: pitch contour, chord sequence, note transcription, voice features (formants, jitter, shimmer, HNR)
- **Features tab**: all 34 short-term features for the first frame

## Controls

| Key/Action | Effect |
|-----------|--------|
| Space | Play / Stop audio |
| Tab | Cycle through analysis tabs |
| Escape | Quit |
| Click-drag on waveform | Set selection range |
| [Analyze] button | Run all analyses on selection (or whole file) |
| [Clear Sel] button | Clear selection, analyze whole file |

## Architecture

```
sndysUI/
  m2.toml           Build config (deps: m2gfx, m2audio, m2wav, etc.)
  src/
    Main.mod         Event loop, layout, tab rendering, playback control
    AppState.def/mod Global state: loaded audio, selection, cached results
    UI.def/mod       Theme, fonts, drawing primitives (buttons, tabs, labels)
    WaveView.def/mod Waveform, spectrogram, chromagram, pitch contour rendering
```

**Rendering**: Immediate-mode — every frame redraws the entire UI using m2gfx Canvas and Font primitives. Dark theme with accent colors for interactive elements.

**Analysis**: All DSP runs synchronously through the existing m2audio modules. Results are cached in AppState and invalidated when the file or selection changes.

**Playback**: Uses the Playback module (SDL2 queued audio) with streaming chunks for responsive stop.

**Selection**: Click-drag on the waveform sets a sample range. All analyses operate on the selection if present, or the whole file otherwise.
