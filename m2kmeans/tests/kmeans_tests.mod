MODULE kmeans_tests;

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM InOut IMPORT WriteString, WriteLn, WriteInt, WriteCard;
FROM KMeans IMPORT KMeansResult, Init, Fit, Predict, PredictBatch,
                   Silhouette, FreeResult;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr = POINTER TO INTEGER;

VAR
  passed, failed, total: CARDINAL;


(* --- Helpers --- *)

PROCEDURE SetReal(base: ADDRESS; idx: CARDINAL; val: LONGREAL);
VAR
  p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)));
  p^ := val
END SetReal;

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

PROCEDURE Abs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0 THEN
    RETURN -x
  END;
  RETURN x
END Abs;

PROCEDURE Check(name: ARRAY OF CHAR; cond: BOOLEAN);
BEGIN
  INC(total);
  WriteString(name);
  IF cond THEN
    WriteString(": PASSED");
    INC(passed)
  ELSE
    WriteString(": FAILED");
    INC(failed)
  END;
  WriteLn
END Check;

PROCEDURE CheckApprox(name: ARRAY OF CHAR; got, expect, tol: LONGREAL);
BEGIN
  Check(name, Abs(got - expect) <= tol)
END CheckApprox;


(* --- Test 1: Two well-separated clusters --- *)

PROCEDURE TestTwoClusters;
VAR
  data: ADDRESS;
  r: KMeansResult;
  l0, l1, l2, l3, l4, l5: INTEGER;
  allSame01, allSame23: BOOLEAN;
BEGIN
  (* Cluster A near (0,0): 3 points; Cluster B near (100,100): 3 points *)
  ALLOCATE(data, 6 * 2 * TSIZE(LONGREAL));
  (* Cluster A *)
  SetReal(data, 0, 0.0);  SetReal(data, 1, 0.0);
  SetReal(data, 2, 1.0);  SetReal(data, 3, 1.0);
  SetReal(data, 4, 0.5);  SetReal(data, 5, 0.5);
  (* Cluster B *)
  SetReal(data, 6, 100.0);  SetReal(data, 7, 100.0);
  SetReal(data, 8, 101.0);  SetReal(data, 9, 101.0);
  SetReal(data, 10, 100.5); SetReal(data, 11, 100.5);

  r.centroids := NIL;
  r.labels := NIL;
  Fit(r, data, 6, 2, 2, 100, 0.0001);

  l0 := GetInt(r.labels, 0);
  l1 := GetInt(r.labels, 1);
  l2 := GetInt(r.labels, 2);
  l3 := GetInt(r.labels, 3);
  l4 := GetInt(r.labels, 4);
  l5 := GetInt(r.labels, 5);

  (* Points 0,1,2 should share a label; points 3,4,5 should share a label *)
  allSame01 := (l0 = l1) AND (l1 = l2);
  allSame23 := (l3 = l4) AND (l4 = l5);

  Check("TwoClusters: cluster A consistent", allSame01);
  Check("TwoClusters: cluster B consistent", allSame23);
  Check("TwoClusters: clusters differ", l0 # l3);

  FreeResult(r);
  DEALLOCATE(data, 0)
END TestTwoClusters;


(* --- Test 2: Three clusters, verify centroids near cluster centers --- *)

PROCEDURE TestThreeClusters;
VAR
  data: ADDRESS;
  r: KMeansResult;
  k, j: CARDINAL;
  cx, cy: LONGREAL;
  foundA, foundB, foundC: BOOLEAN;
BEGIN
  (* 3 clusters of 3 points each, 2D *)
  (* A near (0,0), B near (50,0), C near (0,50) *)
  ALLOCATE(data, 9 * 2 * TSIZE(LONGREAL));
  (* Cluster A *)
  SetReal(data, 0, -1.0); SetReal(data, 1, -1.0);
  SetReal(data, 2,  0.0); SetReal(data, 3,  0.0);
  SetReal(data, 4,  1.0); SetReal(data, 5,  1.0);
  (* Cluster B *)
  SetReal(data, 6,  49.0); SetReal(data, 7, -1.0);
  SetReal(data, 8,  50.0); SetReal(data, 9,  0.0);
  SetReal(data, 10, 51.0); SetReal(data, 11, 1.0);
  (* Cluster C *)
  SetReal(data, 12, -1.0); SetReal(data, 13, 49.0);
  SetReal(data, 14,  0.0); SetReal(data, 15, 50.0);
  SetReal(data, 16,  1.0); SetReal(data, 17, 51.0);

  r.centroids := NIL;
  r.labels := NIL;
  Fit(r, data, 9, 2, 3, 100, 0.0001);

  (* Check that each expected center is close to one of the centroids *)
  foundA := FALSE;
  foundB := FALSE;
  foundC := FALSE;
  FOR k := 0 TO 2 DO
    cx := GetReal(r.centroids, k * 2);
    cy := GetReal(r.centroids, k * 2 + 1);
    IF (Abs(cx - 0.0) < 5.0) AND (Abs(cy - 0.0) < 5.0) THEN
      foundA := TRUE
    END;
    IF (Abs(cx - 50.0) < 5.0) AND (Abs(cy - 0.0) < 5.0) THEN
      foundB := TRUE
    END;
    IF (Abs(cx - 0.0) < 5.0) AND (Abs(cy - 50.0) < 5.0) THEN
      foundC := TRUE
    END
  END;

  Check("ThreeClusters: centroid near (0,0)", foundA);
  Check("ThreeClusters: centroid near (50,0)", foundB);
  Check("ThreeClusters: centroid near (0,50)", foundC);

  FreeResult(r);
  DEALLOCATE(data, 0)
END TestThreeClusters;


(* --- Test 3: Silhouette score for well-separated data --- *)

PROCEDURE TestSilhouette;
VAR
  data: ADDRESS;
  r: KMeansResult;
  score: LONGREAL;
BEGIN
  (* Two very separated clusters *)
  ALLOCATE(data, 6 * 2 * TSIZE(LONGREAL));
  SetReal(data, 0, 0.0);  SetReal(data, 1, 0.0);
  SetReal(data, 2, 1.0);  SetReal(data, 3, 0.0);
  SetReal(data, 4, 0.0);  SetReal(data, 5, 1.0);
  SetReal(data, 6, 100.0);  SetReal(data, 7, 100.0);
  SetReal(data, 8, 101.0);  SetReal(data, 9, 100.0);
  SetReal(data, 10, 100.0); SetReal(data, 11, 101.0);

  r.centroids := NIL;
  r.labels := NIL;
  Fit(r, data, 6, 2, 2, 100, 0.0001);

  score := Silhouette(r, data);

  Check("Silhouette: score > 0.8", score > 0.8);

  FreeResult(r);
  DEALLOCATE(data, 0)
END TestSilhouette;


(* --- Test 4: Predict assigns to nearest cluster --- *)

PROCEDURE TestPredict;
VAR
  data, sample: ADDRESS;
  r: KMeansResult;
  label_i: INTEGER;
  l0: INTEGER;
BEGIN
  (* Train on two clusters *)
  ALLOCATE(data, 4 * 2 * TSIZE(LONGREAL));
  SetReal(data, 0, 0.0); SetReal(data, 1, 0.0);
  SetReal(data, 2, 1.0); SetReal(data, 3, 1.0);
  SetReal(data, 4, 100.0); SetReal(data, 5, 100.0);
  SetReal(data, 6, 101.0); SetReal(data, 7, 101.0);

  r.centroids := NIL;
  r.labels := NIL;
  Fit(r, data, 4, 2, 2, 100, 0.0001);

  (* Get the label of point (0,0) *)
  l0 := GetInt(r.labels, 0);

  (* Predict a new point near cluster A *)
  ALLOCATE(sample, 2 * TSIZE(LONGREAL));
  SetReal(sample, 0, 2.0);
  SetReal(sample, 1, 2.0);

  label_i := Predict(r, sample);
  Check("Predict: new point near cluster A", label_i = l0);

  (* Predict a point near cluster B *)
  SetReal(sample, 0, 99.0);
  SetReal(sample, 1, 99.0);
  label_i := Predict(r, sample);
  Check("Predict: new point near cluster B", label_i # l0);

  DEALLOCATE(sample, 0);
  FreeResult(r);
  DEALLOCATE(data, 0)
END TestPredict;


(* --- Test 5: Convergence within reasonable iterations --- *)

PROCEDURE TestConvergence;
VAR
  data: ADDRESS;
  r: KMeansResult;
BEGIN
  (* Simple data that should converge quickly *)
  ALLOCATE(data, 4 * 1 * TSIZE(LONGREAL));
  SetReal(data, 0, 0.0);
  SetReal(data, 1, 1.0);
  SetReal(data, 2, 100.0);
  SetReal(data, 3, 101.0);

  r.centroids := NIL;
  r.labels := NIL;
  Fit(r, data, 4, 1, 2, 1000, 0.0001);

  Check("Convergence: converged flag set", r.converged);
  Check("Convergence: iterations < 50", r.iterations < 50);

  FreeResult(r);
  DEALLOCATE(data, 0)
END TestConvergence;


BEGIN
  passed := 0;
  failed := 0;
  total := 0;

  WriteString("=== m2kmeans tests ===");
  WriteLn;

  TestTwoClusters;
  TestThreeClusters;
  TestSilhouette;
  TestPredict;
  TestConvergence;

  WriteLn;
  WriteString("Results: ");
  WriteCard(passed, 0);
  WriteString(" passed, ");
  WriteCard(failed, 0);
  WriteString(" failed, ");
  WriteCard(total, 0);
  WriteString(" total");
  WriteLn
END kmeans_tests.
