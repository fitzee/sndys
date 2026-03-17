IMPLEMENTATION MODULE DCT;
(* Discrete Cosine Transform (DCT-II/III) for MFCC computation.
   Direct O(N^2) implementation, suitable for N = 13..40. *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathLib IMPORT cos;

CONST
  Pi = 3.14159265358979323846D0;

TYPE
  RealPtr = POINTER TO LONGREAL;

(* Helper: return pointer to element at index idx in a LONGREAL array
   starting at base. *)
PROCEDURE ElemPtr(base: ADDRESS; idx: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)))
END ElemPtr;

PROCEDURE Forward(input: ADDRESS; n: CARDINAL; output: ADDRESS);
VAR
  k, i: CARDINAL;
  sum, angle: LONGREAL;
  pIn, pOut: RealPtr;
BEGIN
  FOR k := 0 TO n - 1 DO
    sum := 0.0D0;
    FOR i := 0 TO n - 1 DO
      pIn := ElemPtr(input, i);
      angle := Pi / LFLOAT(n) * (LFLOAT(i) + 0.5D0) * LFLOAT(k);
      sum := sum + pIn^ * LFLOAT(cos(FLOAT(angle)))
    END;
    pOut := ElemPtr(output, k);
    pOut^ := sum
  END
END Forward;

PROCEDURE ForwardPartial(input: ADDRESS; n: CARDINAL;
                         output: ADDRESS; numCoeffs: CARDINAL);
VAR
  k, i: CARDINAL;
  sum, angle: LONGREAL;
  pIn, pOut: RealPtr;
BEGIN
  FOR k := 0 TO numCoeffs - 1 DO
    sum := 0.0D0;
    FOR i := 0 TO n - 1 DO
      pIn := ElemPtr(input, i);
      angle := Pi / LFLOAT(n) * (LFLOAT(i) + 0.5D0) * LFLOAT(k);
      sum := sum + pIn^ * LFLOAT(cos(FLOAT(angle)))
    END;
    pOut := ElemPtr(output, k);
    pOut^ := sum
  END
END ForwardPartial;

PROCEDURE Inverse(input: ADDRESS; n: CARDINAL; output: ADDRESS);
VAR
  i, k: CARDINAL;
  sum, angle, invN: LONGREAL;
  pIn, pOut, pDc: RealPtr;
BEGIN
  invN := 1.0D0 / LFLOAT(n);
  pDc := ElemPtr(input, 0);
  FOR i := 0 TO n - 1 DO
    sum := pDc^ * 0.5D0;
    FOR k := 1 TO n - 1 DO
      pIn := ElemPtr(input, k);
      angle := Pi / LFLOAT(n) * LFLOAT(k) * (LFLOAT(i) + 0.5D0);
      sum := sum + pIn^ * LFLOAT(cos(FLOAT(angle)))
    END;
    pOut := ElemPtr(output, i);
    pOut^ := sum * invN
  END
END Inverse;

END DCT.
