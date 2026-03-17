# ShortFeats

The `ShortFeats` module is the core of the m2audio feature extraction pipeline. It extracts 34 short-term audio features per frame from a mono audio signal, producing a dense feature matrix suitable for classification, segmentation, and similarity tasks. The implementation is aligned with pyAudioAnalysis, achieving r=1.0000 correlation on all 21 non-chroma features and r>0.95 on most chroma features.

## Why ShortFeats?

Audio classification and segmentation algorithms do not operate on raw PCM samples. They need compact, meaningful descriptors -- features -- that capture the timbral, spectral, and harmonic properties of short overlapping windows of audio. `ShortFeats` bundles all 34 standard features from the pyAudioAnalysis library into a single `Extract` call that handles DC normalization, direct DFT computation, and feature calculation internally. You get back a flat matrix ready for statistical analysis or machine learning.

## pyAudioAnalysis Alignment

The implementation matches pyAudioAnalysis's algorithmic choices:

- **DC normalization**: Signal is mean-subtracted and scaled to [-1, 1] before processing
- **No windowing**: Raw frames are passed to the DFT (no Hamming/Hann window), matching pyAudioAnalysis
- **Direct DFT**: Computes exact N-point DFT at window size (not padded radix-2 FFT), avoiding resampling artifacts. `num_fft = window // 2` bins, normalized by `num_fft`
- **Energy entropy / Spectral entropy**: Uses log2 (not ln), matching pyAudioAnalysis
- **Spectral centroid/spread**: Uses Hz-valued frequency bins normalized by max magnitude, then scaled to [0, 1] by dividing by Nyquist frequency
- **Spectral flux**: Sum of squared differences of L1-normalized spectra (no sqrt), with per-element epsilon stabilization
- **MFCC filterbank**: scikits.talkbox design (13 linear + 27 log-spaced triangular filters, lowfreq=133.33 Hz, linc=200/3, logsc=1.0711703)
- **MFCC DCT**: log10 of filterbank energies, orthonormal DCT-II (`norm='ortho'`)
- **Chroma**: Maps FFT bins to pitch classes via `round(12 * log2(freq / 27.50))`, with last-write-wins semantics for duplicate bin assignments

### Validation Results

Tested on two WAV files against pyAudioAnalysis v0.3.14 (236 and 1198 frames):

| Feature Group | Count | Correlation | Error |
|---|---|---|---|
| ZCR, Energy, EnergyEntropy | 3 | r = 1.0000 | < 0.01% |
| Spectral (Centroid, Spread, Entropy, Flux, Rolloff) | 5 | r = 1.0000 | < 0.05% |
| MFCCs 1-13 | 13 | r = 1.0000 | < 0.3% |
| Chroma 1-12 + Std | 13 | r = 0.52-0.99 | Scale differs |

Chroma features show consistent scale offsets due to pyAudioAnalysis's use of numpy advanced indexing side-effects in its chroma bin accumulation, which is not replicated exactly.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `NumFeatures` | 34 | Total number of features extracted per frame |
| `NumMfcc` | 13 | Number of Mel-Frequency Cepstral Coefficients (indices 8-20) |
| `NumChroma` | 12 | Number of chroma bins, one per pitch class (indices 21-32) |

## Types

### FrameResult

```modula2
TYPE FrameResult = RECORD
  features: ARRAY [0..33] OF LONGREAL;
END;
```

A single frame's feature vector. Used internally; the `Extract` procedure returns a flat matrix instead.

## Feature Index

| Index | Name | Description |
|---|---|---|
| 0 | Zero Crossing Rate | Fraction of sign changes per frame |
| 1 | Energy | Mean squared amplitude |
| 2 | Energy Entropy | Entropy of sub-frame energy distribution (log2) |
| 3 | Spectral Centroid | Magnitude-weighted mean frequency, normalized to [0, 1] |
| 4 | Spectral Spread | Magnitude-weighted frequency std dev, normalized to [0, 1] |
| 5 | Spectral Entropy | Entropy of sub-band spectral energy (log2) |
| 6 | Spectral Flux | Frame-to-frame spectral change (sum of squared diffs) |
| 7 | Spectral Rolloff | Frequency below which 90% of energy is concentrated |
| 8-20 | MFCC 1-13 | Mel-Frequency Cepstral Coefficients via scikits.talkbox filterbank |
| 21-32 | Chroma 1-12 | Energy per pitch class (A, A#, B, ..., G#), normalized |
| 33 | Chroma Std Dev | Standard deviation of the 12 chroma values |

## Procedures

### Extract

```modula2
PROCEDURE Extract(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  winSizeSec, winStepSec: LONGREAL;
                  VAR featureMatrix: ADDRESS; VAR numFrames: CARDINAL;
                  VAR ok: BOOLEAN);
```

Extract all 34 short-term features from a mono audio signal. The signal is DC-normalized internally. A direct DFT is computed at the exact window size (no zero-padding) to match pyAudioAnalysis's frequency resolution.

`featureMatrix` is heap-allocated: `numFrames * 34` LONGREALs in row-major order. Row `i`, column `j` is at index `i * 34 + j`. Free with `FreeFeatures`.

```modula2
VAR feats: ADDRESS; nFrames: CARDINAL; ok: BOOLEAN;
Extract(signal, numSamples, 44100, 0.050, 0.025, feats, nFrames, ok);
(* feats[frame * 34 + 0] = ZCR of frame *)
(* feats[frame * 34 + 8] = MFCC 1 of frame *)
```

**Performance**: ~3.5 seconds for a 6-second stereo WAV at 44100 Hz (direct DFT is O(N*K) per frame, where N=window size and K=N/2 bins).

### FreeFeatures

```modula2
PROCEDURE FreeFeatures(VAR featureMatrix: ADDRESS);
```

Deallocate the feature matrix returned by `Extract`.

### FeatureName

```modula2
PROCEDURE FeatureName(idx: CARDINAL; VAR name: ARRAY OF CHAR);
```

Get the human-readable name of the feature at index `idx` (0-33).

```modula2
VAR name: ARRAY [0..31] OF CHAR;
FeatureName(8, name);
(* name = "MFCC 1" *)
```

## Example

```modula2
MODULE FeatureDemo;
FROM InOut IMPORT WriteString, WriteInt, WriteLn;
FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, Extract, FreeFeatures, FeatureName;

TYPE RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

VAR
  signal: ADDRESS;
  numSamples, sampleRate: CARDINAL;
  feats: ADDRESS;
  numFrames: CARDINAL;
  ok: BOOLEAN;
  p: RealPtr;
  name: ARRAY [0..31] OF CHAR;

BEGIN
  ReadAudio("input.wav", signal, numSamples, sampleRate, ok);
  IF NOT ok THEN HALT END;

  Extract(signal, numSamples, sampleRate, 0.050, 0.025,
          feats, numFrames, ok);
  IF NOT ok THEN FreeSignal(signal); HALT END;

  (* Print MFCC 1 for first 5 frames *)
  WriteString("MFCC 1 per frame:"); WriteLn;
  FOR i := 0 TO 4 DO
    p := Elem(feats, i * NumFeatures + 8);
    WriteInt(TRUNC(p^ * 1000), 8); WriteLn
  END;

  FreeFeatures(feats);
  FreeSignal(signal)
END FeatureDemo.
```
