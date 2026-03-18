IMPLEMENTATION MODULE Delta;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

PROCEDURE ComputeDeltas(featureMatrix: ADDRESS;
                        numFrames, numFeatures: CARDINAL;
                        VAR deltaMatrix: ADDRESS);
VAR
  t, f: CARDINAL;
  pCur, pPrev, pDst: RealPtr;
BEGIN
  IF (numFrames = 0) OR (numFeatures = 0) THEN
    deltaMatrix := NIL;
    RETURN
  END;

  ALLOCATE(deltaMatrix, numFrames * numFeatures * TSIZE(LONGREAL));

  (* First frame: delta = 0 *)
  FOR f := 0 TO numFeatures - 1 DO
    pDst := Elem(deltaMatrix, f);
    pDst^ := 0.0
  END;

  (* Remaining frames: delta[t] = feat[t] - feat[t-1] *)
  FOR t := 1 TO numFrames - 1 DO
    FOR f := 0 TO numFeatures - 1 DO
      pCur := Elem(featureMatrix, t * numFeatures + f);
      pPrev := Elem(featureMatrix, (t - 1) * numFeatures + f);
      pDst := Elem(deltaMatrix, t * numFeatures + f);
      pDst^ := pCur^ - pPrev^
    END
  END
END ComputeDeltas;

PROCEDURE CombineWithDeltas(featureMatrix: ADDRESS;
                            numFrames, numFeatures: CARDINAL;
                            VAR combined: ADDRESS);
VAR
  t, f: CARDINAL;
  outCols: CARDINAL;
  pSrc, pDst, pCur, pPrev: RealPtr;
BEGIN
  IF (numFrames = 0) OR (numFeatures = 0) THEN
    combined := NIL;
    RETURN
  END;

  outCols := 2 * numFeatures;
  ALLOCATE(combined, numFrames * outCols * TSIZE(LONGREAL));

  FOR t := 0 TO numFrames - 1 DO
    (* Copy original features *)
    FOR f := 0 TO numFeatures - 1 DO
      pSrc := Elem(featureMatrix, t * numFeatures + f);
      pDst := Elem(combined, t * outCols + f);
      pDst^ := pSrc^
    END;

    (* Compute and store deltas *)
    FOR f := 0 TO numFeatures - 1 DO
      pDst := Elem(combined, t * outCols + numFeatures + f);
      IF t = 0 THEN
        pDst^ := 0.0
      ELSE
        pCur := Elem(featureMatrix, t * numFeatures + f);
        pPrev := Elem(featureMatrix, (t - 1) * numFeatures + f);
        pDst^ := pCur^ - pPrev^
      END
    END
  END
END CombineWithDeltas;

PROCEDURE FreeDelta(VAR matrix: ADDRESS; numElements: CARDINAL);
BEGIN
  IF matrix # NIL THEN
    DEALLOCATE(matrix, numElements * TSIZE(LONGREAL));
    matrix := NIL
  END
END FreeDelta;

END Delta.
