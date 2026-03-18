IMPLEMENTATION MODULE Scaler;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathLib IMPORT sqrt;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

PROCEDURE Init(VAR sc: ScalerState; nFeatures: CARDINAL);
VAR j: CARDINAL;
BEGIN
  IF nFeatures > MaxFeatures THEN
    sc.numFeatures := MaxFeatures
  ELSE
    sc.numFeatures := nFeatures
  END;
  IF sc.numFeatures > 0 THEN
    FOR j := 0 TO sc.numFeatures - 1 DO
      sc.means[j] := 0.0;
      sc.stds[j] := 1.0
    END
  END;
  sc.fitted := FALSE
END Init;

PROCEDURE Fit(VAR sc: ScalerState;
              data: ADDRESS; numSamples, numFeatures: CARDINAL);
VAR
  i, j, nf: CARDINAL;
  sum, sumSq, m, v: LONGREAL;
  p: RealPtr;
BEGIN
  nf := numFeatures;
  IF nf > MaxFeatures THEN nf := MaxFeatures END;
  sc.numFeatures := nf;

  IF numSamples = 0 THEN
    sc.fitted := TRUE;
    RETURN
  END;

  FOR j := 0 TO nf - 1 DO
    sum := 0.0;
    sumSq := 0.0;
    FOR i := 0 TO numSamples - 1 DO
      p := Elem(data, i * numFeatures + j);
      sum := sum + p^;
      sumSq := sumSq + p^ * p^
    END;
    m := sum / LFLOAT(numSamples);
    v := sumSq / LFLOAT(numSamples) - m * m;
    sc.means[j] := m;
    IF v > 0.0 THEN
      sc.stds[j] := LFLOAT(sqrt(FLOAT(v)))
    ELSE
      sc.stds[j] := 1.0  (* avoid division by zero *)
    END
  END;
  sc.fitted := TRUE
END Fit;

PROCEDURE Transform(VAR sc: ScalerState;
                    data: ADDRESS; numSamples, numFeatures: CARDINAL);
VAR
  i, j, nf: CARDINAL;
  p: RealPtr;
BEGIN
  IF NOT sc.fitted THEN RETURN END;
  nf := sc.numFeatures;
  FOR i := 0 TO numSamples - 1 DO
    FOR j := 0 TO nf - 1 DO
      p := Elem(data, i * numFeatures + j);
      IF sc.stds[j] > 0.0 THEN
        p^ := (p^ - sc.means[j]) / sc.stds[j]
      ELSE
        p^ := 0.0
      END
    END
  END
END Transform;

PROCEDURE FitTransform(VAR sc: ScalerState;
                       data: ADDRESS; numSamples, numFeatures: CARDINAL);
BEGIN
  Fit(sc, data, numSamples, numFeatures);
  Transform(sc, data, numSamples, numFeatures)
END FitTransform;

PROCEDURE InverseTransform(VAR sc: ScalerState;
                           data: ADDRESS;
                           numSamples, numFeatures: CARDINAL);
VAR
  i, j, nf: CARDINAL;
  p: RealPtr;
BEGIN
  IF NOT sc.fitted THEN RETURN END;
  nf := sc.numFeatures;
  FOR i := 0 TO numSamples - 1 DO
    FOR j := 0 TO nf - 1 DO
      p := Elem(data, i * numFeatures + j);
      p^ := p^ * sc.stds[j] + sc.means[j]
    END
  END
END InverseTransform;

END Scaler.
