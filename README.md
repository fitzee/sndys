# sndys

An audio analysis toolkit written in PIM4 Modula-2, compiled to native code via the [mx](https://github.com/fitzee/mx) transpiler (Modula-2 → C → native binary). Includes 12 libraries, a 44-command CLI, and a native macOS SwiftUI app — all sharing the same analysis backend.

<p align="center">
  <img src="images/sshot1.png" width="24%" />
  <img src="images/sshot2.png" width="24%" />
  <img src="images/sshot3.png" width="24%" />
  <img src="images/sshot4.png" width="24%" />
</p>

## Overview

A port of [pyAudioAnalysis](https://github.com/tyiannak/pyAudioAnalysis) — audio feature extraction, classification, and segmentation — to PIM4 Modula-2. No Python runtime, no numpy, no scikit-learn. All computation is in Modula-2 compiled to C.

## Why Modula-2?

- **Clean module interfaces.** `.def` / `.mod` separation maps well to library boundaries.
- **Explicit memory management.** No hidden allocations, deterministic ownership.
- **C-compatible output.** `mx` produces standard `.o` files and `.a` static libraries with exported C symbols. Links into any C-compatible toolchain (CLI, Swift app, test harness) without reimplementation.
- **Single codebase, multiple front-ends.** The same object files power the CLI and the macOS app.

## Libraries

12 independent mx libraries, each with definition modules, implementations, tests, and docs:

| Library | What it does |
|---------|-------------|
| [**m2wav**](m2wav/) | WAV read/write (8/16/24/32-bit PCM), stereo-to-mono, Lanczos downsampling |
| [**m2math**](m2math/) | Extended math — Log, Pow, Floor, Ceil, Hypot, NextPow2 |
| [**m2fft**](m2fft/) | Radix-2 Cooley-Tukey FFT |
| [**m2dct**](m2dct/) | DCT-II/III for MFCC computation |
| [**m2stats**](m2stats/) | Mean, StdDev, Entropy, Normalize, DotProduct |
| [**m2audio**](m2audio/) | 27 modules: feature extraction, beat detection, key detection, chord recognition, note transcription, onset detection, pitch tracking, spectrograms, filtering, classification, segmentation, playback, and more |
| [**m2knn**](m2knn/) | k-NN classifier/regressor, StandardScaler, SMOTE, cross-validation |
| [**m2hmm**](m2hmm/) | Gaussian HMM — Viterbi decoding, supervised training, forward algorithm |
| [**m2kmeans**](m2kmeans/) | K-means clustering with silhouette scoring |
| [**m2pca**](m2pca/) | PCA and LDA via power iteration |
| [**m2tree**](m2tree/) | Decision trees, Random Forest, Extra Trees, Gradient Boosting |
| [**m2svm**](m2svm/) | SVM with linear/RBF kernels (simplified SMO, multi-class OVR) |

## CLI

A unified audio analysis toolbox built on all 12 libraries.

**44 commands across 8 categories** — analysis, classification, processing, playback, generation, music intelligence, and more.

**[Full documentation and command reference →](sndys/README.md)**

```
$ sndys analyze samples/celtic.wav
=== samples/celtic.wav ===

Format:     48000 Hz, 2 ch, 24-bit
Duration:   142.00s (6816000 samples)

RMS:        -16.06 dBFS
Peak:       -0.06 dBFS
Crest:      15.99 dB
Key:        A# minor (0.67)
BPM:        85.7 (7% confidence)
Activity:   14 non-silent segments
```

## macOS App

A SwiftUI desktop application that wraps the Modula-2 analysis libraries through a C bridge. All analysis calls go through the same M2 code the CLI uses.

**[Build and run instructions →](sndysApp/README.md)**

Features:
- NavigationSplitView with sidebar (Overview, Spectrum, Tempo, Harmonic, Features)
- Core Graphics waveform with click-to-seek and live playback cursor
- Spectrogram and chromagram heatmaps via CGImage
- Async analysis on background threads with progress indicators
- AVAudioPlayer playback with play/pause toggle
- Native file picker, dark mode, Retina support via SwiftUI
- SF Symbols throughout

Architecture:
```
SwiftUI Views → SndysBridge.swift → sndys_bridge.c → bridge_all.c (mx --emit-c) → M2 libraries
```

The bridge exposes 20 C functions wrapping the M2 analysis calls. `mx --emit-c` transpiles all 27 M2 modules into a single C file; the bridge appends wrapper functions in the same translation unit (calling the `static` M2 functions directly). `clang` compiles everything into `libsndys.a`. Swift links against it via a bridging header.

## Build

### CLI

Requires [mx](https://github.com/fitzee/mx).

```bash
cd sndys
mx build
```

### macOS App

Requires mx, Xcode command line tools, and SDL2 (`brew install sdl2`).

```bash
cd sndysApp
make
open ./build/sndysApp
```

## Validation

Feature extraction validated against pyAudioAnalysis v0.3.14 on real audio files. 21 of 34 features match at r=1.0000 correlation with <0.3% error. The remaining 13 (chroma features) show consistent scale offsets due to a numpy advanced-indexing difference in the reference implementation.

Beat detection tested against files with known BPM — within 5% of ground truth on all tested tracks.

## Release Notes

See **[RELEASE_NOTES.md](RELEASE_NOTES.md)** for the defect audit breakdown — 100+ fixes across pointer arithmetic, memory management, bounds safety, division guards, and numerical stability.

## API Documentation

Per-module docs are in [`docs/libs/`](docs/libs/) — covering every procedure in every library.

## Project Structure

```
sndys/
  sndys/                  CLI tool (44 commands)
  sndysApp/               Native macOS SwiftUI app
    Sources/              Swift views + bridge wrappers
    Bridge/               C bridge, build script, libsndys.a
  m2wav/                  WAV I/O
  m2math/                 Extended math
  m2fft/                  FFT
  m2dct/                  DCT
  m2stats/                Statistics
  m2audio/                Audio analysis (27 modules)
  m2knn/                  k-NN + evaluation
  m2hmm/                  Hidden Markov Model
  m2kmeans/               K-means clustering
  m2pca/                  PCA + LDA
  m2tree/                 Decision trees + ensembles
  m2svm/                  Support Vector Machine
  docs/libs/              API documentation
  examples/               Standalone example programs
```
