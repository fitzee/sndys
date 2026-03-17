# Beat

The `Beat` module estimates the tempo (BPM) of a musical audio signal by analyzing peak patterns in short-term audio features. It implements the same histogram-based beat detection algorithm as pyAudioAnalysis, producing matching BPM and confidence values.

## Why Beat?

Tempo estimation is fundamental to music information retrieval — it drives beat-synchronous analysis, automatic DJ mixing, music similarity, and rhythm-based classification. The approach here is lightweight and requires no deep learning: detect peaks in feature trajectories, measure their spacing, and find the dominant periodicity.

## Algorithm

1. **Feature selection**: 18 features are tracked — ZCR, Energy, Spectral Centroid through Rolloff, and MFCCs 1-11. These capture both spectral and timbral periodicity.

2. **Peak detection** (Billauer peakdet): For each feature trajectory, find local maxima that rise at least `2 * mean(|diffs|)` above the preceding minimum.

3. **Inter-peak histogram**: Compute the frame distance between consecutive peaks and accumulate into a histogram. Normalize by total frame count.

4. **Aggregate**: Sum histograms across all 18 features to get a robust multi-feature tempo estimate.

5. **BPM conversion**: `BPM = 60 / (peak_interval_frames * step_size_seconds)`.

6. **Confidence**: Ratio of the dominant histogram bin to total histogram mass.

## Procedures

### BeatExtract

```modula2
PROCEDURE BeatExtract(featureMatrix: ADDRESS;
                      numFrames, numFeatures: CARDINAL;
                      winStepSec: LONGREAL;
                      VAR bpm: LONGREAL;
                      VAR ratio: LONGREAL);
```

Estimate BPM from a short-term feature matrix (as returned by `ShortFeats.Extract`).

- `featureMatrix`: `numFrames x numFeatures` LONGREALs, row-major
- `winStepSec`: the step size used during feature extraction (e.g., 0.025 for 25ms)
- `bpm`: estimated beats per minute (0.0 if detection fails)
- `ratio`: confidence score in [0, 1] — higher is more rhythmic

```modula2
VAR bpm, ratio: LONGREAL;
Extract(signal, n, sr, 0.050, 0.025, feats, nFrames, ok);
BeatExtract(feats, nFrames, 34, 0.025, bpm, ratio);
(* bpm = 120.0, ratio = 0.35 for rhythmic music *)
```

**Interpretation**: Rhythmic music with a clear beat produces BPMs in 60-200 range with confidence > 20%. Speech and ambient audio produce high/unstable BPMs with confidence < 15%.

## Validation

Tested against pyAudioAnalysis v0.3.14 on two WAV files:

| File | pyAudioAnalysis | M2 |
|------|----------------|-----|
| WAV 1MB (speech) | 240.0 BPM, 12.1% | 239.9 BPM, 12% |
| WAV 5MB (orchestral) | 480.0 BPM, 15.4% | 479.9 BPM, 15% |

## Example

```modula2
MODULE BPMDemo;
FROM InOut IMPORT WriteString, WriteCard, WriteLn;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, Extract, FreeFeatures;
FROM Beat IMPORT BeatExtract;

VAR
  signal, feats: ADDRESS;
  n, sr, nFrames: CARDINAL;
  ok: BOOLEAN;
  bpm, ratio: LONGREAL;
BEGIN
  ReadAudio("song.wav", signal, n, sr, ok);
  IF NOT ok THEN HALT END;
  Extract(signal, n, sr, 0.050, 0.025, feats, nFrames, ok);
  IF NOT ok THEN FreeSignal(signal); HALT END;
  BeatExtract(feats, nFrames, NumFeatures, 0.025, bpm, ratio);
  WriteString("BPM: "); WriteCard(TRUNC(bpm), 0); WriteLn;
  FreeFeatures(feats);
  FreeSignal(signal)
END BPMDemo.
```
