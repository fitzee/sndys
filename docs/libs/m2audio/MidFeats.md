# MidFeats

The `MidFeats` module computes mid-term feature statistics by sliding a window over the short-term feature matrix produced by `ShortFeats.Extract`. For each mid-term window, it calculates the mean and standard deviation of every short-term feature, producing a compact statistical summary suitable for audio segment classification, speaker clustering, and music genre recognition.

## Why MidFeats?

Short-term features describe what is happening in a single 20-50 ms frame of audio. That is too fine-grained for most classification tasks -- a genre label applies to seconds or minutes of audio, not to individual frames. Mid-term statistics solve this by summarizing how each feature behaves over a longer window (typically 1-2 seconds). The mean captures the average character of the signal in that window, while the standard deviation captures its variability. Together, they give classifiers a stable, fixed-length representation of an audio segment regardless of its duration. This is the standard two-level feature extraction architecture used by pyAudioAnalysis and most audio classification systems.

## Output Layout

The output matrix has `numMidFrames` rows and `2 * numFeatures` columns. Each row corresponds to one mid-term window. The columns are arranged as **all means first, then all standard deviations**:

```
Row i: [mean_f0, mean_f1, ..., mean_f33, std_f0, std_f1, ..., std_f33]
        |<--- numFeatures means --->|    |<--- numFeatures stds --->|
```

When used with `ShortFeats` (where `numFeatures = 34`), each row has 68 values:

| Column range | Content |
|---|---|
| 0 - 33 | Mean of each short-term feature over the mid-term window |
| 34 - 67 | Standard deviation of each short-term feature over the mid-term window |

So column 0 is the mean Zero Crossing Rate, column 1 is the mean Energy, column 34 is the standard deviation of Zero Crossing Rate, column 35 is the standard deviation of Energy, and so on. The feature ordering within each half matches the `ShortFeats` feature index exactly.

**Indexing formula:** For short-term feature index `f` (0-33):
- Mean: `row * 68 + f`
- Std dev: `row * 68 + 34 + f`

More generally, for arbitrary `numFeatures`:
- Mean: `row * (2 * numFeatures) + f`
- Std dev: `row * (2 * numFeatures) + numFeatures + f`

## Procedures

### Extract

```modula2
PROCEDURE Extract(shortFeats: ADDRESS;
                  numFrames, numFeatures: CARDINAL;
                  midWinFrames, midStepFrames: CARDINAL;
                  VAR midFeats: ADDRESS;
                  VAR numMidFrames: CARDINAL;
                  VAR ok: BOOLEAN);
```

Computes mid-term feature statistics from a short-term feature matrix. The input `shortFeats` is a flat row-major array of `numFrames * numFeatures` `LONGREAL` values, as produced by `ShortFeats.Extract`. The `midWinFrames` parameter specifies how many short-term frames make up one mid-term window, and `midStepFrames` specifies the hop between consecutive mid-term windows (both in frame counts, not seconds).

To convert from seconds to frames: `midWinFrames = TRUNC(midWinSec / winStepSec)`, where `winStepSec` is the short-term hop size you passed to `ShortFeats.Extract`.

The number of output mid-term frames is `(numFrames - midWinFrames) DIV midStepFrames + 1`. The output `midFeats` is a dynamically allocated flat array of `numMidFrames * (2 * numFeatures)` `LONGREAL` values. The caller must free it with `FreeMidFeatures` when done.

On failure (zero-length input, window larger than input, invalid parameters), `ok` is `FALSE`, `midFeats` is `NIL`, and `numMidFrames` is 0.

**Usage example:**

```modula2
VAR
  midFeats     : ADDRESS;
  numMidFrames : CARDINAL;
  ok           : BOOLEAN;
  midWin, midStep : CARDINAL;

(* 1-second mid-term window with 0.5-second step,
   given a short-term hop of 0.025 seconds *)
midWin  := 40;  (* 1.0 / 0.025 *)
midStep := 20;  (* 0.5 / 0.025 *)

Extract(shortFeats, numFrames, 34,
        midWin, midStep,
        midFeats, numMidFrames, ok);
IF ok THEN
  (* midFeats holds numMidFrames * 68 LONGREALs *)
  FreeMidFeatures(midFeats)
END;
```

### FreeMidFeatures

```modula2
PROCEDURE FreeMidFeatures(VAR midFeats: ADDRESS);
```

Deallocates the mid-term feature matrix returned by `Extract`. After this call, `midFeats` is set to `NIL`. It is safe to call on a `NIL` pointer.

**Usage example:**

```modula2
FreeMidFeatures(midFeats);
(* midFeats is now NIL *)
```

## Example

A complete program that reads a WAV file, extracts short-term features, computes mid-term statistics, and prints the mean and standard deviation of each feature for the first mid-term window:

```modula2
MODULE MidFeatsDemo;

FROM SYSTEM     IMPORT ADDRESS, TSIZE;
FROM InOut      IMPORT WriteString, WriteLn, WriteCard;
FROM AudioIO    IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT Extract, FreeFeatures, FeatureName, NumFeatures;
FROM MidFeats   IMPORT Extract, FreeMidFeatures;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

VAR
  sig           : ADDRESS;
  nSamples, rate : CARDINAL;
  ok            : BOOLEAN;
  shortFeats    : ADDRESS;
  numFrames     : CARDINAL;
  midFeats      : ADDRESS;
  numMidFrames  : CARDINAL;
  midWin, midStep : CARDINAL;
  i             : CARDINAL;
  pMean, pStd   : RealPtr;
  nameBuf       : ARRAY [0..63] OF CHAR;
  outCols       : CARDINAL;

BEGIN
  ReadAudio("speech.wav", sig, nSamples, rate, ok);
  IF NOT ok THEN
    WriteString("Failed to read audio.");
    WriteLn;
    RETURN
  END;

  (* Short-term extraction: 50 ms window, 25 ms step *)
  ShortFeats.Extract(sig, nSamples, rate,
                     0.050, 0.025,
                     shortFeats, numFrames, ok);
  IF NOT ok THEN
    WriteString("Short-term extraction failed.");
    WriteLn;
    FreeSignal(sig);
    RETURN
  END;

  (* Mid-term extraction: 1.0 s window, 0.5 s step *)
  midWin  := 40;
  midStep := 20;
  MidFeats.Extract(shortFeats, numFrames, NumFeatures,
                   midWin, midStep,
                   midFeats, numMidFrames, ok);
  IF NOT ok THEN
    WriteString("Mid-term extraction failed.");
    WriteLn;
    FreeFeatures(shortFeats);
    FreeSignal(sig);
    RETURN
  END;

  WriteString("Mid-term frames: ");
  WriteCard(numMidFrames, 0);
  WriteLn;
  WriteLn;

  (* Print mean and std dev for each feature in mid-term frame 0 *)
  outCols := 2 * NumFeatures;
  WriteString("--- Mid-term frame 0 ---");
  WriteLn;
  WriteString("Feature                     Mean         Std Dev");
  WriteLn;

  FOR i := 0 TO NumFeatures - 1 DO
    FeatureName(i, nameBuf);
    WriteString(nameBuf);
    WriteString(": ");
    pMean := Elem(midFeats, i);
    (* print pMean^ *)
    WriteString("  ");
    pStd := Elem(midFeats, NumFeatures + i);
    (* print pStd^ *)
    WriteLn
  END;

  FreeMidFeatures(midFeats);
  FreeFeatures(shortFeats);
  FreeSignal(sig)
END MidFeatsDemo.
```
