# Classify

The `Classify` module connects the m2audio feature extraction pipeline with the m2knn k-Nearest Neighbors classifier to provide end-to-end audio classification. It extracts a fixed-length feature vector per audio file, trains a classifier from labeled directories of WAV files, and predicts the class of unknown files.

## Why Classify?

Audio classification requires multiple steps: reading audio, extracting short-term features, computing mid-term statistics, averaging into a file-level descriptor, normalizing, and running a classifier. `Classify` bundles this entire pipeline into three procedures: `ExtractFileVector` for the feature side, `TrainFromDirs` for batch training, and `PredictFile` for inference.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `VectorLen` | 34 | Features per file (mean of each short-term feature across mid-term windows) |

## Feature Extraction Pipeline

For each WAV file:

1. `AudioIO.ReadAudio` — read WAV, auto stereo-to-mono
2. `ShortFeats.Extract` — 34 features x N frames (50ms window, 25ms step)
3. `MidFeats.Extract` — mean + std per feature over 1-second windows
4. Average the mid-term means across all windows → 34-element vector

This produces one 34-dimensional feature vector per file, suitable for classification.

## Procedures

### ExtractFileVector

```modula2
PROCEDURE ExtractFileVector(path: ARRAY OF CHAR;
                            VAR vec: ARRAY OF LONGREAL;
                            VAR ok: BOOLEAN);
```

Extract a single 34-element feature vector from a WAV file. `vec` must have room for at least `VectorLen` LONGREALs. Returns `FALSE` on read or extraction failure.

```modula2
VAR vec: ARRAY [0..33] OF LONGREAL; ok: BOOLEAN;
ExtractFileVector("music.wav", vec, ok);
(* vec[0] = average ZCR, vec[8] = average MFCC 1, etc. *)
```

### TrainFromDirs

```modula2
PROCEDURE TrainFromDirs(VAR m: Model;
                        dirs: ADDRESS;
                        numDirs: CARDINAL;
                        kNeighbors: CARDINAL;
                        VAR ok: BOOLEAN);
```

Train a k-NN model from labeled directories. `dirs` is an array of `ADDRESS` values, each pointing to a null-terminated directory path string. Each directory is a class (class 0 = first directory, etc.). The procedure scans each directory for `.wav` files, extracts feature vectors, and trains with StandardScaler normalization.

```modula2
VAR
  m: Model;
  dirs: ARRAY [0..1] OF ADDRESS;
  path0: ARRAY [0..63] OF CHAR;
  path1: ARRAY [0..63] OF CHAR;
  ok: BOOLEAN;

path0 := "music/"; path1 := "speech/";
dirs[0] := ADR(path0); dirs[1] := ADR(path1);
TrainFromDirs(m, ADR(dirs), 2, 5, ok);
```

### PredictFile

```modula2
PROCEDURE PredictFile(VAR m: Model;
                      path: ARRAY OF CHAR;
                      VAR proba: ARRAY OF LONGREAL): INTEGER;
```

Classify a single WAV file. Returns the predicted class label (0-based), or -1 on failure. `proba` is filled with per-class probability scores.

```modula2
VAR proba: ARRAY [0..1] OF LONGREAL; pred: INTEGER;
pred := PredictFile(m, "unknown.wav", proba);
(* pred = 0 or 1, proba[0] + proba[1] = 1.0 *)
```

## Example

```
classify train music_dir/ speech_dir/ -o model.bin
classify predict model.bin unknown.wav
```

See `examples/classify.mod` for the full CLI implementation.
