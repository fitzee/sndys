IMPLEMENTATION MODULE KMeans;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr = POINTER TO INTEGER;


(* --- Helper: access element of LONGREAL array at given index --- *)

PROCEDURE GetReal(base: ADDRESS; idx: CARDINAL): LONGREAL;
VAR
  p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(LONGREAL)));
  RETURN p^
END GetReal;


PROCEDURE SetReal(base: ADDRESS; idx: CARDINAL; val: LONGREAL);
VAR
  p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(LONGREAL)));
  p^ := val
END SetReal;


(* --- Helper: access element of INTEGER array at given index --- *)

PROCEDURE GetInt(base: ADDRESS; idx: CARDINAL): INTEGER;
VAR
  p: IntPtr;
BEGIN
  p := IntPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(INTEGER)));
  RETURN p^
END GetInt;


PROCEDURE SetInt(base: ADDRESS; idx: CARDINAL; val: INTEGER);
VAR
  p: IntPtr;
BEGIN
  p := IntPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(INTEGER)));
  p^ := val
END SetInt;


(* --- Euclidean distance squared between two points --- *)

PROCEDURE DistSq(data1: ADDRESS; off1: CARDINAL;
                 data2: ADDRESS; off2: CARDINAL;
                 nf: CARDINAL): LONGREAL;
VAR
  j: CARDINAL;
  diff, sum: LONGREAL;
BEGIN
  sum := 0.0;
  FOR j := 0 TO nf - 1 DO
    diff := GetReal(data1, off1 + j) - GetReal(data2, off2 + j);
    sum := sum + diff * diff
  END;
  RETURN sum
END DistSq;


(* --- Init: allocate centroids and labels --- *)

PROCEDURE Init(VAR r: KMeansResult; k, nFeatures: CARDINAL);
BEGIN
  r.numClusters := k;
  r.numFeatures := nFeatures;
  r.numSamples := 0;
  r.iterations := 0;
  r.converged := FALSE;
  r.centroids := NIL;
  r.labels := NIL
END Init;


(* --- Fit: run K-Means clustering --- *)

PROCEDURE Fit(VAR r: KMeansResult;
              data: ADDRESS;
              numSamples, numFeatures, numClusters, maxIter: CARDINAL;
              tolerance: LONGREAL);
VAR
  i, j, k, iter, nearest: CARDINAL;
  dist, minDist, shift, maxShift, oldVal, newVal: LONGREAL;
  counts: ADDRESS;
  oldCentroids: ADDRESS;
  centroidsSize, labelsSize, countsSize, oldCentroidsSize: CARDINAL;
  sampleIdx: CARDINAL;
  countVal: INTEGER;
BEGIN
  (* Free any existing result buffers before overwriting *)
  IF r.centroids # NIL THEN
    DEALLOCATE(r.centroids, r.numClusters * r.numFeatures * TSIZE(LONGREAL));
    r.centroids := NIL
  END;
  IF r.labels # NIL THEN
    DEALLOCATE(r.labels, r.numSamples * TSIZE(INTEGER));
    r.labels := NIL
  END;

  r.numClusters := numClusters;
  r.numFeatures := numFeatures;
  r.numSamples := numSamples;
  r.iterations := 0;
  r.converged := FALSE;

  IF (numClusters = 0) OR (numSamples = 0) OR (numFeatures = 0) THEN
    RETURN
  END;

  (* Allocate centroids and labels *)
  centroidsSize := numClusters * numFeatures * TSIZE(LONGREAL);
  labelsSize := numSamples * TSIZE(INTEGER);
  ALLOCATE(r.centroids, centroidsSize);
  ALLOCATE(r.labels, labelsSize);

  (* Initialize centroids: pick evenly spaced samples *)
  FOR k := 0 TO numClusters - 1 DO
    sampleIdx := (k * numSamples) DIV numClusters;
    FOR j := 0 TO numFeatures - 1 DO
      SetReal(r.centroids, k * numFeatures + j,
              GetReal(data, sampleIdx * numFeatures + j))
    END
  END;

  (* Allocate temporary arrays *)
  countsSize := numClusters * TSIZE(INTEGER);
  oldCentroidsSize := numClusters * numFeatures * TSIZE(LONGREAL);
  ALLOCATE(counts, countsSize);
  ALLOCATE(oldCentroids, oldCentroidsSize);

  (* Main iteration loop *)
  FOR iter := 1 TO maxIter DO
    (* --- Assignment step: assign each sample to nearest centroid --- *)
    FOR i := 0 TO numSamples - 1 DO
      minDist := DistSq(data, i * numFeatures,
                        r.centroids, 0,
                        numFeatures);
      nearest := 0;
      FOR k := 1 TO numClusters - 1 DO
        dist := DistSq(data, i * numFeatures,
                       r.centroids, k * numFeatures,
                       numFeatures);
        IF dist < minDist THEN
          minDist := dist;
          nearest := k
        END
      END;
      SetInt(r.labels, i, INTEGER(nearest))
    END;

    (* --- Update step: recompute centroids --- *)
    (* Save old centroids for convergence check and empty-cluster recovery *)
    FOR k := 0 TO numClusters - 1 DO
      FOR j := 0 TO numFeatures - 1 DO
        SetReal(oldCentroids, k * numFeatures + j,
                GetReal(r.centroids, k * numFeatures + j))
      END
    END;

    (* Zero out centroids and counts *)
    FOR k := 0 TO numClusters - 1 DO
      SetInt(counts, k, 0);
      FOR j := 0 TO numFeatures - 1 DO
        SetReal(r.centroids, k * numFeatures + j, 0.0)
      END
    END;

    (* Sum all points belonging to each cluster *)
    FOR i := 0 TO numSamples - 1 DO
      nearest := CARDINAL(GetInt(r.labels, i));
      countVal := GetInt(counts, nearest);
      SetInt(counts, nearest, countVal + 1);
      FOR j := 0 TO numFeatures - 1 DO
        oldVal := GetReal(r.centroids, nearest * numFeatures + j);
        SetReal(r.centroids, nearest * numFeatures + j,
                oldVal + GetReal(data, i * numFeatures + j))
      END
    END;

    (* Divide by counts to get means; track max centroid shift.
       Empty clusters keep their previous centroid — this prevents
       silent collapse to the origin and keeps k clusters active. *)
    maxShift := 0.0;
    FOR k := 0 TO numClusters - 1 DO
      countVal := GetInt(counts, k);
      IF countVal > 0 THEN
        FOR j := 0 TO numFeatures - 1 DO
          newVal := GetReal(r.centroids, k * numFeatures + j) / LFLOAT(countVal);
          SetReal(r.centroids, k * numFeatures + j, newVal);
          oldVal := GetReal(oldCentroids, k * numFeatures + j);
          shift := newVal - oldVal;
          IF shift < 0.0 THEN shift := -shift END;
          IF shift > maxShift THEN maxShift := shift END
        END
      ELSE
        (* Empty cluster: restore previous centroid *)
        FOR j := 0 TO numFeatures - 1 DO
          SetReal(r.centroids, k * numFeatures + j,
                  GetReal(oldCentroids, k * numFeatures + j))
        END
      END
    END;

    r.iterations := iter;

    (* Check convergence *)
    IF maxShift < tolerance THEN
      r.converged := TRUE;
      DEALLOCATE(counts, countsSize);
      DEALLOCATE(oldCentroids, oldCentroidsSize);
      RETURN
    END
  END;

  DEALLOCATE(counts, countsSize);
  DEALLOCATE(oldCentroids, oldCentroidsSize)
END Fit;


(* --- Predict: assign a single sample to the nearest cluster --- *)

PROCEDURE Predict(VAR r: KMeansResult; sample: ADDRESS): INTEGER;
VAR
  k, nearest: CARDINAL;
  dist, minDist: LONGREAL;
BEGIN
  IF (r.centroids = NIL) OR (r.numClusters = 0) OR (r.numFeatures = 0) THEN
    RETURN -1
  END;
  minDist := DistSq(sample, 0, r.centroids, 0, r.numFeatures);
  nearest := 0;
  FOR k := 1 TO r.numClusters - 1 DO
    dist := DistSq(sample, 0, r.centroids, k * r.numFeatures, r.numFeatures);
    IF dist < minDist THEN
      minDist := dist;
      nearest := k
    END
  END;
  RETURN INTEGER(nearest)
END Predict;


(* --- PredictBatch: assign multiple samples --- *)

PROCEDURE PredictBatch(VAR r: KMeansResult;
                       data: ADDRESS;
                       numSamples: CARDINAL;
                       labels: ADDRESS);
VAR
  i, k, nearest: CARDINAL;
  dist, minDist: LONGREAL;
BEGIN
  IF (r.centroids = NIL) OR (r.numClusters = 0) OR
     (r.numFeatures = 0) OR (numSamples = 0) THEN
    RETURN
  END;
  FOR i := 0 TO numSamples - 1 DO
    minDist := DistSq(data, i * r.numFeatures,
                      r.centroids, 0, r.numFeatures);
    nearest := 0;
    FOR k := 1 TO r.numClusters - 1 DO
      dist := DistSq(data, i * r.numFeatures,
                     r.centroids, k * r.numFeatures, r.numFeatures);
      IF dist < minDist THEN
        minDist := dist;
        nearest := k
      END
    END;
    SetInt(labels, i, INTEGER(nearest))
  END
END PredictBatch;


(* --- Silhouette: compute mean silhouette score --- *)

PROCEDURE Silhouette(VAR r: KMeansResult; data: ADDRESS): LONGREAL;
VAR
  i, j, k: CARDINAL;
  label_i, label_j: INTEGER;
  ai, bi, dist, si, totalSil: LONGREAL;
  aCount: CARDINAL;
  bSums, bCounts: ADDRESS;
  bSumsSize, bCountsSize: CARDINAL;
  bSum, bCount: LONGREAL;
  minB: LONGREAL;
  maxAB: LONGREAL;
BEGIN
  IF (r.numSamples < 2) OR (r.centroids = NIL) OR
     (r.labels = NIL) OR (r.numClusters = 0) OR (r.numFeatures = 0) THEN
    RETURN 0.0
  END;

  (* Allocate arrays for per-cluster distance sums and counts *)
  bSumsSize := r.numClusters * TSIZE(LONGREAL);
  bCountsSize := r.numClusters * TSIZE(LONGREAL);
  ALLOCATE(bSums, bSumsSize);
  ALLOCATE(bCounts, bCountsSize);

  totalSil := 0.0;

  FOR i := 0 TO r.numSamples - 1 DO
    label_i := GetInt(r.labels, i);

    (* Zero out accumulators *)
    FOR k := 0 TO r.numClusters - 1 DO
      SetReal(bSums, k, 0.0);
      SetReal(bCounts, k, 0.0)
    END;

    (* Accumulate distances to all other points, grouped by cluster *)
    FOR j := 0 TO r.numSamples - 1 DO
      IF i # j THEN
        label_j := GetInt(r.labels, j);
        dist := DistSq(data, i * r.numFeatures,
                       data, j * r.numFeatures,
                       r.numFeatures);
        dist := LFLOAT(sqrt(FLOAT(dist)));
        bSum := GetReal(bSums, CARDINAL(label_j));
        SetReal(bSums, CARDINAL(label_j), bSum + dist);
        bCount := GetReal(bCounts, CARDINAL(label_j));
        SetReal(bCounts, CARDINAL(label_j), bCount + 1.0)
      END
    END;

    (* Compute a(i): mean intra-cluster distance *)
    bCount := GetReal(bCounts, CARDINAL(label_i));
    IF bCount > 0.0 THEN
      ai := GetReal(bSums, CARDINAL(label_i)) / bCount
    ELSE
      ai := 0.0
    END;

    (* Compute b(i): minimum mean inter-cluster distance *)
    minB := -1.0;
    FOR k := 0 TO r.numClusters - 1 DO
      IF INTEGER(k) # label_i THEN
        bCount := GetReal(bCounts, k);
        IF bCount > 0.0 THEN
          bi := GetReal(bSums, k) / bCount;
          IF (minB < 0.0) OR (bi < minB) THEN
            minB := bi
          END
        END
      END
    END;

    IF minB < 0.0 THEN
      minB := 0.0
    END;

    (* Silhouette for point i *)
    IF ai > minB THEN
      maxAB := ai
    ELSE
      maxAB := minB
    END;
    IF maxAB > 0.0 THEN
      si := (minB - ai) / maxAB
    ELSE
      si := 0.0
    END;

    totalSil := totalSil + si
  END;

  DEALLOCATE(bSums, bSumsSize);
  DEALLOCATE(bCounts, bCountsSize);

  RETURN totalSil / LFLOAT(r.numSamples)
END Silhouette;


(* --- FreeResult: deallocate centroids and labels --- *)

PROCEDURE FreeResult(VAR r: KMeansResult);
BEGIN
  IF r.centroids # NIL THEN
    DEALLOCATE(r.centroids, r.numClusters * r.numFeatures * TSIZE(LONGREAL));
    r.centroids := NIL
  END;
  IF r.labels # NIL THEN
    DEALLOCATE(r.labels, r.numSamples * TSIZE(INTEGER));
    r.labels := NIL
  END;
  r.numClusters := 0;
  r.numFeatures := 0;
  r.numSamples := 0;
  r.iterations := 0;
  r.converged := FALSE
END FreeResult;

END KMeans.
