IMPLEMENTATION MODULE AudioProc;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt, sin;
FROM MathUtil IMPORT Pi, TwoPi, FAbs;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

PROCEDURE Trim(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
               startSec, endSec: LONGREAL;
               VAR output: ADDRESS; VAR outSamples: CARDINAL);
VAR
  startIdx, endIdx, i: CARDINAL;
  pSrc, pDst: RealPtr;
BEGIN
  IF numSamples = 0 THEN
    output := NIL; outSamples := 0; RETURN
  END;
  IF startSec < 0.0 THEN startSec := 0.0 END;
  IF endSec < 0.0 THEN endSec := 0.0 END;
  startIdx := TRUNC(startSec * LFLOAT(sampleRate));
  endIdx := TRUNC(endSec * LFLOAT(sampleRate));
  IF startIdx >= numSamples THEN
    output := NIL; outSamples := 0; RETURN
  END;
  IF endIdx > numSamples THEN endIdx := numSamples END;
  IF endIdx <= startIdx THEN
    output := NIL; outSamples := 0; RETURN
  END;

  outSamples := endIdx - startIdx;
  ALLOCATE(output, outSamples * TSIZE(LONGREAL));
  FOR i := 0 TO outSamples - 1 DO
    pSrc := Elem(signal, startIdx + i);
    pDst := Elem(output, i);
    pDst^ := pSrc^
  END
END Trim;

PROCEDURE Mix(signalA: ADDRESS; numA: CARDINAL;
              signalB: ADDRESS; numB: CARDINAL;
              mixRatio: LONGREAL;
              VAR output: ADDRESS; VAR outSamples: CARDINAL);
VAR
  i: CARDINAL;
  valA, valB: LONGREAL;
  pA, pB, pOut: RealPtr;
BEGIN
  IF numA > numB THEN outSamples := numA
  ELSE outSamples := numB END;

  ALLOCATE(output, outSamples * TSIZE(LONGREAL));
  FOR i := 0 TO outSamples - 1 DO
    IF i < numA THEN
      pA := Elem(signalA, i); valA := pA^
    ELSE valA := 0.0 END;
    IF i < numB THEN
      pB := Elem(signalB, i); valB := pB^
    ELSE valB := 0.0 END;
    pOut := Elem(output, i);
    pOut^ := valA * (1.0 - mixRatio) + valB * mixRatio
  END
END Mix;

PROCEDURE Normalize(signal: ADDRESS; numSamples: CARDINAL;
                    targetPeak: LONGREAL);
VAR
  i: CARDINAL;
  maxAbs, val, scale: LONGREAL;
  p: RealPtr;
BEGIN
  IF numSamples = 0 THEN RETURN END;
  maxAbs := 0.0;
  FOR i := 0 TO numSamples - 1 DO
    p := Elem(signal, i);
    val := FAbs(p^);
    IF val > maxAbs THEN maxAbs := val END
  END;
  IF maxAbs < 1.0D-10 THEN RETURN END;
  scale := targetPeak / maxAbs;
  FOR i := 0 TO numSamples - 1 DO
    p := Elem(signal, i);
    p^ := p^ * scale
  END
END Normalize;

PROCEDURE NormalizeRMS(signal: ADDRESS; numSamples: CARDINAL;
                       targetRMS: LONGREAL);
VAR
  i: CARDINAL;
  sum, rms, scale: LONGREAL;
  p: RealPtr;
BEGIN
  IF numSamples = 0 THEN RETURN END;
  sum := 0.0;
  FOR i := 0 TO numSamples - 1 DO
    p := Elem(signal, i);
    sum := sum + p^ * p^
  END;
  rms := LFLOAT(sqrt(FLOAT(sum / LFLOAT(numSamples))));
  IF rms < 1.0D-10 THEN RETURN END;
  scale := targetRMS / rms;
  FOR i := 0 TO numSamples - 1 DO
    p := Elem(signal, i);
    p^ := p^ * scale
  END
END NormalizeRMS;

PROCEDURE FadeIn(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                 fadeSec: LONGREAL);
VAR
  i, fadeSamples: CARDINAL;
  p: RealPtr;
BEGIN
  IF numSamples = 0 THEN RETURN END;
  IF fadeSec <= 0.0 THEN RETURN END;
  fadeSamples := TRUNC(fadeSec * LFLOAT(sampleRate));
  IF fadeSamples = 0 THEN RETURN END;
  IF fadeSamples > numSamples THEN fadeSamples := numSamples END;
  FOR i := 0 TO fadeSamples - 1 DO
    p := Elem(signal, i);
    p^ := p^ * LFLOAT(i) / LFLOAT(fadeSamples)
  END
END FadeIn;

PROCEDURE FadeOut(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  fadeSec: LONGREAL);
VAR
  i, fadeSamples, startIdx: CARDINAL;
  p: RealPtr;
BEGIN
  IF numSamples = 0 THEN RETURN END;
  IF fadeSec <= 0.0 THEN RETURN END;
  fadeSamples := TRUNC(fadeSec * LFLOAT(sampleRate));
  IF fadeSamples = 0 THEN RETURN END;
  IF fadeSamples > numSamples THEN fadeSamples := numSamples END;
  startIdx := numSamples - fadeSamples;
  FOR i := 0 TO fadeSamples - 1 DO
    p := Elem(signal, startIdx + i);
    p^ := p^ * LFLOAT(fadeSamples - i) / LFLOAT(fadeSamples)
  END
END FadeOut;

PROCEDURE Reverse(signal: ADDRESS; numSamples: CARDINAL);
VAR
  i, j: CARDINAL;
  tmp: LONGREAL;
  pI, pJ: RealPtr;
BEGIN
  IF numSamples = 0 THEN RETURN END;
  IF numSamples < 2 THEN RETURN END;
  i := 0;
  j := numSamples - 1;
  WHILE i < j DO
    pI := Elem(signal, i);
    pJ := Elem(signal, j);
    tmp := pI^;
    pI^ := pJ^;
    pJ^ := tmp;
    INC(i);
    DEC(j)
  END
END Reverse;

PROCEDURE GenerateSine(freq: LONGREAL; durationSec: LONGREAL;
                       sampleRate: CARDINAL; amplitude: LONGREAL;
                       VAR output: ADDRESS; VAR outSamples: CARDINAL);
VAR
  i: CARDINAL; p: RealPtr; phase: LONGREAL;
BEGIN
  IF durationSec <= 0.0 THEN output := NIL; outSamples := 0; RETURN END;
  outSamples := TRUNC(durationSec * LFLOAT(sampleRate));
  IF outSamples = 0 THEN output := NIL; RETURN END;
  ALLOCATE(output, outSamples * TSIZE(LONGREAL));
  FOR i := 0 TO outSamples - 1 DO
    phase := TwoPi * freq * LFLOAT(i) / LFLOAT(sampleRate);
    p := Elem(output, i);
    p^ := amplitude * LFLOAT(sin(FLOAT(phase)))
  END
END GenerateSine;

PROCEDURE GenerateChirp(startFreq, endFreq, durationSec: LONGREAL;
                        sampleRate: CARDINAL; amplitude: LONGREAL;
                        VAR output: ADDRESS; VAR outSamples: CARDINAL);
VAR
  i: CARDINAL; p: RealPtr;
  t, freq, phase: LONGREAL;
BEGIN
  IF durationSec <= 0.0 THEN output := NIL; outSamples := 0; RETURN END;
  outSamples := TRUNC(durationSec * LFLOAT(sampleRate));
  IF outSamples = 0 THEN output := NIL; RETURN END;
  ALLOCATE(output, outSamples * TSIZE(LONGREAL));
  FOR i := 0 TO outSamples - 1 DO
    t := LFLOAT(i) / LFLOAT(sampleRate);
    freq := startFreq + (endFreq - startFreq) * t / durationSec;
    phase := TwoPi * freq * t;
    p := Elem(output, i);
    p^ := amplitude * LFLOAT(sin(FLOAT(phase)))
  END
END GenerateChirp;

PROCEDURE GenerateNoise(durationSec: LONGREAL;
                        sampleRate: CARDINAL; amplitude: LONGREAL;
                        VAR output: ADDRESS; VAR outSamples: CARDINAL);
VAR
  i: CARDINAL; p: RealPtr;
  seed: LONGCARD; val: LONGREAL;
BEGIN
  IF durationSec <= 0.0 THEN output := NIL; outSamples := 0; RETURN END;
  outSamples := TRUNC(durationSec * LFLOAT(sampleRate));
  IF outSamples = 0 THEN output := NIL; RETURN END;
  ALLOCATE(output, outSamples * TSIZE(LONGREAL));
  seed := 12345;
  FOR i := 0 TO outSamples - 1 DO
    seed := (seed * 1103515245 + 12345) MOD 2147483648;
    val := LFLOAT(seed) / 1073741824.0 - 1.0;  (* [-1, 1] *)
    p := Elem(output, i);
    p^ := amplitude * val
  END
END GenerateNoise;

PROCEDURE GenerateClick(bpm, durationSec: LONGREAL;
                        sampleRate: CARDINAL;
                        VAR output: ADDRESS; VAR outSamples: CARDINAL);
VAR
  i, clickIdx: CARDINAL; p: RealPtr;
  clickInterval, nextClick: LONGREAL;
  clickSamples: CARDINAL;
BEGIN
  IF (durationSec <= 0.0) OR (bpm <= 0.0) THEN
    output := NIL; outSamples := 0; RETURN
  END;
  outSamples := TRUNC(durationSec * LFLOAT(sampleRate));
  IF outSamples = 0 THEN output := NIL; RETURN END;
  ALLOCATE(output, outSamples * TSIZE(LONGREAL));

  (* Zero fill *)
  FOR i := 0 TO outSamples - 1 DO
    p := Elem(output, i);
    p^ := 0.0
  END;

  clickInterval := 60.0 / bpm;
  clickSamples := TRUNC(0.005 * LFLOAT(sampleRate)); (* 5ms click *)
  IF clickSamples = 0 THEN clickSamples := 1 END;

  nextClick := 0.0;
  WHILE nextClick < durationSec DO
    i := TRUNC(nextClick * LFLOAT(sampleRate));
    IF i + clickSamples <= outSamples THEN
      (* Short decaying pulse *)
      FOR clickIdx := 0 TO clickSamples - 1 DO
        p := Elem(output, i + clickIdx);
        p^ := 0.8 * (1.0 - LFLOAT(clickIdx) / LFLOAT(clickSamples))
      END
    END;
    nextClick := nextClick + clickInterval
  END
END GenerateClick;

PROCEDURE FreeProc(VAR output: ADDRESS; numSamples: CARDINAL);
BEGIN
  IF output # NIL THEN
    DEALLOCATE(output, numSamples * TSIZE(LONGREAL));
    output := NIL
  END
END FreeProc;

END AudioProc.
