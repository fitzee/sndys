MODULE tree_tests;

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM InOut IMPORT WriteString, WriteLn, WriteInt, WriteCard;
IMPORT DTree;
IMPORT Forest;
IMPORT GBoost;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr = POINTER TO INTEGER;

VAR
  passed, failed, total: CARDINAL;

(* ---- Helpers ---- *)

PROCEDURE SetReal(base: ADDRESS; idx: CARDINAL; val: LONGREAL);
VAR
  p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)));
  p^ := val
END SetReal;

PROCEDURE SetInt(base: ADDRESS; idx: CARDINAL; val: INTEGER);
VAR
  p: IntPtr;
BEGIN
  p := IntPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(INTEGER)));
  p^ := val
END SetInt;

PROCEDURE GetInt(base: ADDRESS; idx: CARDINAL): INTEGER;
VAR
  p: IntPtr;
BEGIN
  p := IntPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(INTEGER)));
  RETURN p^
END GetInt;

PROCEDURE GetReal(base: ADDRESS; idx: CARDINAL): LONGREAL;
VAR
  p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)));
  RETURN p^
END GetReal;

PROCEDURE Check(condition: BOOLEAN; name: ARRAY OF CHAR);
BEGIN
  INC(total);
  WriteString("  ");
  IF condition THEN
    INC(passed);
    WriteString("PASS: ")
  ELSE
    INC(failed);
    WriteString("FAIL: ")
  END;
  WriteString(name);
  WriteLn
END Check;

(* ============================================================
   Test 1: Decision tree learns XOR-like pattern
   ============================================================ *)

PROCEDURE TestXOR;
VAR
  data: ADDRESS;
  labels: ADDRESS;
  t: DTree.Tree;
  sample: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  correct: CARDINAL;
  i: CARDINAL;
BEGIN
  WriteString("Test 1: Decision tree XOR pattern");
  WriteLn;

  (* 8 samples: XOR on 2 features
     (0,0)->0, (0,1)->1, (1,0)->1, (1,1)->0
     duplicated for more training data *)
  ALLOCATE(data, 8 * 2 * TSIZE(LONGREAL));
  ALLOCATE(labels, 8 * TSIZE(INTEGER));

  (* Sample 0: (0,0) -> 0 *)
  SetReal(data, 0, 0.0); SetReal(data, 1, 0.0); SetInt(labels, 0, 0);
  (* Sample 1: (0,1) -> 1 *)
  SetReal(data, 2, 0.0); SetReal(data, 3, 1.0); SetInt(labels, 1, 1);
  (* Sample 2: (1,0) -> 1 *)
  SetReal(data, 4, 1.0); SetReal(data, 5, 0.0); SetInt(labels, 2, 1);
  (* Sample 3: (1,1) -> 0 *)
  SetReal(data, 6, 1.0); SetReal(data, 7, 1.0); SetInt(labels, 3, 0);
  (* Duplicates *)
  SetReal(data, 8, 0.1); SetReal(data, 9, 0.1); SetInt(labels, 4, 0);
  SetReal(data, 10, 0.1); SetReal(data, 11, 0.9); SetInt(labels, 5, 1);
  SetReal(data, 12, 0.9); SetReal(data, 13, 0.1); SetInt(labels, 6, 1);
  SetReal(data, 14, 0.9); SetReal(data, 15, 0.9); SetInt(labels, 7, 0);

  DTree.Init(t, 2, 2, 5);
  DTree.Train(t, data, labels, 8, 2);

  correct := 0;
  (* Test (0,0) -> 0 *)
  sample[0] := 0.05; sample[1] := 0.05;
  pred := DTree.Predict(t, ADR(sample));
  IF pred = 0 THEN INC(correct) END;

  (* Test (0,1) -> 1 *)
  sample[0] := 0.05; sample[1] := 0.95;
  pred := DTree.Predict(t, ADR(sample));
  IF pred = 1 THEN INC(correct) END;

  (* Test (1,0) -> 1 *)
  sample[0] := 0.95; sample[1] := 0.05;
  pred := DTree.Predict(t, ADR(sample));
  IF pred = 1 THEN INC(correct) END;

  (* Test (1,1) -> 0 *)
  sample[0] := 0.95; sample[1] := 0.95;
  pred := DTree.Predict(t, ADR(sample));
  IF pred = 0 THEN INC(correct) END;

  Check(correct >= 3, "XOR: at least 3/4 correct");
  Check(correct = 4, "XOR: all 4 correct");

  DTree.Free(t);
  DEALLOCATE(data, 8 * 2 * TSIZE(LONGREAL));
  DEALLOCATE(labels, 8 * TSIZE(INTEGER))
END TestXOR;

(* ============================================================
   Test 2: Linearly separable => 100% accuracy
   ============================================================ *)

PROCEDURE TestLinear;
VAR
  data: ADDRESS;
  labels: ADDRESS;
  t: DTree.Tree;
  sample: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  correct, i: CARDINAL;
  numSamples: CARDINAL;
BEGIN
  WriteString("Test 2: Linearly separable data");
  WriteLn;

  numSamples := 20;
  ALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  ALLOCATE(labels, numSamples * TSIZE(INTEGER));

  (* Class 0: x < 0.5, Class 1: x >= 0.5 *)
  FOR i := 0 TO 9 DO
    SetReal(data, i * 2, LFLOAT(i) / 20.0);          (* x1: 0.0..0.45 *)
    SetReal(data, i * 2 + 1, LFLOAT(i) / 10.0);      (* x2: noise *)
    SetInt(labels, i, 0)
  END;
  FOR i := 10 TO 19 DO
    SetReal(data, i * 2, 0.5 + LFLOAT(i - 10) / 20.0);  (* x1: 0.5..0.95 *)
    SetReal(data, i * 2 + 1, LFLOAT(i) / 10.0);
    SetInt(labels, i, 1)
  END;

  DTree.Init(t, 2, 2, 10);
  DTree.Train(t, data, labels, numSamples, 2);

  correct := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := DTree.Predict(t, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correct)
    END
  END;

  Check(correct = numSamples, "Linear: 100% training accuracy");

  DTree.Free(t);
  DEALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  DEALLOCATE(labels, numSamples * TSIZE(INTEGER))
END TestLinear;

(* ============================================================
   Test 3: Random Forest majority vote
   ============================================================ *)

PROCEDURE TestRandomForest;
VAR
  data: ADDRESS;
  labels: ADDRESS;
  f: Forest.Forest;
  sample: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  correct, i, numSamples: CARDINAL;
BEGIN
  WriteString("Test 3: Random Forest majority vote");
  WriteLn;

  numSamples := 20;
  ALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  ALLOCATE(labels, numSamples * TSIZE(INTEGER));

  (* Simple separable data *)
  FOR i := 0 TO 9 DO
    SetReal(data, i * 2, LFLOAT(i) / 20.0);
    SetReal(data, i * 2 + 1, 0.5);
    SetInt(labels, i, 0)
  END;
  FOR i := 10 TO 19 DO
    SetReal(data, i * 2, 0.5 + LFLOAT(i - 10) / 20.0);
    SetReal(data, i * 2 + 1, 0.5);
    SetInt(labels, i, 1)
  END;

  Forest.Init(f, 10, 2, 2, 5, Forest.RandomForest);
  Forest.Train(f, data, labels, numSamples, 2);

  correct := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := Forest.Predict(f, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correct)
    END
  END;

  Check(correct >= 15, "RF: at least 75% accuracy");
  WriteString("    RF accuracy: ");
  WriteCard(correct, 2);
  WriteString("/");
  WriteCard(numSamples, 2);
  WriteLn;

  Forest.Free(f);
  DEALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  DEALLOCATE(labels, numSamples * TSIZE(INTEGER))
END TestRandomForest;

(* ============================================================
   Test 4: Extra Trees trains and predicts
   ============================================================ *)

PROCEDURE TestExtraTrees;
VAR
  data: ADDRESS;
  labels: ADDRESS;
  f: Forest.Forest;
  sample: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  correct, i, numSamples: CARDINAL;
BEGIN
  WriteString("Test 4: Extra Trees");
  WriteLn;

  numSamples := 20;
  ALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  ALLOCATE(labels, numSamples * TSIZE(INTEGER));

  FOR i := 0 TO 9 DO
    SetReal(data, i * 2, LFLOAT(i) / 20.0);
    SetReal(data, i * 2 + 1, 0.3);
    SetInt(labels, i, 0)
  END;
  FOR i := 10 TO 19 DO
    SetReal(data, i * 2, 0.5 + LFLOAT(i - 10) / 20.0);
    SetReal(data, i * 2 + 1, 0.7);
    SetInt(labels, i, 1)
  END;

  Forest.Init(f, 15, 2, 2, 5, Forest.ExtraTrees);
  Forest.Train(f, data, labels, numSamples, 2);

  correct := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := Forest.Predict(f, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correct)
    END
  END;

  Check(correct >= 14, "ET: at least 70% accuracy");
  WriteString("    ET accuracy: ");
  WriteCard(correct, 2);
  WriteString("/");
  WriteCard(numSamples, 2);
  WriteLn;

  Forest.Free(f);
  DEALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  DEALLOCATE(labels, numSamples * TSIZE(INTEGER))
END TestExtraTrees;

(* ============================================================
   Test 5: Gradient Boosting improves over iterations
   ============================================================ *)

PROCEDURE TestGradientBoosting;
VAR
  data: ADDRESS;
  labels: ADDRESS;
  m1, m2: GBoost.GBModel;
  sample: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  correct1, correct2, i, numSamples: CARDINAL;
BEGIN
  WriteString("Test 5: Gradient Boosting improvement");
  WriteLn;

  numSamples := 20;
  ALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  ALLOCATE(labels, numSamples * TSIZE(INTEGER));

  FOR i := 0 TO 9 DO
    SetReal(data, i * 2, LFLOAT(i) / 20.0);
    SetReal(data, i * 2 + 1, 0.2 + LFLOAT(i) / 50.0);
    SetInt(labels, i, 0)
  END;
  FOR i := 10 TO 19 DO
    SetReal(data, i * 2, 0.5 + LFLOAT(i - 10) / 20.0);
    SetReal(data, i * 2 + 1, 0.6 + LFLOAT(i - 10) / 50.0);
    SetInt(labels, i, 1)
  END;

  (* Few rounds *)
  GBoost.Init(m1, 3, 2, 2, 0.5);
  GBoost.Train(m1, data, labels, numSamples, 2);

  correct1 := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := GBoost.Predict(m1, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correct1)
    END
  END;

  (* Many rounds *)
  GBoost.Init(m2, 20, 2, 2, 0.3);
  GBoost.Train(m2, data, labels, numSamples, 2);

  correct2 := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := GBoost.Predict(m2, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correct2)
    END
  END;

  Check(correct2 >= correct1, "GB: more rounds >= fewer rounds accuracy");
  Check(correct2 >= 15, "GB: 20 rounds achieves >= 75% accuracy");
  WriteString("    GB 3 rounds: ");
  WriteCard(correct1, 2);
  WriteString("/");
  WriteCard(numSamples, 2);
  WriteString("  20 rounds: ");
  WriteCard(correct2, 2);
  WriteString("/");
  WriteCard(numSamples, 2);
  WriteLn;

  GBoost.Free(m1);
  GBoost.Free(m2);
  DEALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  DEALLOCATE(labels, numSamples * TSIZE(INTEGER))
END TestGradientBoosting;

(* ============================================================
   Test 6: All classifiers handle 3-class problems
   ============================================================ *)

PROCEDURE TestThreeClass;
VAR
  data: ADDRESS;
  labels: ADDRESS;
  t: DTree.Tree;
  f: Forest.Forest;
  m: GBoost.GBModel;
  sample: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  correctTree, correctRF, correctGB: CARDINAL;
  i, numSamples: CARDINAL;
BEGIN
  WriteString("Test 6: Three-class classification");
  WriteLn;

  numSamples := 30;
  ALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  ALLOCATE(labels, numSamples * TSIZE(INTEGER));

  (* Class 0: x1 in [0.0, 0.3) *)
  FOR i := 0 TO 9 DO
    SetReal(data, i * 2, LFLOAT(i) / 40.0);
    SetReal(data, i * 2 + 1, 0.5);
    SetInt(labels, i, 0)
  END;
  (* Class 1: x1 in [0.35, 0.65) *)
  FOR i := 10 TO 19 DO
    SetReal(data, i * 2, 0.35 + LFLOAT(i - 10) / 40.0);
    SetReal(data, i * 2 + 1, 0.5);
    SetInt(labels, i, 1)
  END;
  (* Class 2: x1 in [0.7, 1.0) *)
  FOR i := 20 TO 29 DO
    SetReal(data, i * 2, 0.7 + LFLOAT(i - 20) / 40.0);
    SetReal(data, i * 2 + 1, 0.5);
    SetInt(labels, i, 2)
  END;

  (* Decision Tree *)
  DTree.Init(t, 2, 3, 10);
  DTree.Train(t, data, labels, numSamples, 2);

  correctTree := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := DTree.Predict(t, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correctTree)
    END
  END;

  Check(correctTree >= 25, "3-class Tree: >= 83% accuracy");
  WriteString("    Tree: ");
  WriteCard(correctTree, 2);
  WriteString("/");
  WriteCard(numSamples, 2);
  WriteLn;

  (* Random Forest *)
  Forest.Init(f, 10, 2, 3, 5, Forest.RandomForest);
  Forest.Train(f, data, labels, numSamples, 2);

  correctRF := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := Forest.Predict(f, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correctRF)
    END
  END;

  Check(correctRF >= 20, "3-class RF: >= 67% accuracy");
  WriteString("    RF: ");
  WriteCard(correctRF, 2);
  WriteString("/");
  WriteCard(numSamples, 2);
  WriteLn;

  (* Gradient Boosting *)
  GBoost.Init(m, 30, 2, 3, 0.3);
  GBoost.Train(m, data, labels, numSamples, 2);

  correctGB := 0;
  FOR i := 0 TO numSamples - 1 DO
    sample[0] := GetReal(data, i * 2);
    sample[1] := GetReal(data, i * 2 + 1);
    pred := GBoost.Predict(m, ADR(sample));
    IF pred = GetInt(labels, i) THEN
      INC(correctGB)
    END
  END;

  Check(correctGB >= 20, "3-class GB: >= 67% accuracy");
  WriteString("    GB: ");
  WriteCard(correctGB, 2);
  WriteString("/");
  WriteCard(numSamples, 2);
  WriteLn;

  DTree.Free(t);
  Forest.Free(f);
  GBoost.Free(m);
  DEALLOCATE(data, numSamples * 2 * TSIZE(LONGREAL));
  DEALLOCATE(labels, numSamples * TSIZE(INTEGER))
END TestThreeClass;

(* ---- Main ---- *)

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("=== m2tree Test Suite ===");
  WriteLn;
  WriteLn;

  TestXOR;
  WriteLn;
  TestLinear;
  WriteLn;
  TestRandomForest;
  WriteLn;
  TestExtraTrees;
  WriteLn;
  TestGradientBoosting;
  WriteLn;
  TestThreeClass;

  WriteLn;
  WriteString("========================");
  WriteLn;
  WriteString("Total: ");
  WriteCard(total, 2);
  WriteString("  Passed: ");
  WriteCard(passed, 2);
  WriteString("  Failed: ");
  WriteCard(failed, 2);
  WriteLn;
  IF failed = 0 THEN
    WriteString("All tests passed!")
  ELSE
    WriteString("Some tests FAILED.")
  END;
  WriteLn
END tree_tests.
