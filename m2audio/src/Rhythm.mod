IMPLEMENTATION MODULE Rhythm;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;
FROM MathUtil IMPORT NextPow2;
FROM FFT IMPORT Forward;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

(* ── TempoStability ────────────────────────────────── *)

PROCEDURE TempoStability(bpms: ADDRESS;
                          numPoints: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  sum, mean, diffSum, diff, variance, stdDev: LONGREAL;
  count: CARDINAL;
  p: RealPtr;
BEGIN
  IF numPoints < 2 THEN RETURN 0.0 END;

  (* Compute mean of non-zero BPM values *)
  sum := 0.0;
  count := 0;
  FOR i := 0 TO numPoints - 1 DO
    p := Elem(bpms, i);
    IF p^ > 0.0 THEN
      sum := sum + p^;
      INC(count)
    END
  END;

  IF count < 2 THEN RETURN 0.0 END;
  mean := sum / LFLOAT(count);
  IF mean < 1.0D-10 THEN RETURN 0.0 END;

  (* Compute standard deviation *)
  diffSum := 0.0;
  FOR i := 0 TO numPoints - 1 DO
    p := Elem(bpms, i);
    IF p^ > 0.0 THEN
      diff := p^ - mean;
      diffSum := diffSum + diff * diff
    END
  END;

  variance := diffSum / LFLOAT(count);
  stdDev := LFLOAT(sqrt(FLOAT(variance)));

  RETURN stdDev / mean
END TempoStability;

(* ── BeatStrength ──────────────────────────────────── *)

PROCEDURE BeatStrength(signal: ADDRESS;
                        numSamples, sampleRate: CARDINAL): LONGREAL;
CONST
  WinSize = 0.020;  (* 20ms analysis window *)
  WinStep = 0.005;  (* 5ms step *)
  MinBPM  = 60.0;
  MaxBPM  = 200.0;
VAR
  winSamp, stepSamp, fftSize, fftHalf: CARDINAL;
  numFrames, t, i: CARDINAL;
  complexBuf, prevSpec, flux: ADDRESS;
  pSrc, pDst, pRe, pIm, pF: RealPtr;
  re, im, mag, prevMag, diff, fVal: LONGREAL;
  lag: CARDINAL;
  minLag, maxLag: CARDINAL;
  acVal, maxAc, meanFlux: LONGREAL;
BEGIN
  IF numSamples < 2 THEN RETURN 0.0 END;

  winSamp := TRUNC(WinSize * LFLOAT(sampleRate));
  stepSamp := TRUNC(WinStep * LFLOAT(sampleRate));
  IF (winSamp = 0) OR (stepSamp = 0) OR (numSamples < winSamp) THEN
    RETURN 0.0
  END;

  fftSize := NextPow2(winSamp);
  fftHalf := fftSize DIV 2;
  numFrames := (numSamples - winSamp) DIV stepSamp + 1;
  IF numFrames < 4 THEN RETURN 0.0 END;

  ALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  ALLOCATE(prevSpec, fftHalf * TSIZE(LONGREAL));
  ALLOCATE(flux, numFrames * TSIZE(LONGREAL));

  (* Initialize prevSpec *)
  FOR i := 0 TO fftHalf - 1 DO
    pDst := Elem(prevSpec, i);
    pDst^ := 0.0
  END;

  (* Compute spectral flux *)
  FOR t := 0 TO numFrames - 1 DO
    FOR i := 0 TO fftSize - 1 DO
      pDst := Elem(complexBuf, 2 * i);
      IF i < winSamp THEN
        pSrc := Elem(signal, t * stepSamp + i);
        pDst^ := pSrc^
      ELSE
        pDst^ := 0.0
      END;
      pDst := Elem(complexBuf, 2 * i + 1);
      pDst^ := 0.0
    END;

    Forward(complexBuf, fftSize);

    fVal := 0.0;
    FOR i := 0 TO fftHalf - 1 DO
      pRe := Elem(complexBuf, 2 * i);
      pIm := Elem(complexBuf, 2 * i + 1);
      re := pRe^; im := pIm^;
      mag := LFLOAT(sqrt(FLOAT(re * re + im * im)));
      pSrc := Elem(prevSpec, i);
      prevMag := pSrc^;
      diff := mag - prevMag;
      IF diff > 0.0 THEN fVal := fVal + diff END;
      pSrc^ := mag
    END;

    pF := Elem(flux, t);
    pF^ := fVal
  END;

  DEALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  DEALLOCATE(prevSpec, fftHalf * TSIZE(LONGREAL));

  (* Mean spectral flux *)
  meanFlux := 0.0;
  FOR t := 0 TO numFrames - 1 DO
    pF := Elem(flux, t);
    meanFlux := meanFlux + pF^
  END;
  meanFlux := meanFlux / LFLOAT(numFrames);

  IF meanFlux < 1.0D-20 THEN
    DEALLOCATE(flux, numFrames * TSIZE(LONGREAL));
    RETURN 0.0
  END;

  (* Autocorrelation of flux to find beat period *)
  (* Lag range for BPM range *)
  (* lag (in frames) = 60 / (BPM * WinStep) *)
  minLag := TRUNC(60.0 / (MaxBPM * WinStep));
  maxLag := TRUNC(60.0 / (MinBPM * WinStep));
  IF minLag < 1 THEN minLag := 1 END;
  IF maxLag >= numFrames THEN maxLag := numFrames - 1 END;
  IF minLag >= maxLag THEN
    DEALLOCATE(flux, numFrames * TSIZE(LONGREAL));
    RETURN 0.0
  END;

  maxAc := 0.0;
  FOR lag := minLag TO maxLag DO
    acVal := 0.0;
    FOR t := 0 TO numFrames - lag - 1 DO
      pF := Elem(flux, t);
      pSrc := Elem(flux, t + lag);
      acVal := acVal + pF^ * pSrc^
    END;
    acVal := acVal / LFLOAT(numFrames - lag);
    IF acVal > maxAc THEN
      maxAc := acVal
    END
  END;

  DEALLOCATE(flux, numFrames * TSIZE(LONGREAL));

  (* Beat strength = peak autocorrelation / mean flux squared *)
  IF meanFlux * meanFlux < 1.0D-20 THEN RETURN 0.0 END;
  RETURN maxAc / (meanFlux * meanFlux)
END BeatStrength;

END Rhythm.
