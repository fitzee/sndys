IMPLEMENTATION MODULE Regress;

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM MathLib IMPORT sqrt;
FROM Scaler IMPORT ScalerState, FitTransform;

CONST
  Eps = 1.0D-10;
  MaxK = 51;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE EuclideanDist(a, b: ADDRESS; n: CARDINAL): LONGREAL;
VAR i: CARDINAL; d, diff: LONGREAL; pa, pb: RealPtr;
BEGIN
  d := 0.0;
  FOR i := 0 TO n - 1 DO
    pa := ElemR(a, i);
    pb := ElemR(b, i);
    diff := pa^ - pb^;
    d := d + diff * diff
  END;
  RETURN LFLOAT(sqrt(FLOAT(d)))
END EuclideanDist;

PROCEDURE Init(VAR m: RegModel; k, numFeatures: CARDINAL;
               weighted: BOOLEAN);
BEGIN
  m.trainData := NIL;
  m.trainTargets := NIL;
  m.numTrain := 0;
  IF numFeatures > 128 THEN m.numFeatures := 128
  ELSE m.numFeatures := numFeatures END;
  IF k > MaxK THEN m.k := MaxK ELSE m.k := k END;
  IF m.k = 0 THEN m.k := 1 END;
  m.weighted := weighted;
  m.hasScaler := FALSE;
  m.scaler.numFeatures := m.numFeatures;
  m.scaler.fitted := FALSE
END Init;

PROCEDURE Train(VAR m: RegModel;
                data: ADDRESS; targets: ADDRESS;
                numSamples: CARDINAL; scale: BOOLEAN);
BEGIN
  m.trainData := data;
  m.trainTargets := targets;
  m.numTrain := numSamples;
  IF scale AND (numSamples > 0) THEN
    FitTransform(m.scaler, data, numSamples, m.numFeatures);
    m.hasScaler := TRUE
  ELSE
    m.hasScaler := FALSE
  END
END Train;

PROCEDURE Predict(VAR m: RegModel; sample: ADDRESS): LONGREAL;
VAR
  i, j: CARDINAL;
  dist, weight, totalWeight, result: LONGREAL;
  trainRow: ADDRESS;
  pTarget: RealPtr;
  scaledBuf: ARRAY [0..127] OF LONGREAL;
  sampleAddr: ADDRESS;
  pSrc: RealPtr;

  kDist: ARRAY [0..50] OF LONGREAL;
  kTarget: ARRAY [0..50] OF LONGREAL;
  kCount: CARDINAL;
  maxDist: LONGREAL;
  maxIdx: CARDINAL;
BEGIN
  IF (m.numTrain = 0) OR (m.trainData = NIL) THEN RETURN 0.0 END;

  (* Scale sample if needed *)
  IF m.hasScaler THEN
    FOR i := 0 TO m.numFeatures - 1 DO
      pSrc := ElemR(sample, i);
      IF m.scaler.stds[i] > 0.0 THEN
        scaledBuf[i] := (pSrc^ - m.scaler.means[i]) / m.scaler.stds[i]
      ELSE
        scaledBuf[i] := 0.0
      END
    END;
    sampleAddr := ADR(scaledBuf)
  ELSE
    sampleAddr := sample
  END;

  (* Find k nearest neighbors *)
  kCount := 0;
  FOR i := 0 TO m.numTrain - 1 DO
    trainRow := ADDRESS(LONGCARD(m.trainData)
                + LONGCARD(i) * LONGCARD(m.numFeatures) * LONGCARD(TSIZE(LONGREAL)));
    dist := EuclideanDist(sampleAddr, trainRow, m.numFeatures);

    pTarget := ElemR(m.trainTargets, i);

    IF kCount < m.k THEN
      kDist[kCount] := dist;
      kTarget[kCount] := pTarget^;
      INC(kCount)
    ELSE
      maxDist := kDist[0];
      maxIdx := 0;
      FOR j := 1 TO kCount - 1 DO
        IF kDist[j] > maxDist THEN
          maxDist := kDist[j];
          maxIdx := j
        END
      END;
      IF dist < maxDist THEN
        kDist[maxIdx] := dist;
        kTarget[maxIdx] := pTarget^
      END
    END
  END;

  (* Compute weighted/unweighted average *)
  result := 0.0;
  totalWeight := 0.0;
  FOR i := 0 TO kCount - 1 DO
    IF m.weighted THEN
      weight := 1.0 / (kDist[i] + Eps)
    ELSE
      weight := 1.0
    END;
    result := result + kTarget[i] * weight;
    totalWeight := totalWeight + weight
  END;

  IF totalWeight > 0.0 THEN
    RETURN result / totalWeight
  ELSE
    RETURN 0.0
  END
END Predict;

PROCEDURE PredictBatch(VAR m: RegModel;
                       data: ADDRESS; numSamples: CARDINAL;
                       predictions: ADDRESS);
VAR
  i: CARDINAL;
  row: ADDRESS;
  pPred: RealPtr;
BEGIN
  IF (numSamples = 0) OR (m.numTrain = 0) OR (m.trainData = NIL) THEN RETURN END;
  FOR i := 0 TO numSamples - 1 DO
    row := ADDRESS(LONGCARD(data)
           + LONGCARD(i) * LONGCARD(m.numFeatures) * LONGCARD(TSIZE(LONGREAL)));
    pPred := ElemR(predictions, i);
    pPred^ := Predict(m, row)
  END
END PredictBatch;

PROCEDURE MSE(VAR m: RegModel;
              data: ADDRESS; targets: ADDRESS;
              numSamples: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  row: ADDRESS;
  pred, actual, diff, sum: LONGREAL;
  pT: RealPtr;
BEGIN
  sum := 0.0;
  FOR i := 0 TO numSamples - 1 DO
    row := ADDRESS(LONGCARD(data)
           + LONGCARD(i) * LONGCARD(m.numFeatures) * LONGCARD(TSIZE(LONGREAL)));
    pred := Predict(m, row);
    pT := ElemR(targets, i);
    actual := pT^;
    diff := pred - actual;
    sum := sum + diff * diff
  END;
  IF numSamples > 0 THEN
    RETURN sum / LFLOAT(numSamples)
  ELSE
    RETURN 0.0
  END
END MSE;

END Regress.
