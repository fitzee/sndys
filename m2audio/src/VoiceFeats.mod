IMPLEMENTATION MODULE VoiceFeats;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt, sin, cos;
FROM MathUtil IMPORT Pi, Log10, FAbs;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

(* ── Levinson-Durbin recursion ─────────────────────── *)

PROCEDURE LevinsonDurbin(VAR r: ARRAY OF LONGREAL;
                          order: CARDINAL;
                          VAR a: ARRAY OF LONGREAL): BOOLEAN;
VAR
  i, j: CARDINAL;
  err, lambda: LONGREAL;
  prev: ARRAY [0..31] OF LONGREAL;
BEGIN
  IF r[0] = 0.0 THEN RETURN FALSE END;

  err := r[0];

  FOR i := 1 TO order DO
    lambda := 0.0;
    FOR j := 1 TO i - 1 DO
      lambda := lambda + a[j] * r[i - j]
    END;
    lambda := -(r[i] + lambda) / err;

    FOR j := 1 TO i - 1 DO
      prev[j] := a[j]
    END;

    FOR j := 1 TO i - 1 DO
      a[j] := prev[j] + lambda * prev[i - j]
    END;
    a[i] := lambda;

    err := err * (1.0 - lambda * lambda);
    IF err <= 0.0 THEN RETURN FALSE END
  END;

  RETURN TRUE
END LevinsonDurbin;

(* ── ComputeFormants ───────────────────────────────── *)

PROCEDURE ComputeFormants(frame: ADDRESS;
                           frameLen, sampleRate: CARDINAL;
                           VAR f1, f2, f3: LONGREAL);
CONST
  LpcOrder = 12;
  EvalPoints = 512;
VAR
  i, k: CARDINAL;
  j: CARDINAL;
  autoCorr: ARRAY [0..12] OF LONGREAL;
  lpcCoeffs: ARRAY [0..12] OF LONGREAL;
  mags: ARRAY [0..511] OF LONGREAL;
  p1, p2: RealPtr;
  sum, re, im, angle, mag, freq: LONGREAL;
  formants: ARRAY [0..11] OF LONGREAL;
  numFormants: CARDINAL;
  ok: BOOLEAN;
  halfSr: LONGREAL;
BEGIN
  f1 := 0.0;
  f2 := 0.0;
  f3 := 0.0;

  IF frameLen < LpcOrder + 1 THEN RETURN END;

  halfSr := LFLOAT(sampleRate) / 2.0;

  (* Compute autocorrelation *)
  FOR i := 0 TO LpcOrder DO
    sum := 0.0;
    FOR j := 0 TO frameLen - i - 1 DO
      p1 := Elem(frame, j);
      p2 := Elem(frame, j + i);
      sum := sum + p1^ * p2^
    END;
    autoCorr[i] := sum
  END;

  IF autoCorr[0] = 0.0 THEN RETURN END;

  (* Initialize LPC coefficients *)
  FOR i := 0 TO LpcOrder DO lpcCoeffs[i] := 0.0 END;

  ok := LevinsonDurbin(autoCorr, LpcOrder, lpcCoeffs);
  IF NOT ok THEN RETURN END;

  (* Evaluate |1/A(z)|^2 on the unit circle *)
  FOR i := 0 TO EvalPoints - 1 DO
    angle := LFLOAT(i) * Pi / LFLOAT(EvalPoints);
    re := 1.0;
    im := 0.0;
    FOR k := 1 TO LpcOrder DO
      re := re + lpcCoeffs[k] * LFLOAT(cos(FLOAT(LFLOAT(k) * angle)));
      im := im - lpcCoeffs[k] * LFLOAT(sin(FLOAT(LFLOAT(k) * angle)))
    END;
    mag := re * re + im * im;
    IF mag < 1.0D-20 THEN mag := 1.0D-20 END;
    mags[i] := 1.0 / mag
  END;

  (* Find peaks in the LPC envelope *)
  numFormants := 0;
  FOR i := 1 TO EvalPoints - 2 DO
    IF (mags[i] > mags[i - 1]) AND (mags[i] > mags[i + 1]) THEN
      freq := LFLOAT(i) * halfSr / LFLOAT(EvalPoints);
      IF (freq > 90.0) AND (freq < halfSr) AND (numFormants < 12) THEN
        formants[numFormants] := freq;
        INC(numFormants)
      END
    END
  END;

  IF numFormants >= 1 THEN f1 := formants[0] END;
  IF numFormants >= 2 THEN f2 := formants[1] END;
  IF numFormants >= 3 THEN f3 := formants[2] END
END ComputeFormants;

(* ── ComputeJitter ─────────────────────────────────── *)

PROCEDURE ComputeJitter(pitches: ADDRESS;
                         numFrames: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  p: RealPtr;
  f0, period: LONGREAL;
  periods: ADDRESS;
  numPeriods: CARDINAL;
  sumPeriod, sumDiff, meanPeriod: LONGREAL;
  pCur, pPrev: RealPtr;
BEGIN
  IF numFrames < 2 THEN RETURN 0.0 END;

  ALLOCATE(periods, numFrames * TSIZE(LONGREAL));
  numPeriods := 0;

  FOR i := 0 TO numFrames - 1 DO
    p := Elem(pitches, i);
    f0 := p^;
    IF f0 > 0.0 THEN
      period := 1.0 / f0;
      pCur := Elem(periods, numPeriods);
      pCur^ := period;
      INC(numPeriods)
    END
  END;

  IF numPeriods < 2 THEN
    DEALLOCATE(periods, 0);
    RETURN 0.0
  END;

  sumPeriod := 0.0;
  FOR i := 0 TO numPeriods - 1 DO
    pCur := Elem(periods, i);
    sumPeriod := sumPeriod + pCur^
  END;
  meanPeriod := sumPeriod / LFLOAT(numPeriods);

  IF meanPeriod < 1.0D-20 THEN
    DEALLOCATE(periods, 0);
    RETURN 0.0
  END;

  sumDiff := 0.0;
  FOR i := 1 TO numPeriods - 1 DO
    pCur := Elem(periods, i);
    pPrev := Elem(periods, i - 1);
    sumDiff := sumDiff + FAbs(pCur^ - pPrev^)
  END;

  DEALLOCATE(periods, 0);
  RETURN (sumDiff / LFLOAT(numPeriods - 1)) / meanPeriod
END ComputeJitter;

(* ── ComputeShimmer ────────────────────────────────── *)

PROCEDURE ComputeShimmer(signal: ADDRESS;
                          numSamples, sampleRate: CARDINAL;
                          pitches: ADDRESS;
                          numFrames: CARDINAL): LONGREAL;
VAR
  i, j: CARDINAL;
  p: RealPtr;
  f0, period: LONGREAL;
  cycleSamp, cycleStart, cycleEnd: CARDINAL;
  amp, maxVal: LONGREAL;
  amps: ADDRESS;
  numAmps: CARDINAL;
  sumAmp, sumDiff, meanAmp: LONGREAL;
  pCur, pPrev, pS: RealPtr;
  stepSamp: CARDINAL;
BEGIN
  IF (numFrames < 2) OR (numSamples < 2) THEN RETURN 0.0 END;

  stepSamp := sampleRate DIV 100;
  IF stepSamp = 0 THEN stepSamp := 1 END;

  ALLOCATE(amps, numFrames * TSIZE(LONGREAL));
  numAmps := 0;

  FOR i := 0 TO numFrames - 1 DO
    p := Elem(pitches, i);
    f0 := p^;
    IF f0 > 0.0 THEN
      period := 1.0 / f0;
      cycleSamp := TRUNC(period * LFLOAT(sampleRate));
      IF cycleSamp = 0 THEN cycleSamp := 1 END;

      cycleStart := i * stepSamp;
      cycleEnd := cycleStart + cycleSamp;
      IF cycleEnd > numSamples THEN cycleEnd := numSamples END;

      maxVal := 0.0;
      FOR j := cycleStart TO cycleEnd - 1 DO
        pS := Elem(signal, j);
        amp := FAbs(pS^);
        IF amp > maxVal THEN maxVal := amp END
      END;

      pCur := Elem(amps, numAmps);
      pCur^ := maxVal;
      INC(numAmps)
    END
  END;

  IF numAmps < 2 THEN
    DEALLOCATE(amps, 0);
    RETURN 0.0
  END;

  sumAmp := 0.0;
  FOR i := 0 TO numAmps - 1 DO
    pCur := Elem(amps, i);
    sumAmp := sumAmp + pCur^
  END;
  meanAmp := sumAmp / LFLOAT(numAmps);

  IF meanAmp < 1.0D-20 THEN
    DEALLOCATE(amps, 0);
    RETURN 0.0
  END;

  sumDiff := 0.0;
  FOR i := 1 TO numAmps - 1 DO
    pCur := Elem(amps, i);
    pPrev := Elem(amps, i - 1);
    sumDiff := sumDiff + FAbs(pCur^ - pPrev^)
  END;

  DEALLOCATE(amps, 0);
  RETURN (sumDiff / LFLOAT(numAmps - 1)) / meanAmp
END ComputeShimmer;

(* ── ComputeHNR ────────────────────────────────────── *)

PROCEDURE ComputeHNR(signal: ADDRESS;
                      numSamples, sampleRate: CARDINAL): LONGREAL;
VAR
  i, lag: CARDINAL;
  minLag, maxLag: CARDINAL;
  r0, rLag, rPeak: LONGREAL;
  p1, p2: RealPtr;
  denom: LONGREAL;
BEGIN
  IF numSamples < 4 THEN RETURN 0.0 END;

  maxLag := sampleRate DIV 50;
  minLag := sampleRate DIV 500;
  IF minLag < 2 THEN minLag := 2 END;
  IF maxLag >= numSamples THEN maxLag := numSamples - 1 END;
  IF minLag >= maxLag THEN RETURN 0.0 END;

  r0 := 0.0;
  FOR i := 0 TO numSamples - 1 DO
    p1 := Elem(signal, i);
    r0 := r0 + p1^ * p1^
  END;

  IF r0 = 0.0 THEN RETURN 0.0 END;

  rPeak := -1.0;
  FOR lag := minLag TO maxLag DO
    rLag := 0.0;
    FOR i := 0 TO numSamples - lag - 1 DO
      p1 := Elem(signal, i);
      p2 := Elem(signal, i + lag);
      rLag := rLag + p1^ * p2^
    END;
    IF rLag > rPeak THEN
      rPeak := rLag
    END
  END;

  IF rPeak <= 0.0 THEN RETURN 0.0 END;

  denom := r0 - rPeak;
  IF denom <= 0.0 THEN RETURN 40.0 END;

  RETURN 10.0 * Log10(rPeak / denom)
END ComputeHNR;

END VoiceFeats.
