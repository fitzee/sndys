IMPLEMENTATION MODULE PitchTrack;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Harmonic IMPORT ComputeHarmonicF0;

CONST
  WinSec  = 0.050;
  StepSec = 0.010;  (* 10ms step for smooth pitch contour *)
  MinHR   = 0.3;    (* minimum harmonic ratio to consider voiced *)

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

(* Simple insertion sort for small arrays *)
PROCEDURE SortSmall(VAR a: ARRAY OF LONGREAL; n: CARDINAL);
VAR i, j: CARDINAL; tmp: LONGREAL;
BEGIN
  FOR i := 1 TO n - 1 DO
    tmp := a[i];
    j := i;
    WHILE (j > 0) AND (a[j - 1] > tmp) DO
      a[j] := a[j - 1];
      DEC(j)
    END;
    a[j] := tmp
  END
END SortSmall;

PROCEDURE TrackPitch(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                     smoothWindow: CARDINAL;
                     VAR pitches: ADDRESS;
                     VAR times: ADDRESS;
                     VAR numFrames: CARDINAL);
VAR
  winSamp, stepSamp, i, j: CARDINAL;
  totalFrames: CARDINAL;
  hr, f0: LONGREAL;
  frameAddr: ADDRESS;
  pP, pT, pSrc: RealPtr;
  (* Median filter *)
  half, wStart, wEnd, wCount: CARDINAL;
  medBuf: ARRAY [0..31] OF LONGREAL;
  smoothed: ADDRESS;
BEGIN
  pitches := NIL;
  times := NIL;
  numFrames := 0;

  winSamp := TRUNC(WinSec * LFLOAT(sampleRate));
  stepSamp := TRUNC(StepSec * LFLOAT(sampleRate));
  IF (winSamp = 0) OR (stepSamp = 0) OR (numSamples < winSamp) THEN RETURN END;

  totalFrames := (numSamples - winSamp) DIV stepSamp + 1;
  IF totalFrames = 0 THEN RETURN END;

  ALLOCATE(pitches, totalFrames * TSIZE(LONGREAL));
  ALLOCATE(times, totalFrames * TSIZE(LONGREAL));

  (* Extract raw F0 per frame *)
  FOR i := 0 TO totalFrames - 1 DO
    frameAddr := ADDRESS(LONGCARD(signal)
                 + LONGCARD(i * stepSamp * TSIZE(LONGREAL)));
    ComputeHarmonicF0(frameAddr, winSamp, sampleRate, hr, f0);

    pT := Elem(times, i);
    pT^ := LFLOAT(i) * StepSec;

    pP := Elem(pitches, i);
    IF hr >= MinHR THEN
      pP^ := f0
    ELSE
      pP^ := 0.0  (* unvoiced *)
    END
  END;

  (* Median smoothing — only smooth voiced frames *)
  IF smoothWindow >= 3 THEN
    ALLOCATE(smoothed, totalFrames * TSIZE(LONGREAL));
    half := smoothWindow DIV 2;

    FOR i := 0 TO totalFrames - 1 DO
      pP := Elem(pitches, i);
      IF pP^ = 0.0 THEN
        (* Unvoiced — keep as 0 *)
        pSrc := Elem(smoothed, i);
        pSrc^ := 0.0
      ELSE
        (* Collect voiced neighbors *)
        IF i >= half THEN wStart := i - half ELSE wStart := 0 END;
        wEnd := i + half;
        IF wEnd >= totalFrames THEN wEnd := totalFrames - 1 END;

        wCount := 0;
        FOR j := wStart TO wEnd DO
          pSrc := Elem(pitches, j);
          IF pSrc^ > 0.0 THEN
            IF wCount <= HIGH(medBuf) THEN
              medBuf[wCount] := pSrc^;
              INC(wCount)
            END
          END
        END;

        pSrc := Elem(smoothed, i);
        IF wCount > 0 THEN
          SortSmall(medBuf, wCount);
          pSrc^ := medBuf[wCount DIV 2]
        ELSE
          pSrc^ := 0.0
        END
      END
    END;

    (* Copy back *)
    FOR i := 0 TO totalFrames - 1 DO
      pSrc := Elem(smoothed, i);
      pP := Elem(pitches, i);
      pP^ := pSrc^
    END;
    DEALLOCATE(smoothed, 0)
  END;

  numFrames := totalFrames
END TrackPitch;

PROCEDURE FreePitch(VAR pitches: ADDRESS; VAR times: ADDRESS);
BEGIN
  IF pitches # NIL THEN DEALLOCATE(pitches, 0); pitches := NIL END;
  IF times # NIL THEN DEALLOCATE(times, 0); times := NIL END
END FreePitch;

END PitchTrack.
