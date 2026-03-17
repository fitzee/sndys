IMPLEMENTATION MODULE Onset;
(* Onset detection via spectral flux peak picking.
   1. Compute magnitude spectrogram (radix-2 FFT)
   2. Compute spectral flux (half-wave rectified frame-to-frame diff)
   3. Adaptive threshold: local mean + sensitivity * local std
   4. Peak pick above threshold *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;
FROM MathUtil IMPORT NextPow2, FAbs;
FROM FFT IMPORT Forward;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE DetectOnsets(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                       sensitivity: LONGREAL;
                       VAR onsets: ARRAY OF LONGREAL;
                       VAR numOnsets: CARDINAL);
CONST
  WinSize = 0.020;  (* 20ms for onset detection — shorter than features *)
  WinStep = 0.005;  (* 5ms step for fine resolution *)
  MedWin  = 10;     (* median window for adaptive threshold *)
VAR
  winSamp, stepSamp, fftSize, fftHalf: CARDINAL;
  numFrames, t, i, j: CARDINAL;
  complexBuf: ADDRESS;
  flux: ADDRESS;     (* numFrames LONGREALs *)
  pSrc, pDst, pRe, pIm, pF: RealPtr;
  re, im, mag, prevMag, diff, fVal: LONGREAL;
  prevSpec: ADDRESS;  (* fftHalf LONGREALs *)

  (* Adaptive threshold *)
  localMean, localStd, thresh, d: LONGREAL;
  wStart, wEnd, wCount: CARDINAL;
BEGIN
  numOnsets := 0;

  winSamp := TRUNC(WinSize * LFLOAT(sampleRate));
  stepSamp := TRUNC(WinStep * LFLOAT(sampleRate));
  IF (winSamp = 0) OR (stepSamp = 0) OR (numSamples < winSamp) THEN RETURN END;

  fftSize := NextPow2(winSamp);
  fftHalf := fftSize DIV 2;
  numFrames := (numSamples - winSamp) DIV stepSamp + 1;
  IF numFrames < 3 THEN RETURN END;

  ALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  ALLOCATE(prevSpec, fftHalf * TSIZE(LONGREAL));
  ALLOCATE(flux, numFrames * TSIZE(LONGREAL));

  (* Initialize prevSpec to zero *)
  FOR i := 0 TO fftHalf - 1 DO
    pDst := Elem(prevSpec, i);
    pDst^ := 0.0
  END;

  (* Compute spectral flux for each frame *)
  FOR t := 0 TO numFrames - 1 DO
    (* Pack frame *)
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

    (* Half-wave rectified spectral flux *)
    fVal := 0.0;
    FOR i := 0 TO fftHalf - 1 DO
      pRe := Elem(complexBuf, 2 * i);
      pIm := Elem(complexBuf, 2 * i + 1);
      re := pRe^; im := pIm^;
      mag := LFLOAT(sqrt(FLOAT(re * re + im * im)));
      pSrc := Elem(prevSpec, i);
      prevMag := pSrc^;
      diff := mag - prevMag;
      IF diff > 0.0 THEN
        fVal := fVal + diff
      END;
      pSrc^ := mag  (* update prev *)
    END;

    pF := Elem(flux, t);
    pF^ := fVal
  END;

  DEALLOCATE(complexBuf, 0);
  DEALLOCATE(prevSpec, 0);

  (* Peak pick with adaptive threshold *)
  FOR t := 1 TO numFrames - 2 DO
    pF := Elem(flux, t);
    fVal := pF^;

    (* Local mean and std in a window around t *)
    IF t >= MedWin THEN wStart := t - MedWin ELSE wStart := 0 END;
    wEnd := t + MedWin;
    IF wEnd >= numFrames THEN wEnd := numFrames - 1 END;

    localMean := 0.0;
    wCount := 0;
    FOR j := wStart TO wEnd DO
      pSrc := Elem(flux, j);
      localMean := localMean + pSrc^;
      INC(wCount)
    END;
    localMean := localMean / LFLOAT(wCount);

    localStd := 0.0;
    FOR j := wStart TO wEnd DO
      pSrc := Elem(flux, j);
      d := pSrc^ - localMean;
      localStd := localStd + d * d
    END;
    localStd := LFLOAT(sqrt(FLOAT(localStd / LFLOAT(wCount))));

    thresh := localMean + sensitivity * localStd;

    (* Peak: flux[t] > threshold AND flux[t] > flux[t-1] AND flux[t] >= flux[t+1] *)
    IF fVal > thresh THEN
      pSrc := Elem(flux, t - 1);
      pDst := Elem(flux, t + 1);
      IF (fVal > pSrc^) AND (fVal >= pDst^) THEN
        IF numOnsets <= HIGH(onsets) THEN
          onsets[numOnsets] := LFLOAT(t) * WinStep;
          INC(numOnsets)
        END
      END
    END
  END;

  DEALLOCATE(flux, 0)
END DetectOnsets;

END Onset.
