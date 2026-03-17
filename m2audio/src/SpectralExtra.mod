IMPLEMENTATION MODULE SpectralExtra;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathLib IMPORT sqrt, ln, exp;
FROM MathUtil IMPORT Log10, FAbs;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

(* ── SpectralFlatness ──────────────────────────────── *)

PROCEDURE SpectralFlatness(mag: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  sumLog, sumLin, val, geoMean, ariMean: LONGREAL;
  count: CARDINAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;

  sumLog := 0.0;
  sumLin := 0.0;
  count := 0;

  FOR i := 0 TO n - 1 DO
    p := Elem(mag, i);
    val := p^;
    IF val > 1.0D-20 THEN
      sumLog := sumLog + LFLOAT(ln(FLOAT(val)));
      sumLin := sumLin + val;
      INC(count)
    ELSE
      (* Treat near-zero as silence contribution *)
      sumLog := sumLog + LFLOAT(ln(FLOAT(1.0D-20)));
      sumLin := sumLin + 1.0D-20;
      INC(count)
    END
  END;

  IF count = 0 THEN RETURN 0.0 END;

  ariMean := sumLin / LFLOAT(count);
  IF ariMean < 1.0D-20 THEN RETURN 0.0 END;

  geoMean := LFLOAT(exp(FLOAT(sumLog / LFLOAT(count))));
  RETURN geoMean / ariMean
END SpectralFlatness;

(* ── SpectralBandwidth ─────────────────────────────── *)

PROCEDURE SpectralBandwidth(mag: ADDRESS; n: CARDINAL;
                             sampleRate: CARDINAL;
                             centroid: LONGREAL): LONGREAL;
VAR
  i: CARDINAL;
  freq, diff, sumWeighted, sumMag, val: LONGREAL;
  halfSr: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;

  halfSr := LFLOAT(sampleRate) / 2.0;
  sumWeighted := 0.0;
  sumMag := 0.0;

  FOR i := 0 TO n - 1 DO
    freq := LFLOAT(i) * halfSr / LFLOAT(n);
    p := Elem(mag, i);
    val := p^;
    diff := freq - centroid;
    sumWeighted := sumWeighted + diff * diff * val;
    sumMag := sumMag + val
  END;

  IF sumMag < 1.0D-20 THEN RETURN 0.0 END;
  RETURN LFLOAT(sqrt(FLOAT(sumWeighted / sumMag)))
END SpectralBandwidth;

(* ── SpectralSlope ─────────────────────────────────── *)

PROCEDURE SpectralSlope(mag: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  sumX, sumY, sumXY, sumXX: LONGREAL;
  x, y, nf, denom: LONGREAL;
  p: RealPtr;
BEGIN
  IF n < 2 THEN RETURN 0.0 END;

  sumX := 0.0;
  sumY := 0.0;
  sumXY := 0.0;
  sumXX := 0.0;
  nf := LFLOAT(n);

  FOR i := 0 TO n - 1 DO
    x := LFLOAT(i);
    p := Elem(mag, i);
    y := p^;
    sumX := sumX + x;
    sumY := sumY + y;
    sumXY := sumXY + x * y;
    sumXX := sumXX + x * x
  END;

  denom := nf * sumXX - sumX * sumX;
  IF FAbs(denom) < 1.0D-20 THEN RETURN 0.0 END;
  RETURN (nf * sumXY - sumX * sumY) / denom
END SpectralSlope;

(* ── SpectralContrast ──────────────────────────────── *)

(* Simple insertion sort for small arrays *)
PROCEDURE SortBuf(VAR a: ARRAY OF LONGREAL; n: CARDINAL);
VAR
  i, j: CARDINAL;
  tmp: LONGREAL;
BEGIN
  IF n < 2 THEN RETURN END;
  FOR i := 1 TO n - 1 DO
    tmp := a[i];
    j := i;
    WHILE (j > 0) AND (a[j - 1] > tmp) DO
      a[j] := a[j - 1];
      DEC(j)
    END;
    a[j] := tmp
  END
END SortBuf;

PROCEDURE SpectralContrast(mag: ADDRESS; n: CARDINAL;
                            numBands: CARDINAL;
                            VAR contrast: ARRAY OF LONGREAL);
CONST
  MaxBandSize = 4096;
VAR
  band, i, bandStart, bandEnd, bandLen: CARDINAL;
  topCount, botCount: CARDINAL;
  topMean, botMean, val: LONGREAL;
  bandBuf: ARRAY [0..4095] OF LONGREAL;
  p: RealPtr;
BEGIN
  IF (n = 0) OR (numBands = 0) THEN RETURN END;

  FOR band := 0 TO numBands - 1 DO
    bandStart := (band * n) DIV numBands;
    bandEnd := ((band + 1) * n) DIV numBands;
    IF bandEnd > n THEN bandEnd := n END;
    bandLen := bandEnd - bandStart;

    IF bandLen = 0 THEN
      IF band <= HIGH(contrast) THEN
        contrast[band] := 0.0
      END
    ELSE
      (* Copy band magnitudes into buffer *)
      IF bandLen > MaxBandSize THEN bandLen := MaxBandSize END;
      FOR i := 0 TO bandLen - 1 DO
        p := Elem(mag, bandStart + i);
        bandBuf[i] := p^
      END;

      SortBuf(bandBuf, bandLen);

      (* Top 20% mean *)
      topCount := bandLen DIV 5;
      IF topCount = 0 THEN topCount := 1 END;
      topMean := 0.0;
      FOR i := bandLen - topCount TO bandLen - 1 DO
        topMean := topMean + bandBuf[i]
      END;
      topMean := topMean / LFLOAT(topCount);

      (* Bottom 20% mean *)
      botCount := bandLen DIV 5;
      IF botCount = 0 THEN botCount := 1 END;
      botMean := 0.0;
      FOR i := 0 TO botCount - 1 DO
        botMean := botMean + bandBuf[i]
      END;
      botMean := botMean / LFLOAT(botCount);

      (* Convert to dB difference *)
      IF topMean < 1.0D-20 THEN topMean := 1.0D-20 END;
      IF botMean < 1.0D-20 THEN botMean := 1.0D-20 END;

      IF band <= HIGH(contrast) THEN
        contrast[band] := 10.0 * Log10(topMean) - 10.0 * Log10(botMean)
      END
    END
  END
END SpectralContrast;

END SpectralExtra.
