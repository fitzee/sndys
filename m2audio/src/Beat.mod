IMPLEMENTATION MODULE Beat;
(* Beat extraction — aligned with pyAudioAnalysis.

   Algorithm:
   1. Select 18 features related to beat tracking
   2. For each feature trajectory:
      a. Threshold = 2 * mean(abs(diffs))
      b. Peak detection (Billauer peakdet)
      c. Histogram inter-peak intervals
   3. Aggregate histograms across features
   4. BPM = 60 / (argmax_interval * step_size)
   5. Confidence = max_bin / total *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathUtil IMPORT FAbs;

CONST
  NumSelected = 18;
  MaxPeaks    = 2048;
  MaxBeatTime = 200;  (* max histogram bins *)
  Eps         = 1.0D-16;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END ElemR;

(* ── Billauer peak detection ─────────────────────────── *)
(* Finds local maxima in a signal where the peak is at least
   delta above the preceding minimum.
   Returns peak positions (indices) in peakPos, count in numPeaks. *)

PROCEDURE PeakDet(featureMatrix: ADDRESS;
                  numFrames, numFeatures, featIdx: CARDINAL;
                  delta: LONGREAL;
                  VAR peakPos: ARRAY OF CARDINAL;
                  VAR numPeaks: CARDINAL);
VAR
  i: CARDINAL;
  val, mx, mn: LONGREAL;
  mxPos: CARDINAL;
  lookForMax: BOOLEAN;
  p: RealPtr;
BEGIN
  numPeaks := 0;
  IF numFrames < 3 THEN RETURN END;

  p := ElemR(featureMatrix, 0 * numFeatures + featIdx);
  mx := p^;
  mn := p^;
  mxPos := 0;
  lookForMax := TRUE;

  FOR i := 1 TO numFrames - 1 DO
    p := ElemR(featureMatrix, i * numFeatures + featIdx);
    val := p^;

    IF val > mx THEN
      mx := val;
      mxPos := i
    END;
    IF val < mn THEN
      mn := val
    END;

    IF lookForMax THEN
      IF val < mx - delta THEN
        (* Found a peak *)
        IF numPeaks <= HIGH(peakPos) THEN
          peakPos[numPeaks] := mxPos;
          INC(numPeaks)
        END;
        mn := val;
        lookForMax := FALSE
      END
    ELSE
      IF val > mn + delta THEN
        mx := val;
        mxPos := i;
        lookForMax := TRUE
      END
    END
  END
END PeakDet;

(* ── Main beat extraction ────────────────────────────── *)

PROCEDURE BeatExtract(featureMatrix: ADDRESS;
                      numFrames, numFeatures: CARDINAL;
                      winStepSec: LONGREAL;
                      VAR bpm: LONGREAL;
                      VAR ratio: LONGREAL);
VAR
  (* Selected feature indices matching pyAudioAnalysis *)
  selected: ARRAY [0..17] OF CARDINAL;
  si, i, j: CARDINAL;
  featIdx: CARDINAL;
  maxBeatTime: CARDINAL;

  (* Per-feature *)
  difThreshold, difSum, meanDif: LONGREAL;
  pCur, pPrev: RealPtr;
  numDifs: CARDINAL;

  (* Peak detection *)
  peakPos: ARRAY [0..2047] OF CARDINAL;
  numPeaks: CARDINAL;
  interval: CARDINAL;

  (* Histogram *)
  histAll: ARRAY [0..199] OF LONGREAL;
  histSum, maxHist, halfSupport: LONGREAL;
  maxIdx: CARDINAL;
  bpmVal: LONGREAL;
BEGIN
  bpm := 0.0;
  ratio := 0.0;

  IF numFrames < 4 THEN RETURN END;

  (* Feature indices: ZCR, Energy, SpectCentroid..Rolloff, MFCC1..10 *)
  selected[0]  := 0;   (* ZCR *)
  selected[1]  := 1;   (* Energy *)
  selected[2]  := 3;   (* Spectral Centroid *)
  selected[3]  := 4;   (* Spectral Spread *)
  selected[4]  := 5;   (* Spectral Entropy *)
  selected[5]  := 6;   (* Spectral Flux *)
  selected[6]  := 7;   (* Spectral Rolloff *)
  selected[7]  := 8;   (* MFCC 1 *)
  selected[8]  := 9;   (* MFCC 2 *)
  selected[9]  := 10;  (* MFCC 3 *)
  selected[10] := 11;  (* MFCC 4 *)
  selected[11] := 12;  (* MFCC 5 *)
  selected[12] := 13;  (* MFCC 6 *)
  selected[13] := 14;  (* MFCC 7 *)
  selected[14] := 15;  (* MFCC 8 *)
  selected[15] := 16;  (* MFCC 9 *)
  selected[16] := 17;  (* MFCC 10 *)
  selected[17] := 18;  (* MFCC 11 *)

  (* max_beat_time = round(2.0 / winStepSec) *)
  maxBeatTime := TRUNC(2.0 / winStepSec + 0.5);
  IF maxBeatTime > MaxBeatTime THEN maxBeatTime := MaxBeatTime END;
  IF maxBeatTime = 0 THEN RETURN END;

  (* Zero histogram *)
  FOR i := 0 TO maxBeatTime - 1 DO
    histAll[i] := 0.0
  END;

  (* Process each selected feature *)
  FOR si := 0 TO NumSelected - 1 DO
    featIdx := selected[si];
    IF featIdx >= numFeatures THEN
      (* skip if feature doesn't exist *)
    ELSE
      (* Compute dif threshold: 2 * mean(abs(diffs)) *)
      difSum := 0.0;
      numDifs := numFrames - 1;
      FOR i := 0 TO numDifs - 1 DO
        pCur := ElemR(featureMatrix, (i + 1) * numFeatures + featIdx);
        pPrev := ElemR(featureMatrix, i * numFeatures + featIdx);
        difSum := difSum + FAbs(pCur^ - pPrev^)
      END;
      IF numDifs > 0 THEN
        meanDif := difSum / LFLOAT(numDifs)
      ELSE
        meanDif := Eps
      END;
      difThreshold := 2.0 * meanDif;
      IF difThreshold <= 0.0 THEN difThreshold := Eps END;

      (* Detect peaks *)
      PeakDet(featureMatrix, numFrames, numFeatures, featIdx,
              difThreshold, peakPos, numPeaks);

      (* Build histogram of inter-peak intervals *)
      IF numPeaks > 1 THEN
        FOR i := 0 TO numPeaks - 2 DO
          interval := peakPos[i + 1] - peakPos[i];
          IF (interval >= 1) AND (interval <= maxBeatTime) THEN
            histAll[interval - 1] := histAll[interval - 1]
                                     + 1.0 / LFLOAT(numFrames)
          END
        END
      END
    END
  END;

  (* Find histogram peak *)
  maxHist := 0.0;
  maxIdx := 0;
  histSum := 0.0;
  FOR i := 0 TO maxBeatTime - 1 DO
    histSum := histSum + histAll[i];
    IF histAll[i] > maxHist THEN
      maxHist := histAll[i];
      maxIdx := i
    END
  END;

  IF (maxHist = 0.0) OR (histSum = 0.0) THEN RETURN END;

  (* Convert to BPM: interval is (maxIdx + 1) frames *)
  (* BPM = 60 / (interval_frames * winStepSec) *)
  bpmVal := 60.0 / (LFLOAT(maxIdx + 1) * winStepSec);

  (* Octave correction: beat detectors commonly lock onto harmonics.
     Strategy: check if the half-tempo region (double interval +/- 1 bin)
     has histogram support. If so, prefer the lower BPM. *)
  LOOP
    j := (maxIdx + 1) * 2 - 1;  (* double the interval = half BPM *)
    IF (bpmVal / 2.0 < 60.0) THEN EXIT END;

    (* Check a window of 3 bins around the half-tempo position *)
    halfSupport := 0.0;
    IF (j >= 1) AND (j - 1 < maxBeatTime) THEN
      halfSupport := halfSupport + histAll[j - 1]
    END;
    IF j < maxBeatTime THEN
      halfSupport := halfSupport + histAll[j]
    END;
    IF j + 1 < maxBeatTime THEN
      halfSupport := halfSupport + histAll[j + 1]
    END;

    IF halfSupport > maxHist * 0.05 THEN
      (* Half-tempo region has at least 5% of the peak's support *)
      bpmVal := bpmVal / 2.0;
      maxIdx := j
    ELSE
      EXIT
    END
  END;

  (* If BPM is still very high with no half-tempo support,
     force-halve down to reasonable range *)
  WHILE bpmVal > 200.0 DO
    bpmVal := bpmVal / 2.0
  END;

  (* If BPM is too low, try doubling *)
  WHILE bpmVal < 50.0 DO
    bpmVal := bpmVal * 2.0
  END;

  bpm := bpmVal;
  ratio := maxHist / histSum
END BeatExtract;

END Beat.
