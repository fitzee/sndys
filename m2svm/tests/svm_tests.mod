MODULE SvmTests;
(* Test suite for m2svm: SVM classifier with SMO.

   Tests:
     1.  Linear SVM separates 2 linearly separable clusters
     2.  RBF SVM handles XOR-like non-linear boundary
     3.  Multi-class one-vs-rest on 3 classes
     4.  Predict sign matches training labels
     5.  Convergence within reasonable iterations *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM SVM IMPORT SVMModel, MultiSVM, KernelType, Linear, RBF;
IMPORT SVM;

CONST
  Eps = 1.0D-6;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

VAR
  passed, failed, total: INTEGER;

PROCEDURE Check(name: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  IF cond THEN
    INC(passed)
  ELSE
    INC(failed);
    WriteString("FAIL: "); WriteString(name); WriteLn
  END
END Check;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i * TSIZE(INTEGER)))
END ElemI;

(* ── Test 1: Linear SVM on 2 separable clusters ─────── *)

PROCEDURE Test1;
VAR
  m: SVMModel;
  (* 8 samples x 2 features:
     cluster A (+1): (1,1), (2,1), (1,2), (2,2)
     cluster B (-1): (5,5), (6,5), (5,6), (6,6) *)
  data: ARRAY [0..15] OF LONGREAL;
  labels: ARRAY [0..7] OF LONGREAL;
  testA, testB: ARRAY [0..1] OF LONGREAL;
  predA, predB: LONGREAL;
BEGIN
  (* Cluster A *)
  data[0] := 1.0; data[1] := 1.0;
  data[2] := 2.0; data[3] := 1.0;
  data[4] := 1.0; data[5] := 2.0;
  data[6] := 2.0; data[7] := 2.0;
  (* Cluster B *)
  data[8]  := 5.0; data[9]  := 5.0;
  data[10] := 6.0; data[11] := 5.0;
  data[12] := 5.0; data[13] := 6.0;
  data[14] := 6.0; data[15] := 6.0;

  labels[0] := 1.0;  labels[1] := 1.0;
  labels[2] := 1.0;  labels[3] := 1.0;
  labels[4] := -1.0; labels[5] := -1.0;
  labels[6] := -1.0; labels[7] := -1.0;

  SVM.Init(m, 2, 10.0, Linear, 0.0);
  SVM.Train(m, ADR(data), ADR(labels), 8, 2);

  testA[0] := 1.5; testA[1] := 1.5;
  testB[0] := 5.5; testB[1] := 5.5;

  predA := SVM.Predict(m, ADR(testA));
  predB := SVM.Predict(m, ADR(testB));

  Check("T1 linear SVM cluster A positive", predA > 0.0);
  Check("T1 linear SVM cluster B negative", predB < 0.0);

  SVM.Free(m)
END Test1;

(* ── Test 2: RBF SVM on XOR-like data ───────────────── *)

PROCEDURE Test2;
VAR
  m: SVMModel;
  (* XOR pattern: (0,0)->+1, (1,1)->+1, (0,1)->-1, (1,0)->-1
     Use offset points for margin *)
  data: ARRAY [0..15] OF LONGREAL;
  labels: ARRAY [0..7] OF LONGREAL;
  test: ARRAY [0..1] OF LONGREAL;
  pred: LONGREAL;
BEGIN
  (* Class +1: near (0,0) and (1,1) *)
  data[0] := 0.0; data[1] := 0.0;
  data[2] := 0.1; data[3] := 0.1;
  data[4] := 1.0; data[5] := 1.0;
  data[6] := 0.9; data[7] := 0.9;
  (* Class -1: near (0,1) and (1,0) *)
  data[8]  := 0.0; data[9]  := 1.0;
  data[10] := 0.1; data[11] := 0.9;
  data[12] := 1.0; data[13] := 0.0;
  data[14] := 0.9; data[15] := 0.1;

  labels[0] := 1.0;  labels[1] := 1.0;
  labels[2] := 1.0;  labels[3] := 1.0;
  labels[4] := -1.0; labels[5] := -1.0;
  labels[6] := -1.0; labels[7] := -1.0;

  SVM.Init(m, 2, 100.0, RBF, 5.0);
  SVM.Train(m, ADR(data), ADR(labels), 8, 2);

  test[0] := 0.05; test[1] := 0.05;
  pred := SVM.Predict(m, ADR(test));
  Check("T2 RBF XOR (0,0) region positive", pred > 0.0);

  test[0] := 0.95; test[1] := 0.95;
  pred := SVM.Predict(m, ADR(test));
  Check("T2 RBF XOR (1,1) region positive", pred > 0.0);

  test[0] := 0.05; test[1] := 0.95;
  pred := SVM.Predict(m, ADR(test));
  Check("T2 RBF XOR (0,1) region negative", pred < 0.0);

  test[0] := 0.95; test[1] := 0.05;
  pred := SVM.Predict(m, ADR(test));
  Check("T2 RBF XOR (1,0) region negative", pred < 0.0);

  SVM.Free(m)
END Test2;

(* ── Test 3: Multi-class one-vs-rest on 3 classes ──── *)

PROCEDURE Test3;
VAR
  ms: MultiSVM;
  (* 9 samples x 2 features, 3 classes:
     class 0: (1,1), (1.5,1), (1,1.5)
     class 1: (5,1), (5.5,1), (5,1.5)
     class 2: (3,5), (3.5,5), (3,5.5) *)
  data: ARRAY [0..17] OF LONGREAL;
  labels: ARRAY [0..8] OF INTEGER;
  test: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  scores: ARRAY [0..2] OF LONGREAL;
BEGIN
  (* Class 0 *)
  data[0] := 1.0; data[1] := 1.0;
  data[2] := 1.5; data[3] := 1.0;
  data[4] := 1.0; data[5] := 1.5;
  (* Class 1 *)
  data[6] := 5.0;  data[7] := 1.0;
  data[8] := 5.5;  data[9] := 1.0;
  data[10] := 5.0; data[11] := 1.5;
  (* Class 2 *)
  data[12] := 3.0; data[13] := 5.0;
  data[14] := 3.5; data[15] := 5.0;
  data[16] := 3.0; data[17] := 5.5;

  labels[0] := 0; labels[1] := 0; labels[2] := 0;
  labels[3] := 1; labels[4] := 1; labels[5] := 1;
  labels[6] := 2; labels[7] := 2; labels[8] := 2;

  SVM.InitMulti(ms, 3, 2, 10.0, Linear, 0.0);
  SVM.TrainMulti(ms, ADR(data), ADR(labels), 9, 2);

  test[0] := 1.2; test[1] := 1.2;
  pred := SVM.PredictMulti(ms, ADR(test));
  Check("T3 multi-class predict class 0", pred = 0);

  test[0] := 5.2; test[1] := 1.2;
  pred := SVM.PredictMulti(ms, ADR(test));
  Check("T3 multi-class predict class 1", pred = 1);

  test[0] := 3.2; test[1] := 5.2;
  pred := SVM.PredictMulti(ms, ADR(test));
  Check("T3 multi-class predict class 2", pred = 2);

  (* Test PredictMultiProba returns scores *)
  test[0] := 1.2; test[1] := 1.2;
  pred := SVM.PredictMultiProba(ms, ADR(test), scores);
  Check("T3 PredictMultiProba class 0 score highest",
        (scores[0] > scores[1]) AND (scores[0] > scores[2]));

  SVM.FreeMulti(ms)
END Test3;

(* ── Test 4: Predict sign matches training labels ──── *)

PROCEDURE Test4;
VAR
  m: SVMModel;
  data: ARRAY [0..11] OF LONGREAL;
  labels: ARRAY [0..5] OF LONGREAL;
  test: ARRAY [0..1] OF LONGREAL;
  pred: LONGREAL;
  i: CARDINAL;
  allCorrect: BOOLEAN;
  pr: RealPtr;
BEGIN
  (* Well-separated clusters *)
  data[0] := 0.0; data[1] := 0.0;
  data[2] := 0.5; data[3] := 0.0;
  data[4] := 0.0; data[5] := 0.5;
  data[6] := 5.0; data[7] := 5.0;
  data[8] := 5.5; data[9] := 5.0;
  data[10] := 5.0; data[11] := 5.5;

  labels[0] := 1.0;  labels[1] := 1.0;  labels[2] := 1.0;
  labels[3] := -1.0; labels[4] := -1.0; labels[5] := -1.0;

  SVM.Init(m, 2, 10.0, Linear, 0.0);
  SVM.Train(m, ADR(data), ADR(labels), 6, 2);

  allCorrect := TRUE;
  FOR i := 0 TO 5 DO
    test[0] := data[i * 2];
    test[1] := data[i * 2 + 1];
    pred := SVM.Predict(m, ADR(test));
    pr := ElemR(ADR(labels), i);
    IF pr^ > 0.0 THEN
      IF pred <= 0.0 THEN allCorrect := FALSE END
    ELSE
      IF pred >= 0.0 THEN allCorrect := FALSE END
    END
  END;

  Check("T4 predict sign matches all training labels", allCorrect);

  SVM.Free(m)
END Test4;

(* ── Test 5: Convergence — model becomes trained ───── *)

PROCEDURE Test5;
VAR
  m: SVMModel;
  data: ARRAY [0..7] OF LONGREAL;
  labels: ARRAY [0..3] OF LONGREAL;
BEGIN
  data[0] := 0.0; data[1] := 0.0;
  data[2] := 1.0; data[3] := 0.0;
  data[4] := 5.0; data[5] := 5.0;
  data[6] := 6.0; data[7] := 5.0;

  labels[0] := 1.0;  labels[1] := 1.0;
  labels[2] := -1.0; labels[3] := -1.0;

  SVM.Init(m, 2, 1.0, Linear, 0.0);
  Check("T5 model not trained before Train", NOT m.trained);

  SVM.Train(m, ADR(data), ADR(labels), 4, 2);
  Check("T5 model trained after Train", m.trained);

  (* Verify alphas were allocated *)
  Check("T5 alphas allocated", m.alphas # NIL);
  Check("T5 trainData allocated", m.trainData # NIL);

  SVM.Free(m);
  Check("T5 alphas freed", m.alphas = NIL);
  Check("T5 trainData freed", m.trainData = NIL)
END Test5;

(* ── Main ────────────────────────────────────────────── *)

BEGIN
  passed := 0;
  failed := 0;
  total  := 0;

  WriteString("=== m2svm test suite ==="); WriteLn;
  WriteLn;

  Test1;
  Test2;
  Test3;
  Test4;
  Test5;

  WriteLn;
  WriteString("Passed: "); WriteInt(passed, 0); WriteLn;
  WriteString("Failed: "); WriteInt(failed, 0); WriteLn;
  WriteString("Total:  "); WriteInt(total, 0); WriteLn;

  IF failed = 0 THEN
    WriteString("All tests passed."); WriteLn
  ELSE
    WriteString("*** SOME TESTS FAILED ***"); WriteLn
  END
END SvmTests.
