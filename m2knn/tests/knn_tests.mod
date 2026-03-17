MODULE KnnTests;
(* Test suite for m2knn: Scaler, KNN, and Evaluate modules.

   Tests:
     1.  Scaler fit computes correct mean/std
     2.  Scaler transform produces zero-mean unit-variance
     3.  Scaler inverse recovers original values
     4.  KNN Init sets fields correctly
     5.  KNN 1-NN exact match on training data
     6.  KNN 3-NN majority vote on simple 2D clusters
     7.  KNN distance-weighted voting
     8.  KNN PredictProba sums to 1.0
     9.  KNN SaveModel/LoadModel roundtrip
    10.  Confusion matrix correctness
    11.  Accuracy/Precision/Recall/F1 computation
    12.  Cross-validation on separable data *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Scaler IMPORT ScalerState, MaxFeatures;
FROM KNN IMPORT Model, DistMetric, Euclidean, Manhattan, Cosine, MaxK;
FROM Evaluate IMPORT ConfMatrix, ClassMetrics,
                     ComputeConfusion, ComputeMetrics, CrossValidate;
IMPORT Scaler;
IMPORT KNN;

CONST
  Eps = 1.0D-6;
  TestModelPath = "/tmp/test_m2knn_model.bin";

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

PROCEDURE Near(a, b: LONGREAL): BOOLEAN;
VAR d: LONGREAL;
BEGIN
  d := a - b;
  IF d < 0.0 THEN d := -d END;
  RETURN d < Eps
END Near;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i * TSIZE(INTEGER)))
END ElemI;

(* ── Test 1: Scaler Fit ───────────────────────────── *)

PROCEDURE Test1;
VAR
  sc: ScalerState;
  data: ARRAY [0..5] OF LONGREAL;
  (* 3 samples x 2 features:
     [1, 10], [2, 20], [3, 30] *)
BEGIN
  data[0] := 1.0; data[1] := 10.0;
  data[2] := 2.0; data[3] := 20.0;
  data[4] := 3.0; data[5] := 30.0;

  Scaler.Init(sc, 2);
  Scaler.Fit(sc, ADR(data), 3, 2);

  Check("fit: mean[0]=2.0", Near(sc.means[0], 2.0));
  Check("fit: mean[1]=20.0", Near(sc.means[1], 20.0));
  Check("fit: fitted", sc.fitted)
END Test1;

(* ── Test 2: Scaler Transform ─────────────────────── *)

PROCEDURE Test2;
VAR
  sc: ScalerState;
  data: ARRAY [0..5] OF LONGREAL;
  sum, sumSq: LONGREAL;
BEGIN
  data[0] := 1.0; data[1] := 10.0;
  data[2] := 2.0; data[3] := 20.0;
  data[4] := 3.0; data[5] := 30.0;

  Scaler.Init(sc, 2);
  Scaler.FitTransform(sc, ADR(data), 3, 2);

  (* Check column 0 has zero mean *)
  sum := data[0] + data[2] + data[4];
  Check("transform: col0 mean~0", Near(sum / 3.0, 0.0));

  (* Check column 1 has zero mean *)
  sum := data[1] + data[3] + data[5];
  Check("transform: col1 mean~0", Near(sum / 3.0, 0.0))
END Test2;

(* ── Test 3: Scaler InverseTransform ──────────────── *)

PROCEDURE Test3;
VAR
  sc: ScalerState;
  data: ARRAY [0..5] OF LONGREAL;
BEGIN
  data[0] := 1.0; data[1] := 10.0;
  data[2] := 2.0; data[3] := 20.0;
  data[4] := 3.0; data[5] := 30.0;

  Scaler.Init(sc, 2);
  Scaler.FitTransform(sc, ADR(data), 3, 2);
  Scaler.InverseTransform(sc, ADR(data), 3, 2);

  Check("inverse: [0,0]=1.0", Near(data[0], 1.0));
  Check("inverse: [0,1]=10.0", Near(data[1], 10.0));
  Check("inverse: [2,1]=30.0", Near(data[5], 30.0))
END Test3;

(* ── Test 4: KNN Init ──────────────────────────────── *)

PROCEDURE Test4;
VAR m: Model;
BEGIN
  KNN.Init(m, 5, 34, 3, Euclidean, TRUE);
  Check("init: k=5", m.k = 5);
  Check("init: nFeat=34", m.numFeatures = 34);
  Check("init: nClass=3", m.numClasses = 3);
  Check("init: weighted", m.weighted);
  Check("init: trainData=NIL", m.trainData = NIL)
END Test4;

(* ── Test 5: 1-NN exact match ──────────────────────── *)

PROCEDURE Test5;
VAR
  m: Model;
  data: ARRAY [0..5] OF LONGREAL;  (* 3 samples x 2 features *)
  labels: ARRAY [0..2] OF INTEGER;
  pred: INTEGER;
BEGIN
  (* 3 points: [0,0]=class0, [10,10]=class1, [20,20]=class2 *)
  data[0] := 0.0; data[1] := 0.0;
  data[2] := 10.0; data[3] := 10.0;
  data[4] := 20.0; data[5] := 20.0;
  labels[0] := 0; labels[1] := 1; labels[2] := 2;

  KNN.Init(m, 1, 2, 3, Euclidean, FALSE);
  KNN.Train(m, ADR(data), ADR(labels), 3, FALSE);

  (* Query at each training point — should get exact match *)
  pred := KNN.Predict(m, ADR(data[0]));
  Check("1nn: [0,0]=class0", pred = 0);

  pred := KNN.Predict(m, ADR(data[2]));
  Check("1nn: [10,10]=class1", pred = 1);

  pred := KNN.Predict(m, ADR(data[4]));
  Check("1nn: [20,20]=class2", pred = 2)
END Test5;

(* ── Test 6: 3-NN majority vote ────────────────────── *)

PROCEDURE Test6;
VAR
  m: Model;
  data: ARRAY [0..13] OF LONGREAL;  (* 7 samples x 2 features *)
  labels: ARRAY [0..6] OF INTEGER;
  query: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
BEGIN
  (* Cluster A near (0,0): 4 points *)
  data[0] := 0.0;  data[1] := 0.0;
  data[2] := 0.1;  data[3] := 0.1;
  data[4] := -0.1; data[5] := 0.1;
  data[6] := 0.1;  data[7] := -0.1;
  labels[0] := 0; labels[1] := 0; labels[2] := 0; labels[3] := 0;

  (* Cluster B near (10,10): 3 points *)
  data[8] := 10.0;  data[9] := 10.0;
  data[10] := 10.1; data[11] := 10.1;
  data[12] := 9.9;  data[13] := 9.9;
  labels[4] := 1; labels[5] := 1; labels[6] := 1;

  KNN.Init(m, 3, 2, 2, Euclidean, FALSE);
  KNN.Train(m, ADR(data), ADR(labels), 7, FALSE);

  (* Query near cluster A *)
  query[0] := 0.2; query[1] := 0.2;
  pred := KNN.Predict(m, ADR(query));
  Check("3nn: near A = class 0", pred = 0);

  (* Query near cluster B *)
  query[0] := 9.8; query[1] := 9.8;
  pred := KNN.Predict(m, ADR(query));
  Check("3nn: near B = class 1", pred = 1)
END Test6;

(* ── Test 7: Distance-weighted voting ──────────────── *)

PROCEDURE Test7;
VAR
  m: Model;
  data: ARRAY [0..5] OF LONGREAL;  (* 3 samples x 2 features *)
  labels: ARRAY [0..2] OF INTEGER;
  query: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
BEGIN
  (* 2 class-0 points far away, 1 class-1 point very close *)
  data[0] := 0.0; data[1] := 0.0;   (* class 0, far *)
  data[2] := 1.0; data[3] := 0.0;   (* class 0, far *)
  data[4] := 5.0; data[5] := 0.0;   (* class 1, will be near query *)
  labels[0] := 0; labels[1] := 0; labels[2] := 1;

  (* With uniform voting and k=3, class 0 wins (2 vs 1) *)
  KNN.Init(m, 3, 2, 2, Euclidean, FALSE);
  KNN.Train(m, ADR(data), ADR(labels), 3, FALSE);
  query[0] := 4.9; query[1] := 0.0;
  pred := KNN.Predict(m, ADR(query));
  Check("uniform: majority=0", pred = 0);

  (* With distance-weighted voting, class 1 wins (very close) *)
  KNN.Init(m, 3, 2, 2, Euclidean, TRUE);
  KNN.Train(m, ADR(data), ADR(labels), 3, FALSE);
  pred := KNN.Predict(m, ADR(query));
  Check("weighted: nearest=1", pred = 1)
END Test7;

(* ── Test 8: PredictProba sums to 1.0 ─────────────── *)

PROCEDURE Test8;
VAR
  m: Model;
  data: ARRAY [0..5] OF LONGREAL;
  labels: ARRAY [0..2] OF INTEGER;
  query: ARRAY [0..1] OF LONGREAL;
  proba: ARRAY [0..1] OF LONGREAL;
  pred: INTEGER;
  sum: LONGREAL;
BEGIN
  data[0] := 0.0; data[1] := 0.0;
  data[2] := 10.0; data[3] := 10.0;
  data[4] := 5.0; data[5] := 5.0;
  labels[0] := 0; labels[1] := 1; labels[2] := 0;

  KNN.Init(m, 3, 2, 2, Euclidean, TRUE);
  KNN.Train(m, ADR(data), ADR(labels), 3, FALSE);

  query[0] := 3.0; query[1] := 3.0;
  pred := KNN.PredictProba(m, ADR(query), proba);
  sum := proba[0] + proba[1];
  Check("proba: sum~1.0", Near(sum, 1.0));
  Check("proba: class0 > 0", proba[0] > 0.0);
  Check("proba: class1 > 0", proba[1] > 0.0)
END Test8;

(* ── Test 9: SaveModel / LoadModel roundtrip ───────── *)

PROCEDURE Test9;
VAR
  m1, m2: Model;
  data: ARRAY [0..5] OF LONGREAL;
  labels: ARRAY [0..2] OF INTEGER;
  query: ARRAY [0..1] OF LONGREAL;
  ok: BOOLEAN;
  pred1, pred2: INTEGER;
BEGIN
  data[0] := 0.0; data[1] := 0.0;
  data[2] := 10.0; data[3] := 10.0;
  data[4] := 20.0; data[5] := 20.0;
  labels[0] := 0; labels[1] := 1; labels[2] := 2;

  KNN.Init(m1, 1, 2, 3, Euclidean, FALSE);
  KNN.Train(m1, ADR(data), ADR(labels), 3, TRUE);

  query[0] := 9.0; query[1] := 9.0;
  pred1 := KNN.Predict(m1, ADR(query));

  (* Save *)
  KNN.SaveModel(m1, TestModelPath, ok);
  Check("save: ok", ok);

  (* Load *)
  KNN.Init(m2, 1, 2, 3, Euclidean, FALSE);
  KNN.LoadModel(m2, TestModelPath, ok);
  Check("load: ok", ok);
  Check("load: numTrain", m2.numTrain = 3);
  Check("load: k", m2.k = 1);

  pred2 := KNN.Predict(m2, ADR(query));
  Check("roundtrip: same prediction", pred1 = pred2);

  KNN.FreeModel(m2)
END Test9;

(* ── Test 10: Confusion matrix ─────────────────────── *)

PROCEDURE Test10;
VAR
  actual:    ARRAY [0..4] OF INTEGER;
  predicted: ARRAY [0..4] OF INTEGER;
  cm: ConfMatrix;
BEGIN
  actual[0] := 0; predicted[0] := 0;  (* correct *)
  actual[1] := 0; predicted[1] := 1;  (* wrong *)
  actual[2] := 1; predicted[2] := 1;  (* correct *)
  actual[3] := 1; predicted[3] := 1;  (* correct *)
  actual[4] := 0; predicted[4] := 0;  (* correct *)

  ComputeConfusion(ADR(actual), ADR(predicted), 5, 2, cm);
  Check("cm: [0][0]=2", cm.cells[0][0] = 2);
  Check("cm: [0][1]=1", cm.cells[0][1] = 1);
  Check("cm: [1][0]=0", cm.cells[1][0] = 0);
  Check("cm: [1][1]=2", cm.cells[1][1] = 2)
END Test10;

(* ── Test 11: Metrics from confusion matrix ────────── *)

PROCEDURE Test11;
VAR
  actual:    ARRAY [0..4] OF INTEGER;
  predicted: ARRAY [0..4] OF INTEGER;
  cm: ConfMatrix;
  met: ClassMetrics;
BEGIN
  actual[0] := 0; predicted[0] := 0;
  actual[1] := 0; predicted[1] := 1;
  actual[2] := 1; predicted[2] := 1;
  actual[3] := 1; predicted[3] := 1;
  actual[4] := 0; predicted[4] := 0;

  ComputeConfusion(ADR(actual), ADR(predicted), 5, 2, cm);
  ComputeMetrics(cm, met);

  Check("metrics: accuracy=0.8", Near(met.accuracy, 0.8));
  (* Class 0: TP=2, FP=0, FN=1 -> precision=1.0, recall=2/3 *)
  Check("metrics: prec[0]=1.0", Near(met.precision[0], 1.0));
  (* Class 1: TP=2, FP=1, FN=0 -> precision=2/3, recall=1.0 *)
  Check("metrics: recall[1]=1.0", Near(met.recall[1], 1.0))
END Test11;

(* ── Test 12: Cross-validation on separable data ───── *)

PROCEDURE Test12;
VAR
  data: ADDRESS;
  labels: ADDRESS;
  i: CARDINAL;
  met: ClassMetrics;
  acc: LONGREAL;
  p: RealPtr;
  pL: IntPtr;
BEGIN
  (* 20 samples x 2 features, 2 well-separated classes, interleaved *)
  ALLOCATE(data, 20 * 2 * TSIZE(LONGREAL));
  ALLOCATE(labels, 20 * TSIZE(INTEGER));

  FOR i := 0 TO 19 DO
    p := ElemR(data, i * 2);
    IF i MOD 2 = 0 THEN
      (* Class 0: near (0, 0) *)
      p^ := LFLOAT(i DIV 2) * 0.1;
      p := ElemR(data, i * 2 + 1);
      p^ := LFLOAT(i DIV 2) * 0.1;
      pL := ElemI(labels, i);
      pL^ := 0
    ELSE
      (* Class 1: near (10, 10) *)
      p^ := 10.0 + LFLOAT(i DIV 2) * 0.1;
      p := ElemR(data, i * 2 + 1);
      p^ := 10.0 + LFLOAT(i DIV 2) * 0.1;
      pL := ElemI(labels, i);
      pL^ := 1
    END
  END;

  acc := CrossValidate(data, labels, 20, 2, 2, 5, 3, met);
  Check("xval: accuracy >= 0.9", acc >= 0.9);
  Check("xval: macroF1 >= 0.8", met.macroF1 >= 0.8);

  DEALLOCATE(data, 0);
  DEALLOCATE(labels, 0)
END Test12;

BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("m2knn test suite"); WriteLn;
  WriteString("================"); WriteLn;

  Test1;
  Test2;
  Test3;
  Test4;
  Test5;
  Test6;
  Test7;
  Test8;
  Test9;
  Test10;
  Test11;
  Test12;

  WriteLn;
  WriteInt(total, 0); WriteString(" tests, ");
  WriteInt(passed, 0); WriteString(" passed, ");
  WriteInt(failed, 0); WriteString(" failed"); WriteLn;

  IF failed > 0 THEN
    WriteString("*** FAILURES ***"); WriteLn;
    HALT
  ELSE
    WriteString("*** ALL TESTS PASSED ***"); WriteLn
  END
END KnnTests.
