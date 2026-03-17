IMPLEMENTATION MODULE Spectro;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;
FROM MathUtil IMPORT NextPow2, Log2;
FROM FFT IMPORT Forward;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE ComputeSpectrogram(signal: ADDRESS;
                              numSamples, sampleRate: CARDINAL;
                              winSizeSec, winStepSec: LONGREAL;
                              VAR output: ADDRESS;
                              VAR numFrames, numBins: CARDINAL);
VAR
  winSamp, stepSamp, fftSize: CARDINAL;
  totalFrames, frameStart, i, t: CARDINAL;
  complexBuf: ADDRESS;
  pSrc, pDst, pRe, pIm: RealPtr;
  re, im: LONGREAL;
BEGIN
  output := NIL;
  numFrames := 0;
  numBins := 0;

  winSamp := TRUNC(winSizeSec * LFLOAT(sampleRate));
  stepSamp := TRUNC(winStepSec * LFLOAT(sampleRate));
  IF (winSamp = 0) OR (stepSamp = 0) OR (numSamples < winSamp) THEN RETURN END;

  fftSize := NextPow2(winSamp);
  numBins := fftSize DIV 2;
  totalFrames := (numSamples - winSamp) DIV stepSamp + 1;
  IF totalFrames = 0 THEN RETURN END;

  ALLOCATE(output, totalFrames * numBins * TSIZE(LONGREAL));
  ALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));

  FOR t := 0 TO totalFrames - 1 DO
    frameStart := t * stepSamp;

    (* Pack frame into complex buffer with zero-padding *)
    FOR i := 0 TO fftSize - 1 DO
      pDst := Elem(complexBuf, 2 * i);
      IF i < winSamp THEN
        pSrc := Elem(signal, frameStart + i);
        pDst^ := pSrc^
      ELSE
        pDst^ := 0.0
      END;
      pDst := Elem(complexBuf, 2 * i + 1);
      pDst^ := 0.0
    END;

    Forward(complexBuf, fftSize);

    (* Magnitude of first half *)
    FOR i := 0 TO numBins - 1 DO
      pRe := Elem(complexBuf, 2 * i);
      pIm := Elem(complexBuf, 2 * i + 1);
      re := pRe^;
      im := pIm^;
      pDst := Elem(output, t * numBins + i);
      pDst^ := LFLOAT(sqrt(FLOAT(re * re + im * im)))
    END
  END;

  numFrames := totalFrames;
  DEALLOCATE(complexBuf, 0)
END ComputeSpectrogram;

PROCEDURE ComputeChromagram(signal: ADDRESS;
                             numSamples, sampleRate: CARDINAL;
                             winSizeSec, winStepSec: LONGREAL;
                             VAR output: ADDRESS;
                             VAR numFrames: CARDINAL);
VAR
  winSamp, stepSamp, fftSize, numBins: CARDINAL;
  totalFrames, frameStart, i, t, pitchClass: CARDINAL;
  complexBuf: ADDRESS;
  pSrc, pDst, pRe, pIm: RealPtr;
  re, im, mag, freq, semitone, total: LONGREAL;
  chroma: ARRAY [0..11] OF LONGREAL;
  halfSr: LONGREAL;
BEGIN
  output := NIL;
  numFrames := 0;

  winSamp := TRUNC(winSizeSec * LFLOAT(sampleRate));
  stepSamp := TRUNC(winStepSec * LFLOAT(sampleRate));
  IF (winSamp = 0) OR (stepSamp = 0) OR (numSamples < winSamp) THEN RETURN END;

  fftSize := NextPow2(winSamp);
  numBins := fftSize DIV 2;
  totalFrames := (numSamples - winSamp) DIV stepSamp + 1;
  IF totalFrames = 0 THEN RETURN END;

  halfSr := LFLOAT(sampleRate) / 2.0;

  ALLOCATE(output, totalFrames * 12 * TSIZE(LONGREAL));
  ALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));

  FOR t := 0 TO totalFrames - 1 DO
    frameStart := t * stepSamp;

    FOR i := 0 TO fftSize - 1 DO
      pDst := Elem(complexBuf, 2 * i);
      IF i < winSamp THEN
        pSrc := Elem(signal, frameStart + i);
        pDst^ := pSrc^
      ELSE
        pDst^ := 0.0
      END;
      pDst := Elem(complexBuf, 2 * i + 1);
      pDst^ := 0.0
    END;

    Forward(complexBuf, fftSize);

    (* Map FFT bins to 12 pitch classes *)
    FOR i := 0 TO 11 DO chroma[i] := 0.0 END;
    total := 0.0;

    FOR i := 1 TO numBins - 1 DO
      pRe := Elem(complexBuf, 2 * i);
      pIm := Elem(complexBuf, 2 * i + 1);
      re := pRe^;
      im := pIm^;
      mag := re * re + im * im;
      total := total + mag;

      freq := LFLOAT(i) * halfSr / LFLOAT(numBins);
      IF freq > 27.5 THEN
        semitone := 12.0 * Log2(freq / 27.5);
        IF semitone >= 0.0 THEN
          pitchClass := TRUNC(semitone + 0.5) MOD 12
        ELSE
          pitchClass := 0
        END;
        chroma[pitchClass] := chroma[pitchClass] + mag
      END
    END;

    (* Normalize *)
    IF total > 0.0 THEN
      FOR i := 0 TO 11 DO
        pDst := Elem(output, t * 12 + i);
        pDst^ := chroma[i] / total
      END
    ELSE
      FOR i := 0 TO 11 DO
        pDst := Elem(output, t * 12 + i);
        pDst^ := 0.0
      END
    END
  END;

  numFrames := totalFrames;
  DEALLOCATE(complexBuf, 0)
END ComputeChromagram;

PROCEDURE FreeSpectro(VAR output: ADDRESS);
BEGIN
  IF output # NIL THEN
    DEALLOCATE(output, 0);
    output := NIL
  END
END FreeSpectro;

END Spectro.
