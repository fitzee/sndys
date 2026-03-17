# sndys — Audio Analysis Toolkit

43 commands in a 156 KB binary. Pure Modula-2, built with [mx](https://github.com/fitzee/mx).

## Build

```bash
cd sndys
mx build
```

Binary: `.mx/bin/sndys`

## Commands

```
Info:
  info        <file.wav>                      File metadata
  spectrum    <file.wav>                      Top 20 FFT bins
  spectrogram <file.wav>                      Spectrogram (CSV)
  chromagram  <file.wav>                      Chromagram (CSV)

Analysis:
  features    <file.wav>                      34 features per frame (CSV)
  midstats    <file.wav>                      Per-feature mean/std summary
  beats       <file.wav>                      Estimate BPM
  tempocurve  <file.wav> [win] [hop]          BPM over time
  key         <file.wav>                      Detect musical key
  pitch       <file.wav>                      Pitch (F0) contour (CSV)
  harmonic    <file.wav>                      Harmonic ratio + F0 (CSV)
  onsets      <file.wav> [sensitivity]        Note onset times
  silence     <file.wav> [thresh] [min_dur]   Non-silent regions
  compare     <file1.wav> <file2.wav>         Similarity score
  thumbnail   <in> <out> [duration_sec]       Most representative segment
  analyze     <file.wav>                      Full analysis report

Classification:
  train       <dir1> <dir2> [...] -o <model>  Train k-NN classifier
  predict     <model> <file.wav>              Classify a file
  segment     <model> <file.wav> [--hmm]      Segment by class
  diarize     <file.wav> [num_speakers]       Speaker diarization

Processing:
  trim        <in> <out> <start> <end>        Extract time region
  concat      <a.wav> <b.wav> <out> [xfade]   Join files with crossfade
  mix         <a.wav> <b.wav> <out> [ratio]   Mix two files
  normalize   <in> <out> [peak]               Peak normalization
  fade        <in> <out> <in_sec> <out_sec>   Apply fades
  reverse     <in> <out>                      Reverse audio
  mono        <in> <out>                      Stereo to mono
  downsample  <in> <out> <rate>               Resample (Lanczos)
  lowpass     <in> <out> <freq_hz>            Butterworth low-pass
  highpass    <in> <out> <freq_hz>            Butterworth high-pass
  bandpass    <in> <out> <lo_hz> <hi_hz>      Butterworth band-pass

Generation:
  generate    sine  <out> <freq> <dur> [amp]  Sine tone
  generate    chirp <out> <start> <end> <dur> Frequency sweep
  generate    noise <out> <dur> [amp]         White noise
  generate    click <out> <bpm> <dur>         Click track

Music Intelligence:
  chords      <file.wav>                      Chord sequence
  notes       <file.wav>                      Note transcription
  tonnetz     <file.wav>                      Tonal centroid (CSV)
  voice       <file.wav>                      Formants, jitter, shimmer, HNR
  flatness    <file.wav>                      Spectral flatness (CSV)
  stability   <file.wav>                      Tempo stability score

Utilities:
  stats       <file.wav>                      RMS, peak, crest factor, DC
  waveform    <file.wav>                      ASCII waveform display
  convert     <input> <output.wav> [rate]     Convert via ffmpeg
  batch       <command> <directory>            Run on all WAVs in dir
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
