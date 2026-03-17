IMPLEMENTATION MODULE TempoCurve;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM ShortFeats IMPORT NumFeatures, ExtractFast, FreeFeatures;
FROM Beat IMPORT BeatExtract;

CONST
  WinSize = 0.050;
  WinStep = 0.025;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE ComputeTempoCurve(signal: ADDRESS;
                             numSamples, sampleRate: CARDINAL;
                             windowSec, hopSec: LONGREAL;
                             VAR bpms: ADDRESS;
                             VAR times: ADDRESS;
                             VAR numPoints: CARDINAL);
VAR
  winSamp, hopSamp, totalPoints, i: CARDINAL;
  startSamp, endSamp, segLen: CARDINAL;
  segAddr, feats: ADDRESS;
  numFrames: CARDINAL;
  ok: BOOLEAN;
  bpm, ratio: LONGREAL;
  pB, pT: RealPtr;
BEGIN
  bpms := NIL;
  times := NIL;
  numPoints := 0;

  winSamp := TRUNC(windowSec * LFLOAT(sampleRate));
  hopSamp := TRUNC(hopSec * LFLOAT(sampleRate));
  IF (winSamp = 0) OR (hopSamp = 0) OR (numSamples < winSamp) THEN RETURN END;

  totalPoints := (numSamples - winSamp) DIV hopSamp + 1;
  IF totalPoints = 0 THEN RETURN END;

  ALLOCATE(bpms, totalPoints * TSIZE(LONGREAL));
  ALLOCATE(times, totalPoints * TSIZE(LONGREAL));

  FOR i := 0 TO totalPoints - 1 DO
    startSamp := i * hopSamp;
    endSamp := startSamp + winSamp;
    IF endSamp > numSamples THEN endSamp := numSamples END;
    segLen := endSamp - startSamp;

    segAddr := ADDRESS(LONGCARD(signal)
               + LONGCARD(startSamp * TSIZE(LONGREAL)));

    ExtractFast(segAddr, segLen, sampleRate, WinSize, WinStep,
                feats, numFrames, ok);

    pT := Elem(times, i);
    pT^ := LFLOAT(startSamp + winSamp DIV 2) / LFLOAT(sampleRate);

    pB := Elem(bpms, i);
    IF ok AND (numFrames > 4) THEN
      BeatExtract(feats, numFrames, NumFeatures, WinStep, bpm, ratio);
      pB^ := bpm;
      FreeFeatures(feats)
    ELSE
      pB^ := 0.0
    END
  END;

  numPoints := totalPoints
END ComputeTempoCurve;

PROCEDURE FreeTempoCurve(VAR bpms: ADDRESS; VAR times: ADDRESS);
BEGIN
  IF bpms # NIL THEN DEALLOCATE(bpms, 0); bpms := NIL END;
  IF times # NIL THEN DEALLOCATE(times, 0); times := NIL END
END FreeTempoCurve;

END TempoCurve.
