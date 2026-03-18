# sndysApp — Native macOS Audio Analysis

Native AppKit front-end for the sndys audio toolkit. Calls into the Modula-2 analysis libraries via a C bridge.

## Build

```bash
cd sndysApp
make
```

Requires: Xcode command line tools, SDL2 (`brew install sdl2`), mx compiler.

## Run

```bash
./build/sndysApp
# or with a file:
./build/sndysApp ../samples/celtic.wav
```

Use **Cmd+O** to open files via native file dialog.

## Architecture

```
sndysApp/
  Makefile               Build orchestration
  Bridge/
    sndys_bridge.h       C API for Swift consumption
    sndys_bridge.c       Wrapper calling M2 functions (compiled into libsndys.a)
    BridgeEntry.mod      Dummy M2 module to force linking all analysis modules
    build_lib.sh         Generates C from M2, compiles to libsndys.a
  Sources/
    main.swift           App entry point
    AppDelegate.swift    Window, menu bar, file open
    MainViewController.swift  Main UI: toolbar, waveform, tabs, analysis
    WaveformView.swift   Core Graphics waveform with click-drag selection
    SpectrogramView.swift  CGImage-based spectrogram heatmap
    SndysBridge.swift    Type-safe Swift wrappers around C bridge
```

### How it works

1. `build_lib.sh` uses `mx --emit-c` to transpile all M2 modules to a single C file
2. The C bridge wrappers are appended (same translation unit, so they can call the `static` M2 functions)
3. Everything compiles to `libsndys.a` — a standard static library
4. `swiftc` links the Swift sources against `libsndys.a` with the bridging header

### What you get vs the SDL2 UI

- **Native fonts** — Core Text rendering, no DPI hacks
- **Native file dialog** — Cmd+O opens NSOpenPanel
- **Real progress indicator** — spinning NSProgressIndicator during analysis
- **Proper async** — analysis runs on background GCD queue, UI stays responsive
- **Native audio playback** — AVAudioPlayer, no SDL2 dependency for playback
- **Dark mode** — automatic via AppKit
- **Retina** — automatic, pixel-perfect
- **Tabbed interface** — native NSTabView
- **Scrollable results** — NSScrollView with selectable text
