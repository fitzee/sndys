# Spectro

The `Spectro` module computes spectrogram and chromagram representations of audio signals. The spectrogram is a time-frequency matrix (magnitude spectrum per frame), and the chromagram maps frequencies to 12 pitch classes.

## Why Spectro?

Spectrograms are the standard visualization and input representation for audio analysis. Chromagrams reduce spectral information to pitch-class profiles, enabling key detection, chord recognition, and music similarity.

## Procedures

### ComputeSpectrogram

```modula2
PROCEDURE ComputeSpectrogram(signal: ADDRESS;
                              numSamples, sampleRate: CARDINAL;
                              winSizeSec, winStepSec: LONGREAL;
                              VAR output: ADDRESS;
                              VAR numFrames, numBins: CARDINAL);
```

Compute a magnitude spectrogram using radix-2 FFT with zero-padding. Output is `numFrames x numBins` LONGREALs (row-major). `numBins = fftSize / 2`. Caller must free with `FreeSpectro`.

```modula2
ComputeSpectrogram(signal, n, 44100, 0.050, 0.025, spec, nF, nB);
(* nB = 1024 for a 2048-point FFT *)
```

### ComputeChromagram

```modula2
PROCEDURE ComputeChromagram(signal: ADDRESS;
                             numSamples, sampleRate: CARDINAL;
                             winSizeSec, winStepSec: LONGREAL;
                             VAR output: ADDRESS;
                             VAR numFrames: CARDINAL);
```

Compute a chroma representation. Output is `numFrames x 12` LONGREALs (one column per pitch class, A through G#). Caller must free with `FreeSpectro`.

```modula2
ComputeChromagram(signal, n, 44100, 0.050, 0.025, chroma, nF);
(* 12 columns: A, A#, B, C, ..., G# *)
```

### FreeSpectro

```modula2
PROCEDURE FreeSpectro(VAR output: ADDRESS);
```

Deallocate a spectrogram or chromagram matrix.
