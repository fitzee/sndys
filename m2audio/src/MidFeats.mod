IMPLEMENTATION MODULE MidFeats;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE Extract(shortFeats: ADDRESS;
                  numFrames, numFeatures: CARDINAL;
                  midWinFrames, midStepFrames: CARDINAL;
                  VAR midFeats: ADDRESS;
                  VAR numMidFrames: CARDINAL;
                  VAR ok: BOOLEAN);
VAR
  midIdx, f, i: CARDINAL;
  startFrame, endFrame, count: CARDINAL;
  totalMidFrames, outCols: CARDINAL;
  m, s, diff: LONGREAL;
  pSrc, pDst: RealPtr;
BEGIN
  ok := FALSE;
  midFeats := NIL;
  numMidFrames := 0;

  IF (numFrames = 0) OR (numFeatures = 0) OR
     (midWinFrames = 0) OR (midStepFrames = 0) THEN
    RETURN
  END;

  IF numFrames < midWinFrames THEN RETURN END;

  totalMidFrames := (numFrames - midWinFrames) DIV midStepFrames + 1;
  IF totalMidFrames = 0 THEN RETURN END;

  outCols := 2 * numFeatures;

  ALLOCATE(midFeats, totalMidFrames * outCols * TSIZE(LONGREAL));

  FOR midIdx := 0 TO totalMidFrames - 1 DO
    startFrame := midIdx * midStepFrames;
    endFrame := startFrame + midWinFrames - 1;
    IF endFrame >= numFrames THEN
      endFrame := numFrames - 1
    END;
    count := endFrame - startFrame + 1;

    FOR f := 0 TO numFeatures - 1 DO
      (* Compute mean of feature f over the mid-term window *)
      m := 0.0;
      FOR i := startFrame TO endFrame DO
        pSrc := Elem(shortFeats, i * numFeatures + f);
        m := m + pSrc^
      END;
      m := m / LFLOAT(count);

      (* Compute std dev of feature f *)
      s := 0.0;
      FOR i := startFrame TO endFrame DO
        pSrc := Elem(shortFeats, i * numFeatures + f);
        diff := pSrc^ - m;
        s := s + diff * diff
      END;
      s := LFLOAT(sqrt(FLOAT(s / LFLOAT(count))));

      (* Store mean *)
      pDst := Elem(midFeats, midIdx * outCols + f);
      pDst^ := m;

      (* Store std dev *)
      pDst := Elem(midFeats, midIdx * outCols + numFeatures + f);
      pDst^ := s
    END
  END;

  numMidFrames := totalMidFrames;
  ok := TRUE
END Extract;

PROCEDURE FreeMidFeatures(VAR midFeats: ADDRESS);
BEGIN
  IF midFeats # NIL THEN
    DEALLOCATE(midFeats, 0);
    midFeats := NIL
  END
END FreeMidFeatures;

END MidFeats.
