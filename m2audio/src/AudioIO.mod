IMPLEMENTATION MODULE AudioIO;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Wav IMPORT WavInfo, ReadWav, FreeWav, StereoToMono, FreeMono;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

PROCEDURE ReadAudio(path: ARRAY OF CHAR;
                    VAR signal: ADDRESS;
                    VAR numSamples: CARDINAL;
                    VAR sampleRate: CARDINAL;
                    VAR ok: BOOLEAN);
VAR
  info: WavInfo;
  samples, mono: ADDRESS;
BEGIN
  ok := FALSE;
  signal := NIL;
  numSamples := 0;
  sampleRate := 0;

  ReadWav(path, info, samples, ok);
  IF NOT ok THEN RETURN END;

  sampleRate := info.sampleRate;
  numSamples := info.numSamples;

  IF info.numChannels = 2 THEN
    StereoToMono(samples, info.numSamples, mono);
    FreeWav(samples, info.numSamples * info.numChannels);
    signal := mono
  ELSIF info.numChannels = 1 THEN
    signal := samples
  ELSE
    FreeWav(samples, info.numSamples * info.numChannels);
    ok := FALSE;
    RETURN
  END;

  ok := TRUE
END ReadAudio;

PROCEDURE FreeSignal(VAR signal: ADDRESS; numSamples: CARDINAL);
BEGIN
  IF signal # NIL THEN
    DEALLOCATE(signal, numSamples * TSIZE(LONGREAL));
    signal := NIL
  END
END FreeSignal;

PROCEDURE PreEmphasis(signal: ADDRESS; n: CARDINAL;
                      coeff: LONGREAL; output: ADDRESS);
VAR
  i: CARDINAL;
  pOut, pCur, pPrev: RealPtr;
BEGIN
  IF n = 0 THEN RETURN END;

  (* First sample: y[0] = x[0] *)
  pCur := Elem(signal, 0);
  pOut := Elem(output, 0);
  pOut^ := pCur^;

  (* Remaining samples: y[n] = x[n] - coeff * x[n-1] *)
  FOR i := 1 TO n - 1 DO
    pCur := Elem(signal, i);
    pPrev := Elem(signal, i - 1);
    pOut := Elem(output, i);
    pOut^ := pCur^ - coeff * pPrev^
  END
END PreEmphasis;

END AudioIO.
