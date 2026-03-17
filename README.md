# sndys

An experiment in AI-assisted coding: can Claude write a full audio analysis toolkit in Modula-2 — a language from 1978 — that actually compiles, runs, and produces correct results?

Turns out, yes.

## The Experiment

The goal was to port [pyAudioAnalysis](https://github.com/tyiannak/pyAudioAnalysis) — a Python library for audio feature extraction, classification, and segmentation — to PIM4 Modula-2, compiled with the [mx](https://github.com/fitzee/mx) transpiler (Modula-2 → C → native binary).

No Python. No numpy. No scikit-learn. Just Modula-2 procedures, pointer arithmetic, and `LONGREAL`.

The result is **12 pure Modula-2 libraries** and a **43-command CLI tool** that does real audio analysis — BPM detection, musical key identification, chord recognition, note transcription, spectral analysis, audio classification, HMM-smoothed segmentation, speaker diarization, and more — in a **156 KB binary**.

## Why Modula-2?

Because it's the hardest way to prove the point. If an AI coding agent can produce sound, modular, correct DSP code in a language with no ecosystem, no Stack Overflow answers, and no training data — and have it match the output of a mature Python library frame-by-frame — then the approach works for anything.

Modula-2's module system (`.def` / `.mod` separation) also turned out to be a surprisingly good fit for audio libraries. Clean interfaces, explicit memory management, no hidden allocations.

## What's Here

### Libraries

12 independent mx libraries, each with definition modules, implementations, tests, and docs:

| Library | What it does |
|---------|-------------|
| [**m2wav**](m2wav/) | WAV read/write (8/16/24/32-bit PCM), stereo-to-mono, Lanczos downsampling |
| [**m2math**](m2math/) | Extended math — Log, Pow, Floor, Ceil, Hypot, NextPow2 |
| [**m2fft**](m2fft/) | Radix-2 Cooley-Tukey FFT |
| [**m2dct**](m2dct/) | DCT-II/III for MFCC computation |
| [**m2stats**](m2stats/) | Mean, StdDev, Entropy, Normalize, DotProduct |
| [**m2audio**](m2audio/) | The big one — 26 modules: feature extraction, beat detection, key detection, chord recognition, note transcription, onset detection, pitch tracking, spectrograms, filtering, classification, segmentation, and more |
| [**m2knn**](m2knn/) | k-NN classifier/regressor, StandardScaler, SMOTE, cross-validation |
| [**m2hmm**](m2hmm/) | Gaussian HMM — Viterbi decoding, supervised training, forward algorithm |
| [**m2kmeans**](m2kmeans/) | K-means clustering with silhouette scoring |
| [**m2pca**](m2pca/) | PCA and LDA via power iteration |
| [**m2tree**](m2tree/) | Decision trees, Random Forest, Extra Trees, Gradient Boosting |
| [**m2svm**](m2svm/) | SVM with linear/RBF kernels (simplified SMO, multi-class OVR) |

### sndys — The CLI

The crown jewel: a unified audio analysis toolbox built on all 12 libraries.

**43 commands across 7 categories** — analysis, classification, processing, generation, music intelligence, and more. One binary, 156 KB.

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

## Build

Requires [mx](https://github.com/fitzee/mx).

```bash
cd sndys
mx build
```

## Validation

The feature extraction pipeline was validated against pyAudioAnalysis v0.3.14 on real audio files. 21 of 34 features match at r=1.0000 correlation with <0.3% error. The remaining 13 (chroma features) show consistent scale offsets due to a numpy advanced-indexing quirk in the reference implementation.

Beat detection was tested against files with known BPM — within 5% of ground truth on all tested tracks.

## API Documentation

Per-module docs are in [`docs/libs/`](docs/libs/) — 44 files covering every procedure in every library.

## Project Structure

```
sndys/
  sndys/                  CLI tool (43 commands)
  m2wav/                  WAV I/O
  m2math/                 Extended math
  m2fft/                  FFT
  m2dct/                  DCT
  m2stats/                Statistics
  m2audio/                Audio analysis (26 modules)
  m2knn/                  k-NN + evaluation
  m2hmm/                  Hidden Markov Model
  m2kmeans/               K-means clustering
  m2pca/                  PCA + LDA
  m2tree/                 Decision trees + ensembles
  m2svm/                  Support Vector Machine
  docs/libs/              API documentation
  examples/               Standalone example programs
```
