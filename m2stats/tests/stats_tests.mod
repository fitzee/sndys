MODULE StatsTests;

FROM InOut IMPORT WriteString, WriteInt, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM MathLib IMPORT ln;
FROM Stats IMPORT Mean, Variance, StdDev, Min, Max, ArgMin, ArgMax,
                  Sum, SumSq, Entropy, Normalize, ZScore, DotProduct,
                  RealPtr;

CONST
  Eps = 1.0D-9;

VAR
  passed, failed, total: INTEGER;

PROCEDURE Abs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0 THEN RETURN -x END;
  RETURN x
END Abs;

PROCEDURE Check(label: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  WriteString(label);
  IF cond THEN
    WriteString(" ... PASSED");
    INC(passed)
  ELSE
    WriteString(" ... FAILED");
    INC(failed)
  END;
  WriteLn
END Check;

PROCEDURE CheckApprox(label: ARRAY OF CHAR; got, expected: LONGREAL);
BEGIN
  Check(label, Abs(got - expected) < Eps)
END CheckApprox;

PROCEDURE CheckCard(label: ARRAY OF CHAR; got, expected: CARDINAL);
BEGIN
  Check(label, got = expected)
END CheckCard;

(* Elem -- return pointer to element at index i from base address *)
PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE TestMean;
VAR
  data: ARRAY [0..4] OF LONGREAL;
BEGIN
  data[0] := 1.0; data[1] := 2.0; data[2] := 3.0;
  data[3] := 4.0; data[4] := 5.0;
  CheckApprox("Test 1: Mean of [1,2,3,4,5]", Mean(ADR(data), 5), 3.0)
END TestMean;

PROCEDURE TestVariance;
VAR
  data: ARRAY [0..7] OF LONGREAL;
BEGIN
  data[0] := 2.0; data[1] := 4.0; data[2] := 4.0; data[3] := 4.0;
  data[4] := 5.0; data[5] := 5.0; data[6] := 7.0; data[7] := 9.0;
  CheckApprox("Test 2: Variance of [2,4,4,4,5,5,7,9]",
              Variance(ADR(data), 8), 4.0)
END TestVariance;

PROCEDURE TestStdDev;
VAR
  data: ARRAY [0..7] OF LONGREAL;
BEGIN
  data[0] := 2.0; data[1] := 4.0; data[2] := 4.0; data[3] := 4.0;
  data[4] := 5.0; data[5] := 5.0; data[6] := 7.0; data[7] := 9.0;
  CheckApprox("Test 3: StdDev of [2,4,4,4,5,5,7,9]",
              StdDev(ADR(data), 8), 2.0)
END TestStdDev;

PROCEDURE TestMinMaxArgMinArgMax;
VAR
  data: ARRAY [0..4] OF LONGREAL;
BEGIN
  data[0] := 3.0; data[1] := 1.0; data[2] := 4.0;
  data[3] := 1.5; data[4] := 2.0;
  CheckApprox("Test 4a: Min of [3,1,4,1.5,2]", Min(ADR(data), 5), 1.0);
  CheckApprox("Test 4b: Max of [3,1,4,1.5,2]", Max(ADR(data), 5), 4.0);
  CheckCard("Test 4c: ArgMin of [3,1,4,1.5,2]", ArgMin(ADR(data), 5), 1);
  CheckCard("Test 4d: ArgMax of [3,1,4,1.5,2]", ArgMax(ADR(data), 5), 2)
END TestMinMaxArgMinArgMax;

PROCEDURE TestSumSumSq;
VAR
  data: ARRAY [0..2] OF LONGREAL;
BEGIN
  data[0] := 1.0; data[1] := 2.0; data[2] := 3.0;
  CheckApprox("Test 5a: Sum of [1,2,3]", Sum(ADR(data), 3), 6.0);
  CheckApprox("Test 5b: SumSq of [1,2,3]", SumSq(ADR(data), 3), 14.0)
END TestSumSumSq;

PROCEDURE TestEntropyUniform;
VAR
  data: ARRAY [0..3] OF LONGREAL;
BEGIN
  data[0] := 0.25; data[1] := 0.25; data[2] := 0.25; data[3] := 0.25;
  CheckApprox("Test 6: Entropy of uniform [0.25,0.25,0.25,0.25]",
              Entropy(ADR(data), 4), ln(4.0))
END TestEntropyUniform;

PROCEDURE TestEntropyDegenerate;
VAR
  data: ARRAY [0..2] OF LONGREAL;
BEGIN
  data[0] := 1.0; data[1] := 0.0; data[2] := 0.0;
  CheckApprox("Test 7: Entropy of degenerate [1,0,0]",
              Entropy(ADR(data), 3), 0.0)
END TestEntropyDegenerate;

PROCEDURE TestNormalize;
VAR
  data: ARRAY [0..2] OF LONGREAL;
  p: RealPtr;
BEGIN
  data[0] := 2.0; data[1] := 3.0; data[2] := 5.0;
  Normalize(ADR(data), 3);
  CheckApprox("Test 8a: Normalize [2,3,5] elem 0", data[0], 0.2);
  CheckApprox("Test 8b: Normalize [2,3,5] elem 1", data[1], 0.3);
  CheckApprox("Test 8c: Normalize [2,3,5] elem 2", data[2], 0.5)
END TestNormalize;

PROCEDURE TestZScore;
VAR
  data: ARRAY [0..2] OF LONGREAL;
BEGIN
  data[0] := 10.0; data[1] := 20.0; data[2] := 30.0;
  (* mean=20, sd=10 => [-1, 0, 1] *)
  ZScore(ADR(data), 3, 20.0, 10.0);
  CheckApprox("Test 9a: ZScore [10,20,30] elem 0", data[0], -1.0);
  CheckApprox("Test 9b: ZScore [10,20,30] elem 1", data[1], 0.0);
  CheckApprox("Test 9c: ZScore [10,20,30] elem 2", data[2], 1.0)
END TestZScore;

PROCEDURE TestDotProduct;
VAR
  a, b: ARRAY [0..2] OF LONGREAL;
BEGIN
  a[0] := 1.0; a[1] := 2.0; a[2] := 3.0;
  b[0] := 4.0; b[1] := 5.0; b[2] := 6.0;
  CheckApprox("Test 10: DotProduct [1,2,3].[4,5,6]",
              DotProduct(ADR(a), ADR(b), 3), 32.0)
END TestDotProduct;

PROCEDURE TestEdgeCases;
VAR
  data: ARRAY [0..0] OF LONGREAL;
  dummy: LONGREAL;
BEGIN
  (* n=1 *)
  data[0] := 42.0;
  CheckApprox("Test 11a: Mean of single element", Mean(ADR(data), 1), 42.0);
  CheckApprox("Test 11b: Variance of single element",
              Variance(ADR(data), 1), 0.0);
  CheckApprox("Test 11c: StdDev of single element",
              StdDev(ADR(data), 1), 0.0);
  CheckApprox("Test 11d: Min of single element", Min(ADR(data), 1), 42.0);
  CheckApprox("Test 11e: Max of single element", Max(ADR(data), 1), 42.0);
  CheckCard("Test 11f: ArgMin of single element", ArgMin(ADR(data), 1), 0);
  CheckCard("Test 11g: ArgMax of single element", ArgMax(ADR(data), 1), 0);

  (* n=0 *)
  dummy := 0.0;
  CheckApprox("Test 11h: Mean of empty", Mean(ADR(dummy), 0), 0.0);
  CheckApprox("Test 11i: Sum of empty", Sum(ADR(dummy), 0), 0.0);
  CheckApprox("Test 11j: Variance of empty", Variance(ADR(dummy), 0), 0.0);
  CheckApprox("Test 11k: Entropy of empty", Entropy(ADR(dummy), 0), 0.0);
  CheckApprox("Test 11l: DotProduct of empty",
              DotProduct(ADR(dummy), ADR(dummy), 0), 0.0)
END TestEdgeCases;

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("=== m2stats test suite ==="); WriteLn;
  WriteLn;

  TestMean;
  TestVariance;
  TestStdDev;
  TestMinMaxArgMinArgMax;
  TestSumSumSq;
  TestEntropyUniform;
  TestEntropyDegenerate;
  TestNormalize;
  TestZScore;
  TestDotProduct;
  TestEdgeCases;

  WriteLn;
  WriteString("=== Results: ");
  WriteInt(passed, 1);
  WriteString(" passed, ");
  WriteInt(failed, 1);
  WriteString(" failed, ");
  WriteInt(total, 1);
  WriteString(" total ===");
  WriteLn;

  IF failed # 0 THEN
    HALT
  END
END StatsTests.
