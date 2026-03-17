IMPLEMENTATION MODULE AudioConcat;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE Concat(sigA: ADDRESS; numA: CARDINAL;
                 sigB: ADDRESS; numB: CARDINAL;
                 sampleRate: CARDINAL;
                 crossfadeSec: LONGREAL;
                 VAR output: ADDRESS; VAR outSamples: CARDINAL);
VAR
  i, xfadeSamp: CARDINAL;
  totalLen: CARDINAL;
  pA, pB, pOut: RealPtr;
  t: LONGREAL;
BEGIN
  xfadeSamp := TRUNC(crossfadeSec * LFLOAT(sampleRate));
  IF xfadeSamp > numA THEN xfadeSamp := numA END;
  IF xfadeSamp > numB THEN xfadeSamp := numB END;

  totalLen := numA + numB - xfadeSamp;
  ALLOCATE(output, totalLen * TSIZE(LONGREAL));

  (* Copy A (before crossfade region) *)
  FOR i := 0 TO numA - xfadeSamp - 1 DO
    pA := Elem(sigA, i);
    pOut := Elem(output, i);
    pOut^ := pA^
  END;

  (* Crossfade region *)
  FOR i := 0 TO xfadeSamp - 1 DO
    t := LFLOAT(i) / LFLOAT(xfadeSamp);  (* 0..1 *)
    pA := Elem(sigA, numA - xfadeSamp + i);
    pB := Elem(sigB, i);
    pOut := Elem(output, numA - xfadeSamp + i);
    pOut^ := pA^ * (1.0 - t) + pB^ * t
  END;

  (* Copy B (after crossfade region) *)
  FOR i := xfadeSamp TO numB - 1 DO
    pB := Elem(sigB, i);
    pOut := Elem(output, numA + i - xfadeSamp);
    pOut^ := pB^
  END;

  outSamples := totalLen
END Concat;

PROCEDURE FreeConcat(VAR output: ADDRESS);
BEGIN
  IF output # NIL THEN DEALLOCATE(output, 0); output := NIL END
END FreeConcat;

END AudioConcat.
