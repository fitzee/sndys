IMPLEMENTATION MODULE Harmonic;

FROM SYSTEM IMPORT ADDRESS, TSIZE;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE ComputeHarmonicF0(frame: ADDRESS; frameLen, sampleRate: CARDINAL;
                             VAR harmonicRatio: LONGREAL;
                             VAR f0: LONGREAL);
VAR
  lag, i: CARDINAL;
  minLag, maxLag: CARDINAL;
  autocorr0, autocorrLag, maxAutocorr: LONGREAL;
  bestLag: CARDINAL;
  pI, pILag: RealPtr;
BEGIN
  harmonicRatio := 0.0;
  f0 := 0.0;

  IF frameLen < 4 THEN RETURN END;

  (* Lag range: 50-500 Hz -> lag = sampleRate/freq *)
  maxLag := sampleRate DIV 50;   (* lowest freq = longest lag *)
  minLag := sampleRate DIV 500;  (* highest freq = shortest lag *)
  IF minLag < 2 THEN minLag := 2 END;
  IF maxLag >= frameLen THEN maxLag := frameLen - 1 END;
  IF minLag >= maxLag THEN RETURN END;

  (* Autocorrelation at lag 0 (energy) *)
  autocorr0 := 0.0;
  FOR i := 0 TO frameLen - 1 DO
    pI := Elem(frame, i);
    autocorr0 := autocorr0 + pI^ * pI^
  END;

  IF autocorr0 = 0.0 THEN RETURN END;

  (* Find lag with maximum autocorrelation *)
  maxAutocorr := -1.0;
  bestLag := minLag;

  FOR lag := minLag TO maxLag DO
    autocorrLag := 0.0;
    FOR i := 0 TO frameLen - lag - 1 DO
      pI := Elem(frame, i);
      pILag := Elem(frame, i + lag);
      autocorrLag := autocorrLag + pI^ * pILag^
    END;
    IF autocorrLag > maxAutocorr THEN
      maxAutocorr := autocorrLag;
      bestLag := lag
    END
  END;

  harmonicRatio := maxAutocorr / autocorr0;
  IF harmonicRatio < 0.0 THEN harmonicRatio := 0.0 END;
  IF harmonicRatio > 1.0 THEN harmonicRatio := 1.0 END;

  f0 := LFLOAT(sampleRate) / LFLOAT(bestLag)
END ComputeHarmonicF0;

END Harmonic.
