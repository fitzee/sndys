# sndys — Audio Analysis Toolkit

44 commands in a single binary. Pure Modula-2, built with [mx](https://github.com/fitzee/mx).

## Build

```bash
cd sndys
mx build
```

Binary: `.mx/bin/sndys`

## Commands

```
Notes:
  Most commands expect mono PCM WAV input (8/16/24/32-bit).
  Stereo files are auto-converted to mono on read.
  Use 'convert' for MP3/OGG/FLAC/AAC (requires ffmpeg).

Core Analysis:
  info        <file.wav>                      WAV metadata (scalar)
  stats       <file.wav>                      RMS, peak, crest factor, DC offset (scalar)
  features    <file.wav>                      34 spectral/temporal/MFCC/chroma features (CSV)
  midstats    <file.wav>                      Per-feature mean+std over mid-term windows (CSV)
  spectrum    <file.wav>                      Top 20 FFT magnitude bins (list)
  spectrogram <file.wav>                      Time-frequency magnitude spectrogram (CSV)
  chromagram  <file.wav>                      12-pitch-class energy over time (CSV)
  flatness    <file.wav>                      Spectral flatness per frame (CSV)
  silence     <file.wav> [thresh] [min_dur]   Non-silent segment boundaries (list)
  compare     <file1.wav> <file2.wav>         Feature-vector distance (scalar)
  analyze     <file.wav>                      Full composite analysis report

Rhythm / Pitch / Harmony:
  beats       <file.wav>                      Estimated BPM and confidence (scalar)
  tempocurve  <file.wav> [win] [hop]          BPM over sliding windows (CSV)
  stability   <file.wav>                      Tempo stability: std/mean of BPM curve (scalar)
  onsets      <file.wav> [sensitivity]        Onset times via spectral flux peaks (list)
  pitch       <file.wav>                      F0 contour via autocorrelation (CSV)
  harmonic    <file.wav>                      Harmonic ratio + F0 per frame (CSV)
  key         <file.wav>                      Musical key via Krumhansl-Schmuckler (scalar)
  chords      <file.wav>                      Chord sequence from chroma templates (list)
  notes       <file.wav>                      Note events: onset + pitch -> MIDI (list)
  tonnetz     <file.wav>                      6-dim tonal centroid per frame (CSV)
  thumbnail   <in> <out> [duration_sec]       Extract most self-similar segment (WAV)

Vocal / Speech:
  voice       <file.wav>                      Formants, jitter, shimmer, HNR (scalar)
                                              [speech/vocal input expected]
  diarize     <file.wav> [num_speakers]       Speaker segmentation via K-means (list)
                                              [speech input expected; auto 2-8 speakers]

Classification:
  train       <dir1> <dir2> [...] -o <model>  Train k-NN classifier from directories
  predict     <model> <file.wav>              Classify file against trained model (scalar)
  segment     <model> <file.wav> [--hmm]      Model-based frame segmentation (list)

Processing:
  trim        <in> <out> <start> <end>        Extract time region in seconds (WAV)
  concat      <a.wav> <b.wav> <out> [xfade]   Concatenate with optional crossfade (WAV)
  mix         <a.wav> <b.wav> <out> [ratio]   Mix two files; ratio 0=A, 1=B (WAV)
  normalize   <in> <out> [peak]               Peak normalization to target (WAV)
  fade        <in> <out> <in_sec> <out_sec>   Linear fade-in/fade-out (WAV)
  reverse     <in> <out>                      Time-reverse signal (WAV)
  mono        <in> <out>                      Stereo to mono downmix (WAV)
  downsample  <in> <out> <rate>               Lanczos resample to target rate (WAV)
  lowpass     <in> <out> <freq_hz>            4th-order Butterworth low-pass (WAV)
  highpass    <in> <out> <freq_hz>            4th-order Butterworth high-pass (WAV)
  bandpass    <in> <out> <lo_hz> <hi_hz>      4th-order Butterworth band-pass (WAV)

Playback / Generation:
  play        <file.wav>                      SDL2 queued playback (any key to stop)
  generate    sine  <out> <freq> <dur> [amp]  Sine tone (WAV)
  generate    chirp <out> <start> <end> <dur> Linear frequency sweep (WAV)
  generate    noise <out> <dur> [amp]         White noise (WAV)
  generate    click <out> <bpm> <dur>         Metronome click track (WAV)

Utilities:
  waveform    <file.wav>                      ASCII waveform to terminal
  convert     <input> <output.wav> [rate]     Convert via ffmpeg to PCM WAV
  batch       <command> <dir>                 Run command on all WAVs in directory
  version                                     Show version
```

## Examples

### Full analysis of a file

```
$ sndys analyze samples/celtic.wav
=== samples/celtic.wav ===

Format:     48000 Hz, 2 ch, 24-bit
Duration:   142.00s (6816000 samples)

RMS:        -16.06 dBFS
Peak:       -0.06 dBFS
Crest:      15.99 dB
DC offset:  -0.000032
Clipping:   1 samples

Key:        A# minor (0.67)
BPM:        85.7 (7% confidence)
Activity:   14 non-silent segments
```

### Batch processing

```
$ sndys batch key samples/
--- file_example_WAV_1MG.wav ---
  Key: E minor  (0.79)
--- file_example_WAV_5MG.wav ---
  Key: C major  (0.89)
--- dance_sample1.wav ---
  Key: A# minor (0.77)
--- celtic.wav ---
  Key: A# minor (0.67)
Processed 5 files
```

### BPM detection

```
$ sndys beats samples/dance_sample1.wav
Analyzing: samples/dance_sample1.wav
  Duration: ~205s (48000 Hz)
  BPM: 119.9
  Confidence: 7%
```

### Chord recognition

```
$ sndys chords samples/file_example_WAV_1MG.wav
Chord sequence (123 segments):
  G#  (0.56)
  Cm  (0.58)
  Fm7  (0.71)
  ...
```

### Note transcription

```
$ sndys notes samples/file_example_WAV_1MG.wav
Notes: 73
  Start     End      Note   MIDI  Hz
  0.004s  0.124s  C#4     61   276.7
  0.124s  0.144s  F4     65   350.0
  0.144s  0.254s  F#4     66   377.9
  ...
```

### Voice analysis

```
$ sndys voice samples/file_example_WAV_1MG.wav
Voice analysis: samples/file_example_WAV_1MG.wav

  Formants (first frame):
    F1: 258.3 Hz
    F2: 11886.3 Hz
    F3: 15977.6 Hz

  HNR: -0.29 dB
  Jitter: 6.29%
  Shimmer: 25.66%
```

### Audio processing

```
$ sndys lowpass samples/celtic.wav samples/out/lowpass.wav 500
Lowpass 500.0Hz -> samples/out/lowpass.wav

$ sndys downsample samples/dance_sample1.wav samples/out/dance_8k.wav 8000
Input:  48000 Hz, 2 ch, 24-bit, 9865650 samples
Output: 8000 Hz, 1 ch, 16-bit, 1644275 samples

$ sndys thumbnail samples/celtic.wav samples/out/thumb.wav 10
Thumbnail: 121.55s - 131.52s (score: 0.9975)
Wrote samples/out/thumb.wav
```

### Signal generation

```
$ sndys generate sine tone.wav 440 2
440.0Hz sine, 2.0s -> tone.wav

$ sndys generate click metro.wav 120 5
120.0 BPM click track -> metro.wav
```

### ASCII waveform

```
$ sndys waveform samples/celtic.wav
                                            |       |      |   ||
                            |            |  |  |||| ||| ||||||||||           |
                            |          |||| ||||||||||||||||||||||  | |   | ||
                            ||  | || |||||| ||||||||||||||||||||||||| ||||||||
                            ||||||||||||||||||||||||||||||||||||||||| ||||||||
                   |    | ||||||||||||||||||||||||||||||||||||||||||||||||||||
                   |   |||||||||||||||||||||||||||||||||||||||||||||||||||||||
   ||| |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
================================================================================
|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
  |||  |||||||| ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
                 | |   |||||||||||||||||||||||||||||||||||||||||||||||||||||||
                       |||||||||||||||||||||||||||||||||||||||||||||||||||||||
                            ||||||||||||||||||||||||||||||||||||||||||||||||||
                            |   | ||  |  ||||||||||||||||||||||||||| ||||||  |
                            |      |  |  |  ||||||||||||||||||||||   |  |||  |
                            |                  |||| ||  ||||||| |         |  |
                                                           |
```

### Train and classify

```
$ sndys train music/ speech/ -o model.bin
Training classifier (2 classes, k=5)
  Found 10 WAV files across 2 classes
  ...
Model saved: model.bin

$ sndys predict model.bin unknown.wav
Predicted class: 0
  Class 0: 0.9999  <--
  Class 1: 0.0000

$ sndys segment model.bin recording.wav --hmm
Segments: 5
    0  0.00s - 45.20s  class 0
    1  45.20s - 180.50s  class 1
    ...
```

## Format Support

- **WAV**: 8, 16, 24, 32-bit PCM (including WAVE_FORMAT_EXTENSIBLE)
- **MP3, OGG, FLAC, AAC**: via ffmpeg bridge (`sndys convert`)

## Feature Extraction

34 short-term features per frame, validated against pyAudioAnalysis v0.3.14:

| Features | Correlation with pyAudioAnalysis |
|----------|--------------------------------|
| ZCR, Energy, Energy Entropy | r = 1.0000 |
| Spectral Centroid, Spread, Entropy, Flux, Rolloff | r = 1.0000 |
| MFCCs 1-13 | r = 1.0000 |
| Chroma 1-12 + Std | r = 0.52-0.99 |

Two extraction modes: `Extract` (exact pyAudioAnalysis match, direct DFT) and `ExtractFast` (radix-2 FFT, ~100x faster on long files).

## Performance

On Apple Silicon (mx transpiles to C, compiled with `cc -O2`):

| Operation | File | Time |
|-----------|------|------|
| `beats` | 3.4 min 48kHz stereo 24-bit | 5.7s |
| `downsample` 48k→8k | 3.4 min stereo | 0.6s |
| `features` | 6s 44kHz stereo 16-bit | 0.2s |
| `batch beats` | 5 WAV files | 10s |

## Libraries

All 12 libraries can be used independently — each has its own `m2.toml`, `.def`/`.mod` sources, tests, and [API docs](../docs/libs/).

| Library | Modules |
|---------|---------|
| **m2wav** | Wav |
| **m2math** | MathUtil |
| **m2fft** | FFT |
| **m2dct** | DCT |
| **m2stats** | Stats |
| **m2audio** | AudioIO, ShortFeats, MidFeats, Beat, Classify, Segment, Delta, Harmonic, Spectro, Thumbnail, KeyDetect, Onset, AudioProc, AudioConcat, Filter, PitchTrack, TempoCurve, AudioStats, Waveform, Convert, SpectralExtra, VoiceFeats, Chords, NoteTranscribe, Tonnetz, Rhythm |
| **m2knn** | Scaler, KNN, Evaluate, SMOTE, Regress |
| **m2hmm** | HMM |
| **m2kmeans** | KMeans |
| **m2pca** | PCA, LDA |
| **m2tree** | DTree, Forest, GBoost |
| **m2svm** | SVM |
