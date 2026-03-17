IMPLEMENTATION MODULE AudioStats;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathLib IMPORT sqrt, ln;
FROM MathUtil IMPORT FAbs;

CONST
  Ln10 = 2.30258509299404568402D0;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE Analyze(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  VAR result: StatsResult);
VAR
  i: CARDINAL;
  sum, sumSq, val, absVal: LONGREAL;
  p: RealPtr;
BEGIN
  result.numSamples := numSamples;
  IF sampleRate > 0 THEN
    result.duration := LFLOAT(numSamples) / LFLOAT(sampleRate)
  ELSE
    result.duration := 0.0
  END;

  IF numSamples = 0 THEN
    result.rmsLevel := 0.0;
    result.peakLevel := 0.0;
    result.crestFactor := 0.0;
    result.dcOffset := 0.0;
    result.rmsDB := -100.0;
    result.peakDB := -100.0;
    result.numClipped := 0;
    RETURN
  END;

  sum := 0.0;
  sumSq := 0.0;
  result.peakLevel := 0.0;
  result.numClipped := 0;

  FOR i := 0 TO numSamples - 1 DO
    p := Elem(signal, i);
    val := p^;
    absVal := FAbs(val);
    sum := sum + val;
    sumSq := sumSq + val * val;
    IF absVal > result.peakLevel THEN result.peakLevel := absVal END;
    IF absVal >= 0.99 THEN INC(result.numClipped) END
  END;

  result.dcOffset := sum / LFLOAT(numSamples);
  result.rmsLevel := LFLOAT(sqrt(FLOAT(sumSq / LFLOAT(numSamples))));

  (* dBFS = 20 * log10(level), where 1.0 = 0 dBFS *)
  IF result.rmsLevel > 1.0D-10 THEN
    result.rmsDB := 20.0 * LFLOAT(ln(FLOAT(result.rmsLevel))) / Ln10
  ELSE
    result.rmsDB := -100.0
  END;

  IF result.peakLevel > 1.0D-10 THEN
    result.peakDB := 20.0 * LFLOAT(ln(FLOAT(result.peakLevel))) / Ln10
  ELSE
    result.peakDB := -100.0
  END;

  (* Crest factor in dB = peak dB - RMS dB *)
  result.crestFactor := result.peakDB - result.rmsDB
END Analyze;

END AudioStats.
