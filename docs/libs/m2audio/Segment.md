# Segment

The `Segment` module splits an audio signal into labeled time regions. It provides two segmentation strategies: energy-based silence removal (unsupervised) and supervised segmentation using a trained k-NN classifier with optional HMM temporal smoothing. Output is a list of segment boundaries (start and end times in seconds) with an integer label for each segment.

## Why Segment?

Raw audio is a continuous stream of samples, but downstream tasks -- transcription, music analysis, speaker diarization -- operate on discrete regions with meaningful boundaries. `Segment` bridges this gap. Silence removal strips away dead air and isolates active regions, which is useful as a preprocessing step for virtually any audio pipeline. Supervised segmentation goes further: given a trained classifier, it labels every frame of audio and then collapses adjacent frames with the same label into contiguous segments. The optional HMM smoothing layer eliminates the isolated misclassifications that inevitably arise from frame-independent classification, producing clean, temporally coherent segment boundaries.

## Constants

### MaxSegments

```modula2
CONST
  MaxSegments = 2048;
```

The maximum number of segments that can be stored in a `SegmentList`. If the audio produces more segments than this limit, additional segments are silently dropped.

## Types

### SegmentList

```modula2
TYPE
  SegmentList = RECORD
    numSegments: CARDINAL;
    starts: ARRAY [0..2047] OF LONGREAL;
    ends:   ARRAY [0..2047] OF LONGREAL;
    labels: ARRAY [0..2047] OF INTEGER;
  END;
```

A list of non-overlapping audio segments. `starts[i]` and `ends[i]` are the start and end times of segment i in seconds. `labels[i]` is the integer class label for that segment. For silence removal, non-silent segments are labeled `1`. For supervised segmentation, labels correspond to the class indices of the k-NN model.

## Silence Removal Algorithm

`RemoveSilence` uses a two-pass energy-thresholding approach with 50ms analysis windows and 25ms step size:

1. **First pass -- find peak energy.** The signal is divided into overlapping frames. For each frame, the mean squared energy is computed. The maximum energy across all frames is recorded.

2. **Compute threshold.** The silence threshold is `energyThreshold * maxEnergy`. A typical value of 0.1 means frames with less than 10% of the peak energy are considered silent.

3. **Second pass -- detect non-silent regions.** The algorithm scans frames sequentially, tracking whether it is currently inside a non-silent segment. When energy rises above the threshold, a new segment begins. When it drops below, the segment ends. Segments shorter than `minDurationSec` are discarded to filter out clicks and transient noise.

4. **Output.** Non-silent segments are written to the `SegmentList` with label `1`.

This approach is simple, fast, and effective for clean recordings. For noisy audio, lowering the threshold (e.g., 0.02) or preprocessing with a noise gate may be necessary.

## Supervised Segmentation Pipeline

`SegmentSupervised` implements a three-stage pipeline that transforms raw audio into labeled segments:

### Stage 1: Feature Extraction

The raw audio signal is processed by `ShortFeats.Extract` using 50ms windows with 25ms step size, producing a matrix of 34 short-term features per frame. These features include zero-crossing rate, energy, spectral centroid, spectral spread, spectral entropy, spectral flux, spectral rolloff, 13 MFCCs, 8 chroma coefficients, and their deltas. The feature matrix has shape `numFrames x 34`.

### Stage 2: Frame-Level Classification (k-NN)

Each frame's 34-dimensional feature vector is classified independently using the provided k-NN model (loaded from a `.bin` file via `KNN.LoadModel`). This produces an array of `numFrames` integer labels -- one predicted class per frame. Because classification is frame-independent, the raw labels may contain rapid oscillations and isolated errors.

### Stage 3: HMM Smoothing (optional)

When `useHMM` is `TRUE`, the module applies temporal smoothing:

1. A `GaussHMM` is initialized with the same number of states as the k-NN model has classes and 34 features.
2. `TrainSupervised` estimates HMM parameters (transition probabilities and per-state Gaussian emissions) directly from the feature matrix and the raw k-NN labels.
3. `Smooth` (Viterbi decoding) re-labels the entire sequence, finding the most likely state sequence given both the acoustic evidence and the learned transition structure.

The HMM penalizes rapid state changes because transitions are learned from the data, where state changes are infrequent relative to the frame rate. This effectively removes isolated misclassifications -- for example, a single "speech" frame in the middle of a "music" region will be corrected to "music".

### Segment Merging

After labeling (raw or smoothed), adjacent frames with the same label are collapsed into contiguous segments. The output `SegmentList` contains one entry per contiguous run, with start/end times computed from the frame indices and the 25ms step size.

## Procedures

### RemoveSilence

```modula2
PROCEDURE RemoveSilence(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                        energyThreshold, minDurationSec: LONGREAL;
                        VAR segments: SegmentList);
```

Detects and removes silent regions from a mono audio signal. `signal` points to `numSamples` LONGREALs (normalized to [-1, 1]). `sampleRate` is the sampling rate in Hz. `energyThreshold` is the fraction of peak frame energy below which a frame is considered silent (typical: 0.1). `minDurationSec` is the minimum duration in seconds for a segment to be kept (typical: 0.2). The `segments` output contains only the non-silent regions, each labeled `1`.

**Example:**

```modula2
VAR
  signal: ADDRESS;
  numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
  segs: SegmentList;

AudioIO.ReadAudio("recording.wav", signal, numSamples, sampleRate, ok);
Segment.RemoveSilence(signal, numSamples, sampleRate,
                      0.1, 0.2, segs);
(* segs contains non-silent regions with times in seconds *)
```

---

### SegmentSupervised

```modula2
PROCEDURE SegmentSupervised(signal: ADDRESS;
                            numSamples, sampleRate: CARDINAL;
                            VAR model: Model;
                            useHMM: BOOLEAN;
                            VAR segments: SegmentList);
```

Segments audio using a trained k-NN classifier with optional HMM smoothing. `signal` points to `numSamples` LONGREALs (mono, normalized). `model` is a trained `KNN.Model` (typically loaded from disk via `KNN.LoadModel`). When `useHMM` is `TRUE`, frame-level predictions are smoothed using Viterbi decoding on a Gaussian HMM trained from the raw predictions. The `segments` output contains contiguous regions of the same label, with boundaries in seconds.

The procedure internally allocates memory for the raw label array (and smoothed label array if HMM is enabled), and frees all allocations before returning. The feature matrix allocated by `ShortFeats.Extract` is also freed.

**Example:**

```modula2
VAR
  signal: ADDRESS;
  numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
  m: KNN.Model;
  segs: SegmentList;

KNN.LoadModel(m, "music_speech.bin", ok);
AudioIO.ReadAudio("podcast.wav", signal, numSamples, sampleRate, ok);

Segment.SegmentSupervised(signal, numSamples, sampleRate,
                          m, TRUE, segs);

(* segs contains labeled segments: e.g., 0=music, 1=speech *)
KNN.FreeModel(m);
AudioIO.FreeSignal(signal);
```

## CLI Usage

The `segment` command-line tool (built from `examples/segment.mod`) exposes both segmentation modes.

### Silence Removal

```
segment silence <file.wav> [threshold] [min_duration]
```

Removes silent regions from a WAV file and prints the non-silent segment boundaries.

```
$ segment silence recording.wav
Silence removal: recording.wav
  Threshold: 0.10  Min duration: 0.20s

  Segments: 3

  #     Start      End   Label
  ---   -----    -----   -----
    0   0.25s - 4.50s   class 1
    1   5.10s - 12.75s   class 1
    2   13.00s - 18.30s   class 1
```

Custom threshold and minimum duration:

```
$ segment silence noisy_recording.wav 0.05 0.3
Silence removal: noisy_recording.wav
  Threshold: 0.05  Min duration: 0.30s

  Segments: 2

  #     Start      End   Label
  ---   -----    -----   -----
    0   0.30s - 8.70s   class 1
    1   9.50s - 20.00s   class 1
```

### Supervised Segmentation

```
segment classify <model.bin> <file.wav> [--hmm]
```

Segments audio using a pre-trained k-NN model. The `--hmm` flag enables Viterbi smoothing.

Without HMM smoothing:

```
$ segment classify music_speech.bin podcast.wav
Supervised segmentation: podcast.wav
  Model: music_speech.bin
  HMM smoothing: disabled

  Segments: 47

  #     Start      End   Label
  ---   -----    -----   -----
    0   0.00s - 3.25s   class 0
    1   3.25s - 3.50s   class 1
    2   3.50s - 15.75s   class 0
  ...
```

With HMM smoothing (recommended):

```
$ segment classify music_speech.bin podcast.wav --hmm
Supervised segmentation: podcast.wav
  Model: music_speech.bin
  HMM smoothing: enabled

  Segments: 5

  #     Start      End   Label
  ---   -----    -----   -----
    0   0.00s - 15.75s   class 0
    1   15.75s - 45.50s   class 1
    2   45.50s - 60.25s   class 0
    3   60.25s - 120.00s   class 1
    4   120.00s - 135.50s   class 0
```

Notice that HMM smoothing reduces the segment count dramatically by eliminating spurious short segments, producing the clean boundaries expected for a music/speech segmentation task.

## Example

A complete program that loads audio, performs silence removal, then runs supervised segmentation with HMM smoothing on the non-silent portions.

```modula2
MODULE SegmentDemo;

FROM SYSTEM IMPORT ADR;
FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM Segment IMPORT SegmentList, RemoveSilence, SegmentSupervised;
FROM KNN IMPORT Model;
IMPORT KNN;

VAR
  signal: ADDRESS;
  numSamples, sampleRate, i: CARDINAL;
  ok: BOOLEAN;
  silenceSegs, classSegs: SegmentList;
  m: Model;

BEGIN
  (* Read audio *)
  ReadAudio("podcast.wav", signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read audio file"); WriteLn;
    HALT
  END;

  (* Step 1: Remove silence *)
  RemoveSilence(signal, numSamples, sampleRate,
                0.1, 0.2, silenceSegs);

  WriteString("=== Silence Removal ==="); WriteLn;
  WriteString("Non-silent segments: ");
  WriteCard(silenceSegs.numSegments, 0); WriteLn;
  FOR i := 0 TO silenceSegs.numSegments - 1 DO
    WriteString("  Segment "); WriteCard(i, 0);
    WriteString(": active audio region"); WriteLn
  END;
  WriteLn;

  (* Step 2: Supervised segmentation with HMM smoothing *)
  KNN.LoadModel(m, "music_speech.bin", ok);
  IF NOT ok THEN
    WriteString("Error: could not load model"); WriteLn;
    FreeSignal(signal);
    HALT
  END;

  SegmentSupervised(signal, numSamples, sampleRate,
                    m, TRUE, classSegs);

  WriteString("=== Supervised Segmentation (HMM) ==="); WriteLn;
  WriteString("Segments found: ");
  WriteCard(classSegs.numSegments, 0); WriteLn;
  FOR i := 0 TO classSegs.numSegments - 1 DO
    WriteString("  Segment "); WriteCard(i, 0);
    WriteString(": class "); WriteInt(classSegs.labels[i], 0);
    WriteLn
  END;

  (* Cleanup *)
  KNN.FreeModel(m);
  FreeSignal(signal)
END SegmentDemo.
```
