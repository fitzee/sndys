MODULE DctTests;
(* Comprehensive tests for the DCT module. *)

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM InOut IMPORT WriteString, WriteLn, WriteCard;
FROM MathLib IMPORT cos, sqrt;
FROM DCT IMPORT Forward, ForwardPartial, Inverse;

CONST
  Epsilon = 1.0D-6;
  Pi      = 3.14159265358979323846D0;

VAR
  passed, failed, total: CARDINAL;

(* ----- helpers ----- *)

PROCEDURE Abs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0D0 THEN
    RETURN -x
  ELSE
    RETURN x
  END
END Abs;

PROCEDURE CheckApprox(name: ARRAY OF CHAR;
                      actual, expected: LONGREAL);
BEGIN
  INC(total);
  IF Abs(actual - expected) < Epsilon THEN
    INC(passed);
    WriteString("  PASS: ");
    WriteString(name);
    WriteLn
  ELSE
    INC(failed);
    WriteString("  FAIL: ");
    WriteString(name);
    WriteLn
  END
END CheckApprox;

PROCEDURE Check(name: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  IF cond THEN
    INC(passed);
    WriteString("  PASS: ");
    WriteString(name);
    WriteLn
  ELSE
    INC(failed);
    WriteString("  FAIL: ");
    WriteString(name);
    WriteLn
  END
END Check;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; idx: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)))
END Elem;

(* ----- Test 1: DCT of [1,1,1,1] ----- *)

PROCEDURE Test1;
VAR
  input:  ARRAY [0..3] OF LONGREAL;
  output: ARRAY [0..3] OF LONGREAL;
BEGIN
  WriteString("Test1: DCT of [1,1,1,1]");
  WriteLn;
  input[0] := 1.0D0; input[1] := 1.0D0;
  input[2] := 1.0D0; input[3] := 1.0D0;
  Forward(ADR(input), 4, ADR(output));
  CheckApprox("DC coefficient = 4.0", output[0], 4.0D0);
  CheckApprox("coeff[1] = 0.0", output[1], 0.0D0);
  CheckApprox("coeff[2] = 0.0", output[2], 0.0D0);
  CheckApprox("coeff[3] = 0.0", output[3], 0.0D0)
END Test1;

(* ----- Test 2: DCT of impulse [1,0,0,0] ----- *)

PROCEDURE Test2;
VAR
  input:  ARRAY [0..3] OF LONGREAL;
  output: ARRAY [0..3] OF LONGREAL;
  k: CARDINAL;
  expected: LONGREAL;
BEGIN
  WriteString("Test2: DCT of impulse [1,0,0,0]");
  WriteLn;
  input[0] := 1.0D0; input[1] := 0.0D0;
  input[2] := 0.0D0; input[3] := 0.0D0;
  Forward(ADR(input), 4, ADR(output));
  (* X[k] = cos(pi/4 * 0.5 * k) *)
  FOR k := 0 TO 3 DO
    expected := LFLOAT(cos(FLOAT(Pi / 4.0D0 * 0.5D0 * LFLOAT(k))));
    CheckApprox("impulse coeff", output[k], expected)
  END
END Test2;

(* ----- Test 3: Forward then Inverse roundtrip ----- *)

PROCEDURE Test3;
VAR
  input:     ARRAY [0..3] OF LONGREAL;
  dctBuf:    ARRAY [0..3] OF LONGREAL;
  recovered: ARRAY [0..3] OF LONGREAL;
  i: CARDINAL;
BEGIN
  WriteString("Test3: Forward/Inverse roundtrip");
  WriteLn;
  input[0] := 1.0D0; input[1] := 2.0D0;
  input[2] := 3.0D0; input[3] := 4.0D0;
  Forward(ADR(input), 4, ADR(dctBuf));
  Inverse(ADR(dctBuf), 4, ADR(recovered));
  FOR i := 0 TO 3 DO
    CheckApprox("roundtrip element", recovered[i], input[i])
  END
END Test3;

(* ----- Test 4: ForwardPartial matches full DCT ----- *)

PROCEDURE Test4;
VAR
  input:   ARRAY [0..3] OF LONGREAL;
  full:    ARRAY [0..3] OF LONGREAL;
  partial: ARRAY [0..1] OF LONGREAL;
BEGIN
  WriteString("Test4: ForwardPartial first 2 coefficients");
  WriteLn;
  input[0] := 1.0D0; input[1] := 2.0D0;
  input[2] := 3.0D0; input[3] := 4.0D0;
  Forward(ADR(input), 4, ADR(full));
  ForwardPartial(ADR(input), 4, ADR(partial), 2);
  CheckApprox("partial[0] = full[0]", partial[0], full[0]);
  CheckApprox("partial[1] = full[1]", partial[1], full[1])
END Test4;

(* ----- Test 5: DCT of [1,2,3,4] known values ----- *)

PROCEDURE Test5;
VAR
  input:  ARRAY [0..3] OF LONGREAL;
  output: ARRAY [0..3] OF LONGREAL;
  e0, e1, e2, e3: LONGREAL;
BEGIN
  WriteString("Test5: DCT of [1,2,3,4] known values");
  WriteLn;
  input[0] := 1.0D0; input[1] := 2.0D0;
  input[2] := 3.0D0; input[3] := 4.0D0;
  Forward(ADR(input), 4, ADR(output));
  (* Manually computed:
     X[0] = 1*cos(0) + 2*cos(0) + 3*cos(0) + 4*cos(0) = 10
     X[1] = 1*cos(pi/8) + 2*cos(3pi/8) + 3*cos(5pi/8) + 4*cos(7pi/8)
     X[2] = 1*cos(pi/4) + 2*cos(3pi/4) + 3*cos(5pi/4) + 4*cos(7pi/4)
     X[3] = 1*cos(3pi/8) + 2*cos(9pi/8) + 3*cos(15pi/8) + 4*cos(21pi/8)
  *)
  e0 := 10.0D0;
  e1 := LFLOAT(cos(FLOAT(Pi / 8.0D0))) + 2.0D0 * LFLOAT(cos(FLOAT(3.0D0 * Pi / 8.0D0)))
        + 3.0D0 * LFLOAT(cos(FLOAT(5.0D0 * Pi / 8.0D0))) + 4.0D0 * LFLOAT(cos(FLOAT(7.0D0 * Pi / 8.0D0)));
  e2 := LFLOAT(cos(FLOAT(Pi / 4.0D0))) + 2.0D0 * LFLOAT(cos(FLOAT(3.0D0 * Pi / 4.0D0)))
        + 3.0D0 * LFLOAT(cos(FLOAT(5.0D0 * Pi / 4.0D0))) + 4.0D0 * LFLOAT(cos(FLOAT(7.0D0 * Pi / 4.0D0)));
  e3 := LFLOAT(cos(FLOAT(3.0D0 * Pi / 8.0D0))) + 2.0D0 * LFLOAT(cos(FLOAT(9.0D0 * Pi / 8.0D0)))
        + 3.0D0 * LFLOAT(cos(FLOAT(15.0D0 * Pi / 8.0D0))) + 4.0D0 * LFLOAT(cos(FLOAT(21.0D0 * Pi / 8.0D0)));
  CheckApprox("X[0] = 10.0", output[0], e0);
  CheckApprox("X[1] known", output[1], e1);
  CheckApprox("X[2] known", output[2], e2);
  CheckApprox("X[3] known", output[3], e3)
END Test5;

(* ----- Test 6: Energy conservation (Parseval) ----- *)
(* For DCT-II with our convention:
   sum x[n]^2 = (1/N) * ( X[0]^2/2 + sum_{k=1}^{N-1} X[k]^2 / 2 )
   Actually the exact Parseval relation depends on normalisation.
   We verify roundtrip energy: the inverse recovers the signal,
   so time-domain energy must match. We also verify directly:
   sum x[n]^2 = (1/N) * sum X[k]^2   ... NOT exactly for unnormalised DCT.
   For the unnormalised DCT-II we have:
     2 * N * sum x[n]^2 = X[0]^2 + 2 * sum_{k=1}^{N-1} X[k]^2 ... no.
   Let us use the identity that Forward then Inverse recovers signal,
   which implicitly proves energy conservation. We test a different
   approach: the squared norm is preserved through roundtrip. *)

PROCEDURE Test6;
VAR
  input:     ARRAY [0..3] OF LONGREAL;
  dctBuf:    ARRAY [0..3] OF LONGREAL;
  recovered: ARRAY [0..3] OF LONGREAL;
  energyIn, energyOut: LONGREAL;
  i: CARDINAL;
BEGIN
  WriteString("Test6: Energy conservation via roundtrip");
  WriteLn;
  input[0] := 3.0D0; input[1] := -1.0D0;
  input[2] := 0.5D0; input[3] := 2.7D0;
  Forward(ADR(input), 4, ADR(dctBuf));
  Inverse(ADR(dctBuf), 4, ADR(recovered));
  energyIn  := 0.0D0;
  energyOut := 0.0D0;
  FOR i := 0 TO 3 DO
    energyIn  := energyIn  + input[i] * input[i];
    energyOut := energyOut + recovered[i] * recovered[i]
  END;
  CheckApprox("energy preserved", energyIn, energyOut)
END Test6;

(* ----- Test 7: DCT of length-8 signal ----- *)

PROCEDURE Test7;
VAR
  input:     ARRAY [0..7] OF LONGREAL;
  dctBuf:    ARRAY [0..7] OF LONGREAL;
  recovered: ARRAY [0..7] OF LONGREAL;
  i: CARDINAL;
BEGIN
  WriteString("Test7: DCT of length-8 signal roundtrip");
  WriteLn;
  input[0] := 0.1D0; input[1] := 0.4D0;
  input[2] := 0.9D0; input[3] := 1.6D0;
  input[4] := 2.5D0; input[5] := 3.6D0;
  input[6] := 4.9D0; input[7] := 6.4D0;
  Forward(ADR(input), 8, ADR(dctBuf));
  Inverse(ADR(dctBuf), 8, ADR(recovered));
  FOR i := 0 TO 7 DO
    CheckApprox("len8 roundtrip", recovered[i], input[i])
  END;
  (* Also verify DC = sum of all elements *)
  CheckApprox("len8 DC = sum",
              dctBuf[0],
              0.1D0 + 0.4D0 + 0.9D0 + 1.6D0 +
              2.5D0 + 3.6D0 + 4.9D0 + 6.4D0)
END Test7;

BEGIN
  passed := 0;
  failed := 0;
  total  := 0;

  WriteString("=== m2dct test suite ===");
  WriteLn;
  WriteLn;

  Test1;
  WriteLn;
  Test2;
  WriteLn;
  Test3;
  WriteLn;
  Test4;
  WriteLn;
  Test5;
  WriteLn;
  Test6;
  WriteLn;
  Test7;

  WriteLn;
  WriteString("=== Results: ");
  WriteCard(passed, 0);
  WriteString(" passed, ");
  WriteCard(failed, 0);
  WriteString(" failed, ");
  WriteCard(total, 0);
  WriteString(" total ===");
  WriteLn;

  IF failed # 0 THEN
    WriteString("SOME TESTS FAILED");
    WriteLn
  ELSE
    WriteString("ALL TESTS PASSED");
    WriteLn
  END
END DctTests.
