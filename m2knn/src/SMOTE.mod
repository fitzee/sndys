IMPLEMENTATION MODULE SMOTE;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i * TSIZE(INTEGER)))
END ElemI;

(* Simple LCG pseudo-random for deterministic synthetic generation *)
VAR seed: LONGCARD;

PROCEDURE NextRand(): LONGREAL;
BEGIN
  seed := (seed * 1103515245 + 12345) MOD 2147483648;
  RETURN LFLOAT(seed) / 2147483648.0
END NextRand;

(* Find nearest neighbor of sample idx within the same class *)
PROCEDURE FindNearest(data: ADDRESS; labels: ADDRESS;
                      numSamples, numFeatures: CARDINAL;
                      idx: CARDINAL; targetClass: INTEGER): CARDINAL;
VAR
  i, f, bestIdx: CARDINAL;
  dist, bestDist, diff: LONGREAL;
  pA, pB: RealPtr;
  pL: IntPtr;
BEGIN
  bestDist := 1.0D30;
  bestIdx := idx;

  FOR i := 0 TO numSamples - 1 DO
    IF i # idx THEN
      pL := ElemI(labels, i);
      IF pL^ = targetClass THEN
        dist := 0.0;
        FOR f := 0 TO numFeatures - 1 DO
          pA := ElemR(data, idx * numFeatures + f);
          pB := ElemR(data, i * numFeatures + f);
          diff := pA^ - pB^;
          dist := dist + diff * diff
        END;
        IF dist < bestDist THEN
          bestDist := dist;
          bestIdx := i
        END
      END
    END
  END;

  RETURN bestIdx
END FindNearest;

PROCEDURE Oversample(data: ADDRESS; labels: ADDRESS;
                     numSamples, numFeatures, numClasses: CARDINAL;
                     VAR newData: ADDRESS; VAR newLabels: ADDRESS;
                     VAR newNumSamples: CARDINAL);
VAR
  c, i, f, idx, neighborIdx: CARDINAL;
  classCount: ARRAY [0..31] OF CARDINAL;
  maxCount, synthNeeded, synthTotal, outIdx: CARDINAL;
  pSrc, pNbr, pDst: RealPtr;
  pLSrc, pLDst: IntPtr;
  lambda: LONGREAL;
BEGIN
  newData := NIL;
  newLabels := NIL;
  newNumSamples := 0;
  seed := 42;

  IF (numSamples = 0) OR (numClasses = 0) THEN RETURN END;

  (* Count samples per class *)
  FOR c := 0 TO numClasses - 1 DO classCount[c] := 0 END;

  FOR i := 0 TO numSamples - 1 DO
    pLSrc := ElemI(labels, i);
    IF (pLSrc^ >= 0) AND (CARDINAL(pLSrc^) < numClasses) THEN
      INC(classCount[pLSrc^])
    END
  END;

  (* Find majority class count *)
  maxCount := 0;
  FOR c := 0 TO numClasses - 1 DO
    IF classCount[c] > maxCount THEN maxCount := classCount[c] END
  END;

  (* Count total synthetic samples needed *)
  synthTotal := 0;
  FOR c := 0 TO numClasses - 1 DO
    IF classCount[c] < maxCount THEN
      synthTotal := synthTotal + (maxCount - classCount[c])
    END
  END;

  newNumSamples := numSamples + synthTotal;
  ALLOCATE(newData, newNumSamples * numFeatures * TSIZE(LONGREAL));
  ALLOCATE(newLabels, newNumSamples * TSIZE(INTEGER));

  (* Copy original data *)
  FOR i := 0 TO numSamples - 1 DO
    FOR f := 0 TO numFeatures - 1 DO
      pSrc := ElemR(data, i * numFeatures + f);
      pDst := ElemR(newData, i * numFeatures + f);
      pDst^ := pSrc^
    END;
    pLSrc := ElemI(labels, i);
    pLDst := ElemI(newLabels, i);
    pLDst^ := pLSrc^
  END;

  (* Generate synthetic samples for each minority class *)
  outIdx := numSamples;

  FOR c := 0 TO numClasses - 1 DO
    IF classCount[c] < maxCount THEN
      synthNeeded := maxCount - classCount[c];

      (* For each synthetic sample: pick a random minority sample,
         find its nearest same-class neighbor, interpolate *)
      FOR i := 0 TO synthNeeded - 1 DO
        (* Pick a source sample from class c *)
        (* Cycle through class c samples *)
        idx := 0;
        (* Find the (i MOD classCount[c])-th sample of class c *)
        f := 0;
        FOR idx := 0 TO numSamples - 1 DO
          pLSrc := ElemI(labels, idx);
          IF pLSrc^ = INTEGER(c) THEN
            IF f = i MOD classCount[c] THEN
              (* Found our source sample *)
              neighborIdx := FindNearest(data, labels,
                                         numSamples, numFeatures,
                                         idx, INTEGER(c));

              (* Interpolate: synth = source + lambda * (neighbor - source) *)
              lambda := NextRand();

              FOR f := 0 TO numFeatures - 1 DO
                pSrc := ElemR(data, idx * numFeatures + f);
                pNbr := ElemR(data, neighborIdx * numFeatures + f);
                pDst := ElemR(newData, outIdx * numFeatures + f);
                pDst^ := pSrc^ + lambda * (pNbr^ - pSrc^)
              END;

              pLDst := ElemI(newLabels, outIdx);
              pLDst^ := INTEGER(c);
              INC(outIdx);
              idx := numSamples  (* break *)
            END;
            INC(f)
          END
        END
      END
    END
  END
END Oversample;

PROCEDURE FreeOversampled(VAR data: ADDRESS; VAR labels: ADDRESS);
BEGIN
  IF data # NIL THEN DEALLOCATE(data, 0); data := NIL END;
  IF labels # NIL THEN DEALLOCATE(labels, 0); labels := NIL END
END FreeOversampled;

END SMOTE.
