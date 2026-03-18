IMPLEMENTATION MODULE Segment;

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;
FROM ShortFeats IMPORT NumFeatures, ExtractFast, FreeFeatures;
FROM KNN IMPORT Model, Predict;
FROM HMM IMPORT GaussHMM, Init, Free, TrainSupervised, Smooth;
FROM KMeans IMPORT KMeansResult, Fit, Silhouette, FreeResult;

CONST
  WinSize = 0.050;   (* 50 ms *)
  WinStep = 0.025;   (* 25 ms *)
  MinSilenceFrames = 4;  (* minimum frames for a segment *)

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(INTEGER)))
END ElemI;

(* ── Silence removal ────────────────────────────────── *)

PROCEDURE RemoveSilence(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                        energyThreshold, minDurationSec: LONGREAL;
                        VAR segments: SegmentList);
VAR
  winSamp, stepSamp, numFrames: CARDINAL;
  i, j, frameStart: CARDINAL;
  energy, maxEnergy, threshold: LONGREAL;
  p: RealPtr;
  isSpeech: BOOLEAN;
  inSegment: BOOLEAN;
  segStart: CARDINAL;
  startSec, endSec, minDur: LONGREAL;
BEGIN
  segments.numSegments := 0;

  winSamp := TRUNC(WinSize * LFLOAT(sampleRate));
  stepSamp := TRUNC(WinStep * LFLOAT(sampleRate));

  IF (winSamp = 0) OR (stepSamp = 0) OR (numSamples < winSamp) THEN
    RETURN
  END;

  numFrames := (numSamples - winSamp) DIV stepSamp + 1;

  (* First pass: find max frame energy *)
  maxEnergy := 0.0;
  FOR i := 0 TO numFrames - 1 DO
    frameStart := i * stepSamp;
    energy := 0.0;
    FOR j := 0 TO winSamp - 1 DO
      p := ElemR(signal, frameStart + j);
      energy := energy + p^ * p^
    END;
    energy := energy / LFLOAT(winSamp);
    IF energy > maxEnergy THEN maxEnergy := energy END
  END;

  IF maxEnergy = 0.0 THEN RETURN END;

  threshold := energyThreshold * maxEnergy;
  minDur := minDurationSec;

  (* Second pass: find non-silent segments *)
  inSegment := FALSE;
  segStart := 0;

  FOR i := 0 TO numFrames - 1 DO
    frameStart := i * stepSamp;
    energy := 0.0;
    FOR j := 0 TO winSamp - 1 DO
      p := ElemR(signal, frameStart + j);
      energy := energy + p^ * p^
    END;
    energy := energy / LFLOAT(winSamp);

    isSpeech := energy > threshold;

    IF isSpeech AND (NOT inSegment) THEN
      (* Start of non-silent segment *)
      segStart := i;
      inSegment := TRUE
    ELSIF (NOT isSpeech) AND inSegment THEN
      (* End of non-silent segment *)
      startSec := LFLOAT(segStart) * WinStep;
      endSec := LFLOAT(i) * WinStep;
      IF (endSec - startSec >= minDur) AND
         (segments.numSegments < MaxSegments) THEN
        segments.starts[segments.numSegments] := startSec;
        segments.ends[segments.numSegments] := endSec;
        segments.labels[segments.numSegments] := 1;  (* 1 = speech/active *)
        INC(segments.numSegments)
      END;
      inSegment := FALSE
    END
  END;

  (* Close final segment if still active *)
  IF inSegment THEN
    startSec := LFLOAT(segStart) * WinStep;
    endSec := LFLOAT(numFrames) * WinStep;
    IF (endSec - startSec >= minDur) AND
       (segments.numSegments < MaxSegments) THEN
      segments.starts[segments.numSegments] := startSec;
      segments.ends[segments.numSegments] := endSec;
      segments.labels[segments.numSegments] := 1;
      INC(segments.numSegments)
    END
  END
END RemoveSilence;

(* ── Supervised segmentation ─────────────────────────── *)

PROCEDURE SegmentSupervised(signal: ADDRESS;
                            numSamples, sampleRate: CARDINAL;
                            VAR model: Model;
                            useHMM: BOOLEAN;
                            VAR segments: SegmentList);
VAR
  featureMatrix: ADDRESS;
  numFrames, i: CARDINAL;
  ok: BOOLEAN;
  frameRow: ADDRESS;
  rawLabels, smoothedLabels: ADDRESS;
  pLabel, pSmooth: IntPtr;
  pred, prevLabel, curLabel: INTEGER;
  segStart: CARDINAL;
  startSec, endSec: LONGREAL;
  hmm: GaussHMM;
  labelPtr: ADDRESS;
BEGIN
  segments.numSegments := 0;

  (* Extract short-term features *)
  ExtractFast(signal, numSamples, sampleRate,
              WinSize, WinStep,
              featureMatrix, numFrames, ok);

  IF (NOT ok) OR (numFrames = 0) THEN RETURN END;

  (* Classify each frame *)
  ALLOCATE(rawLabels, numFrames * TSIZE(INTEGER));

  FOR i := 0 TO numFrames - 1 DO
    frameRow := ADDRESS(LONGCARD(featureMatrix)
                + LONGCARD(i) * LONGCARD(NumFeatures) * LONGCARD(TSIZE(LONGREAL)));
    pLabel := ElemI(rawLabels, i);
    pLabel^ := Predict(model, frameRow)
  END;

  (* Optional HMM smoothing *)
  IF useHMM THEN
    ALLOCATE(smoothedLabels, numFrames * TSIZE(INTEGER));

    (* Train HMM from raw predictions *)
    HMM.Init(hmm, model.numClasses, NumFeatures);
    TrainSupervised(hmm, featureMatrix, rawLabels, numFrames);

    (* Re-decode with Viterbi *)
    Smooth(hmm, featureMatrix, numFrames, smoothedLabels);
    HMM.Free(hmm);

    labelPtr := smoothedLabels
  ELSE
    smoothedLabels := NIL;
    labelPtr := rawLabels
  END;

  (* Convert frame labels to segment boundaries *)
  pLabel := ElemI(labelPtr, 0);
  prevLabel := pLabel^;
  segStart := 0;

  FOR i := 1 TO numFrames - 1 DO
    pLabel := ElemI(labelPtr, i);
    curLabel := pLabel^;

    IF curLabel # prevLabel THEN
      (* Emit segment *)
      IF segments.numSegments < MaxSegments THEN
        startSec := LFLOAT(segStart) * WinStep;
        endSec := LFLOAT(i) * WinStep;
        segments.starts[segments.numSegments] := startSec;
        segments.ends[segments.numSegments] := endSec;
        segments.labels[segments.numSegments] := prevLabel;
        INC(segments.numSegments)
      END;
      segStart := i;
      prevLabel := curLabel
    END
  END;

  (* Emit final segment *)
  IF segments.numSegments < MaxSegments THEN
    startSec := LFLOAT(segStart) * WinStep;
    endSec := LFLOAT(numFrames) * WinStep;
    segments.starts[segments.numSegments] := startSec;
    segments.ends[segments.numSegments] := endSec;
    segments.labels[segments.numSegments] := prevLabel;
    INC(segments.numSegments)
  END;

  (* Cleanup *)
  DEALLOCATE(rawLabels, numFrames * TSIZE(INTEGER));
  IF smoothedLabels # NIL THEN
    DEALLOCATE(smoothedLabels, numFrames * TSIZE(INTEGER))
  END;
  FreeFeatures(featureMatrix, numFrames)
END SegmentSupervised;

(* ── Speaker diarization via K-Means ──────────────── *)

PROCEDURE Diarize(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  numSpeakers: CARDINAL;
                  VAR segments: SegmentList);
VAR
  featureMatrix: ADDRESS;
  numFrames, k, bestK, i: CARDINAL;
  ok: BOOLEAN;
  result, bestResult: KMeansResult;
  sil, bestSil: LONGREAL;
  pLabel: IntPtr;
  prevLabel, curLabel: INTEGER;
  segStart: CARDINAL;
  startSec, endSec: LONGREAL;
BEGIN
  segments.numSegments := 0;

  (* Extract features using fast FFT path *)
  ExtractFast(signal, numSamples, sampleRate,
              WinSize, WinStep,
              featureMatrix, numFrames, ok);

  IF (NOT ok) OR (numFrames = 0) THEN RETURN END;

  IF numSpeakers > 0 THEN
    (* Fixed number of speakers *)
    Fit(result, featureMatrix, numFrames, NumFeatures,
        numSpeakers, 100, 1.0D-4);
    bestK := numSpeakers
  ELSE
    (* Auto-detect: try k=2..8, pick best silhouette *)
    bestSil := -2.0;
    bestK := 2;

    FOR k := 2 TO 8 DO
      Fit(result, featureMatrix, numFrames, NumFeatures,
          k, 100, 1.0D-4);
      sil := Silhouette(result, featureMatrix);
      IF sil > bestSil THEN
        bestSil := sil;
        bestK := k;
        (* Keep best result — but we need to re-fit since we can't copy *)
        FreeResult(result)
      ELSE
        FreeResult(result)
      END
    END;

    (* Re-fit with best k *)
    Fit(result, featureMatrix, numFrames, NumFeatures,
        bestK, 100, 1.0D-4)
  END;

  (* Convert cluster labels to segments *)
  pLabel := ElemI(result.labels, 0);
  prevLabel := pLabel^;
  segStart := 0;

  FOR i := 1 TO numFrames - 1 DO
    pLabel := ElemI(result.labels, i);
    curLabel := pLabel^;

    IF curLabel # prevLabel THEN
      IF segments.numSegments < MaxSegments THEN
        startSec := LFLOAT(segStart) * WinStep;
        endSec := LFLOAT(i) * WinStep;
        segments.starts[segments.numSegments] := startSec;
        segments.ends[segments.numSegments] := endSec;
        segments.labels[segments.numSegments] := prevLabel;
        INC(segments.numSegments)
      END;
      segStart := i;
      prevLabel := curLabel
    END
  END;

  (* Final segment *)
  IF segments.numSegments < MaxSegments THEN
    startSec := LFLOAT(segStart) * WinStep;
    endSec := LFLOAT(numFrames) * WinStep;
    segments.starts[segments.numSegments] := startSec;
    segments.ends[segments.numSegments] := endSec;
    segments.labels[segments.numSegments] := prevLabel;
    INC(segments.numSegments)
  END;

  FreeResult(result);
  FreeFeatures(featureMatrix, numFrames)
END Diarize;

(* ── Moving average label smoothing ────────────────── *)

PROCEDURE SmoothLabels(labels: ADDRESS; numFrames: CARDINAL;
                       windowSize: CARDINAL);
VAR
  i, j, half, startJ, endJ: CARDINAL;
  c, maxCount, bestLabel: CARDINAL;
  pL: IntPtr;
  counts: ARRAY [0..31] OF CARDINAL;
  smoothed: ADDRESS;
  pS: IntPtr;
BEGIN
  IF (numFrames = 0) OR (windowSize <= 1) THEN RETURN END;

  half := windowSize DIV 2;

  (* Allocate temp buffer for smoothed labels *)
  ALLOCATE(smoothed, numFrames * TSIZE(INTEGER));

  FOR i := 0 TO numFrames - 1 DO
    (* Determine window bounds *)
    IF i >= half THEN startJ := i - half ELSE startJ := 0 END;
    endJ := i + half;
    IF endJ >= numFrames THEN endJ := numFrames - 1 END;

    (* Count label occurrences in window *)
    FOR c := 0 TO 31 DO counts[c] := 0 END;

    FOR j := startJ TO endJ DO
      pL := ElemI(labels, j);
      IF (pL^ >= 0) AND (pL^ < 32) THEN
        INC(counts[pL^])
      END
    END;

    (* Find majority label *)
    maxCount := 0;
    bestLabel := 0;
    FOR c := 0 TO 31 DO
      IF counts[c] > maxCount THEN
        maxCount := counts[c];
        bestLabel := c
      END
    END;

    pS := ElemI(smoothed, i);
    pS^ := INTEGER(bestLabel)
  END;

  (* Copy back *)
  FOR i := 0 TO numFrames - 1 DO
    pS := ElemI(smoothed, i);
    pL := ElemI(labels, i);
    pL^ := pS^
  END;

  DEALLOCATE(smoothed, numFrames * TSIZE(INTEGER))
END SmoothLabels;

END Segment.
