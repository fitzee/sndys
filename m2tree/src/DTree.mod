IMPLEMENTATION MODULE DTree;

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr = POINTER TO INTEGER;
  CardPtr = POINTER TO CARDINAL;
  NodePtr = POINTER TO TreeNode;

(* ---- Pointer arithmetic helpers ---- *)

PROCEDURE GetReal(base: ADDRESS; idx: CARDINAL): LONGREAL;
VAR
  p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(LONGREAL)));
  RETURN p^
END GetReal;

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

PROCEDURE SetInt(base: ADDRESS; idx: CARDINAL; val: INTEGER);
VAR
  p: IntPtr;
BEGIN
  p := IntPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(INTEGER)));
  p^ := val
END SetInt;

PROCEDURE GetCard(base: ADDRESS; idx: CARDINAL): CARDINAL;
VAR
  p: CardPtr;
BEGIN
  p := CardPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(CARDINAL)));
  RETURN p^
END GetCard;

PROCEDURE SetCard(base: ADDRESS; idx: CARDINAL; val: CARDINAL);
VAR
  p: CardPtr;
BEGIN
  p := CardPtr(LONGCARD(base) + LONGCARD(idx * TSIZE(CARDINAL)));
  p^ := val
END SetCard;

PROCEDURE GetNode(base: ADDRESS; idx: CARDINAL): NodePtr;
BEGIN
  RETURN NodePtr(LONGCARD(base) + LONGCARD(idx * TSIZE(TreeNode)))
END GetNode;

(* ---- Data access: row-major data[sample][feature] ---- *)

PROCEDURE GetFeature(data: ADDRESS; sample, feature, numFeatures: CARDINAL): LONGREAL;
BEGIN
  RETURN GetReal(data, sample * numFeatures + feature)
END GetFeature;

(* ---- LCG pseudo-random ---- *)

PROCEDURE LCGNext(seed: CARDINAL): CARDINAL;
BEGIN
  RETURN (seed * 1103515245 + 12345) MOD 2147483648
END LCGNext;

(* ---- Tree init ---- *)

PROCEDURE Init(VAR t: Tree; nFeatures, nClasses, maxDepth: CARDINAL);
VAR
  estimatedNodes: CARDINAL;
BEGIN
  (* Estimate max nodes: 2^(maxDepth+1) - 1, capped *)
  estimatedNodes := 1;
  IF maxDepth <= 15 THEN
    estimatedNodes := 1;
    (* Shift left by (maxDepth+1) *)
    estimatedNodes := Power2(maxDepth + 1) - 1
  ELSE
    estimatedNodes := 65535
  END;
  IF estimatedNodes > 65535 THEN
    estimatedNodes := 65535
  END;

  t.numNodes := 0;
  t.maxNodes := estimatedNodes;
  t.numFeatures := nFeatures;
  t.numClasses := nClasses;
  t.maxDepth := maxDepth;
  ALLOCATE(t.nodes, estimatedNodes * TSIZE(TreeNode))
END Init;

PROCEDURE Power2(n: CARDINAL): CARDINAL;
VAR
  result, i: CARDINAL;
BEGIN
  result := 1;
  FOR i := 1 TO n DO
    result := result * 2;
    IF result > 65536 THEN
      RETURN 65536
    END
  END;
  RETURN result
END Power2;

(* ---- Allocate a new node, return its index ---- *)

PROCEDURE AllocNode(VAR t: Tree): INTEGER;
VAR
  idx: CARDINAL;
  np: NodePtr;
BEGIN
  IF t.numNodes >= t.maxNodes THEN
    RETURN -1
  END;
  idx := t.numNodes;
  INC(t.numNodes);
  np := GetNode(t.nodes, idx);
  np^.featureIdx := -1;
  np^.threshold := 0.0;
  np^.leftChild := -1;
  np^.rightChild := -1;
  np^.classLabel := 0;
  np^.numSamples := 0;
  RETURN INTEGER(idx)
END AllocNode;

(* ---- Gini impurity ---- *)

PROCEDURE ComputeGini(classCounts: ADDRESS; numClasses, totalSamples: CARDINAL): LONGREAL;
VAR
  gini, p: LONGREAL;
  i, cnt: CARDINAL;
BEGIN
  IF totalSamples = 0 THEN
    RETURN 1.0
  END;
  gini := 1.0;
  FOR i := 0 TO numClasses - 1 DO
    cnt := GetCard(classCounts, i);
    p := LFLOAT(cnt) / LFLOAT(totalSamples);
    gini := gini - p * p
  END;
  RETURN gini
END ComputeGini;

(* ---- Majority class ---- *)

PROCEDURE MajorityClass(labels: ADDRESS; indices: ADDRESS;
                        numSamples, numClasses: CARDINAL): INTEGER;
VAR
  counts: ARRAY [0..31] OF CARDINAL;
  i, cls, bestCount: CARDINAL;
  bestClass: INTEGER;
  sampleIdx: CARDINAL;
BEGIN
  FOR i := 0 TO numClasses - 1 DO
    counts[i] := 0
  END;

  FOR i := 0 TO numSamples - 1 DO
    sampleIdx := GetCard(indices, i);
    cls := CARDINAL(GetInt(labels, sampleIdx));
    IF cls < numClasses THEN
      INC(counts[cls])
    END
  END;

  bestClass := 0;
  bestCount := 0;
  FOR i := 0 TO numClasses - 1 DO
    IF counts[i] > bestCount THEN
      bestCount := counts[i];
      bestClass := INTEGER(i)
    END
  END;
  RETURN bestClass
END MajorityClass;

(* ---- Check if node is pure ---- *)

PROCEDURE IsPure(labels: ADDRESS; indices: ADDRESS;
                 numSamples: CARDINAL): BOOLEAN;
VAR
  i, sampleIdx: CARDINAL;
  firstLabel, lbl: INTEGER;
BEGIN
  IF numSamples <= 1 THEN
    RETURN TRUE
  END;
  sampleIdx := GetCard(indices, 0);
  firstLabel := GetInt(labels, sampleIdx);
  FOR i := 1 TO numSamples - 1 DO
    sampleIdx := GetCard(indices, i);
    lbl := GetInt(labels, sampleIdx);
    IF lbl # firstLabel THEN
      RETURN FALSE
    END
  END;
  RETURN TRUE
END IsPure;

(* ---- Find best split for a node ---- *)

PROCEDURE FindBestSplit(data: ADDRESS; labels: ADDRESS;
                        indices: ADDRESS; numSamples, numFeatures,
                        numClasses: CARDINAL;
                        featureMask: ADDRESS; numMaskFeatures: CARDINAL;
                        useRandomThresholds: BOOLEAN; VAR rngSeed: CARDINAL;
                        VAR bestFeature: INTEGER; VAR bestThreshold: LONGREAL;
                        VAR bestGini: LONGREAL);
VAR
  feat, fi, t, i, sampleIdx: CARDINAL;
  leftCounts, rightCounts: ARRAY [0..31] OF CARDINAL;
  leftTotal, rightTotal: CARDINAL;
  minVal, maxVal, threshold, fVal, giniLeft, giniRight, giniSplit: LONGREAL;
  cls: CARDINAL;
  numThresholds: CARDINAL;
  featureToTry: CARDINAL;
BEGIN
  bestGini := 999.0;
  bestFeature := -1;
  bestThreshold := 0.0;
  numThresholds := 20;

  FOR fi := 0 TO numMaskFeatures - 1 DO
    IF featureMask # NIL THEN
      featureToTry := GetCard(featureMask, fi)
    ELSE
      featureToTry := fi
    END;

    (* Find min/max of this feature in current subset *)
    sampleIdx := GetCard(indices, 0);
    minVal := GetFeature(data, sampleIdx, featureToTry, numFeatures);
    maxVal := minVal;
    FOR i := 1 TO numSamples - 1 DO
      sampleIdx := GetCard(indices, i);
      fVal := GetFeature(data, sampleIdx, featureToTry, numFeatures);
      IF fVal < minVal THEN
        minVal := fVal
      END;
      IF fVal > maxVal THEN
        maxVal := fVal
      END
    END;

    IF maxVal - minVal < 1.0E-12 THEN
      (* skip constant feature *)
    ELSE
      IF useRandomThresholds THEN
        (* ExtraTrees: try a single random threshold *)
        rngSeed := LCGNext(rngSeed);
        threshold := minVal + LFLOAT(rngSeed MOD 10000) / 10000.0 * (maxVal - minVal);

        (* Count left and right *)
        FOR cls := 0 TO numClasses - 1 DO
          leftCounts[cls] := 0;
          rightCounts[cls] := 0
        END;
        leftTotal := 0;
        rightTotal := 0;
        FOR i := 0 TO numSamples - 1 DO
          sampleIdx := GetCard(indices, i);
          fVal := GetFeature(data, sampleIdx, featureToTry, numFeatures);
          cls := CARDINAL(GetInt(labels, sampleIdx));
          IF cls >= numClasses THEN
            cls := 0
          END;
          IF fVal <= threshold THEN
            INC(leftCounts[cls]);
            INC(leftTotal)
          ELSE
            INC(rightCounts[cls]);
            INC(rightTotal)
          END
        END;

        IF (leftTotal > 0) AND (rightTotal > 0) THEN
          giniLeft := ComputeGini(ADR(leftCounts), numClasses, leftTotal);
          giniRight := ComputeGini(ADR(rightCounts), numClasses, rightTotal);
          giniSplit := (LFLOAT(leftTotal) * giniLeft + LFLOAT(rightTotal) * giniRight)
                       / LFLOAT(numSamples);
          IF giniSplit < bestGini THEN
            bestGini := giniSplit;
            bestFeature := INTEGER(featureToTry);
            bestThreshold := threshold
          END
        END
      ELSE
        (* Standard: try numThresholds evenly spaced thresholds *)
        FOR t := 1 TO numThresholds DO
          threshold := minVal + LFLOAT(t) / LFLOAT(numThresholds + 1) * (maxVal - minVal);

          FOR cls := 0 TO numClasses - 1 DO
            leftCounts[cls] := 0;
            rightCounts[cls] := 0
          END;
          leftTotal := 0;
          rightTotal := 0;

          FOR i := 0 TO numSamples - 1 DO
            sampleIdx := GetCard(indices, i);
            fVal := GetFeature(data, sampleIdx, featureToTry, numFeatures);
            cls := CARDINAL(GetInt(labels, sampleIdx));
            IF cls >= numClasses THEN
              cls := 0
            END;
            IF fVal <= threshold THEN
              INC(leftCounts[cls]);
              INC(leftTotal)
            ELSE
              INC(rightCounts[cls]);
              INC(rightTotal)
            END
          END;

          IF (leftTotal > 0) AND (rightTotal > 0) THEN
            giniLeft := ComputeGini(ADR(leftCounts), numClasses, leftTotal);
            giniRight := ComputeGini(ADR(rightCounts), numClasses, rightTotal);
            giniSplit := (LFLOAT(leftTotal) * giniLeft + LFLOAT(rightTotal) * giniRight)
                         / LFLOAT(numSamples);
            IF giniSplit < bestGini THEN
              bestGini := giniSplit;
              bestFeature := INTEGER(featureToTry);
              bestThreshold := threshold
            END
          END
        END (* FOR t *)
      END (* IF useRandomThresholds *)
    END (* IF maxVal - minVal *)
  END (* FOR fi *)
END FindBestSplit;

(* ---- Recursive tree building ---- *)

PROCEDURE BuildNode(VAR t: Tree; data: ADDRESS; labels: ADDRESS;
                    indices: ADDRESS; numSamples, numFeatures: CARDINAL;
                    depth: CARDINAL;
                    featureMask: ADDRESS; numMaskFeatures: CARDINAL;
                    useRandomThresholds: BOOLEAN; VAR rngSeed: CARDINAL): INTEGER;
VAR
  nodeIdx: INTEGER;
  np: NodePtr;
  bestFeature: INTEGER;
  bestThreshold, bestGini: LONGREAL;
  leftIndices, rightIndices: ADDRESS;
  leftCount, rightCount, i, sampleIdx: CARDINAL;
  fVal: LONGREAL;
  leftChildIdx, rightChildIdx: INTEGER;
BEGIN
  nodeIdx := AllocNode(t);
  IF nodeIdx = -1 THEN
    RETURN -1
  END;

  np := GetNode(t.nodes, CARDINAL(nodeIdx));
  np^.numSamples := numSamples;

  (* Leaf conditions *)
  IF (numSamples <= 1) OR (depth >= t.maxDepth) OR IsPure(labels, indices, numSamples) THEN
    np^.featureIdx := -1;
    np^.classLabel := MajorityClass(labels, indices, numSamples, t.numClasses);
    RETURN nodeIdx
  END;

  (* Find best split *)
  FindBestSplit(data, labels, indices, numSamples, numFeatures, t.numClasses,
                featureMask, numMaskFeatures,
                useRandomThresholds, rngSeed,
                bestFeature, bestThreshold, bestGini);

  IF bestFeature = -1 THEN
    (* No valid split found => leaf *)
    np^.featureIdx := -1;
    np^.classLabel := MajorityClass(labels, indices, numSamples, t.numClasses);
    RETURN nodeIdx
  END;

  (* Partition indices *)
  ALLOCATE(leftIndices, numSamples * TSIZE(CARDINAL));
  ALLOCATE(rightIndices, numSamples * TSIZE(CARDINAL));
  leftCount := 0;
  rightCount := 0;

  FOR i := 0 TO numSamples - 1 DO
    sampleIdx := GetCard(indices, i);
    fVal := GetFeature(data, sampleIdx, CARDINAL(bestFeature), numFeatures);
    IF fVal <= bestThreshold THEN
      SetCard(leftIndices, leftCount, sampleIdx);
      INC(leftCount)
    ELSE
      SetCard(rightIndices, rightCount, sampleIdx);
      INC(rightCount)
    END
  END;

  IF (leftCount = 0) OR (rightCount = 0) THEN
    (* Degenerate split => leaf *)
    DEALLOCATE(leftIndices, numSamples * TSIZE(CARDINAL));
    DEALLOCATE(rightIndices, numSamples * TSIZE(CARDINAL));
    np^.featureIdx := -1;
    np^.classLabel := MajorityClass(labels, indices, numSamples, t.numClasses);
    RETURN nodeIdx
  END;

  (* Set split info - re-fetch np since AllocNode in children may move things,
     but we use flat array so pointer stays valid *)
  np := GetNode(t.nodes, CARDINAL(nodeIdx));
  np^.featureIdx := bestFeature;
  np^.threshold := bestThreshold;

  (* Build children *)
  leftChildIdx := BuildNode(t, data, labels, leftIndices, leftCount, numFeatures,
                            depth + 1, featureMask, numMaskFeatures,
                            useRandomThresholds, rngSeed);
  rightChildIdx := BuildNode(t, data, labels, rightIndices, rightCount, numFeatures,
                             depth + 1, featureMask, numMaskFeatures,
                             useRandomThresholds, rngSeed);

  (* Re-fetch pointer after recursive calls *)
  np := GetNode(t.nodes, CARDINAL(nodeIdx));
  np^.leftChild := leftChildIdx;
  np^.rightChild := rightChildIdx;

  DEALLOCATE(leftIndices, numSamples * TSIZE(CARDINAL));
  DEALLOCATE(rightIndices, numSamples * TSIZE(CARDINAL));

  RETURN nodeIdx
END BuildNode;

(* ---- Public: Train ---- *)

PROCEDURE Train(VAR t: Tree; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
VAR
  indices: ADDRESS;
  i: CARDINAL;
  dummy: INTEGER;
  seed: CARDINAL;
BEGIN
  ALLOCATE(indices, numSamples * TSIZE(CARDINAL));
  FOR i := 0 TO numSamples - 1 DO
    SetCard(indices, i, i)
  END;
  seed := 42;
  dummy := BuildNode(t, data, labels, indices, numSamples, numFeatures, 0,
                     NIL, numFeatures, FALSE, seed);
  DEALLOCATE(indices, numSamples * TSIZE(CARDINAL))
END Train;

(* ---- Public: TrainSubset ---- *)

PROCEDURE TrainSubset(VAR t: Tree; data: ADDRESS; labels: ADDRESS;
                      numSamples, numFeatures: CARDINAL;
                      sampleIndices: ADDRESS; numSubSamples: CARDINAL;
                      featureMask: ADDRESS; numMaskFeatures: CARDINAL;
                      useRandomThresholds: BOOLEAN; seed: CARDINAL);
VAR
  dummy: INTEGER;
BEGIN
  dummy := BuildNode(t, data, labels, sampleIndices, numSubSamples, numFeatures, 0,
                     featureMask, numMaskFeatures, useRandomThresholds, seed)
END TrainSubset;

(* ---- Public: Predict ---- *)

PROCEDURE Predict(VAR t: Tree; sample: ADDRESS): INTEGER;
VAR
  nodeIdx: CARDINAL;
  np: NodePtr;
  fVal: LONGREAL;
BEGIN
  IF t.numNodes = 0 THEN
    RETURN 0
  END;
  nodeIdx := 0;
  LOOP
    np := GetNode(t.nodes, nodeIdx);
    IF np^.featureIdx = -1 THEN
      RETURN np^.classLabel
    END;
    fVal := GetReal(sample, CARDINAL(np^.featureIdx));
    IF fVal <= np^.threshold THEN
      IF np^.leftChild = -1 THEN
        RETURN np^.classLabel
      END;
      nodeIdx := CARDINAL(np^.leftChild)
    ELSE
      IF np^.rightChild = -1 THEN
        RETURN np^.classLabel
      END;
      nodeIdx := CARDINAL(np^.rightChild)
    END
  END
END Predict;

(* ---- Public: PredictBatch ---- *)

PROCEDURE PredictBatch(VAR t: Tree; data: ADDRESS; numSamples: CARDINAL;
                       predictions: ADDRESS);
VAR
  i: CARDINAL;
  sampleAddr: ADDRESS;
  pred: INTEGER;
BEGIN
  FOR i := 0 TO numSamples - 1 DO
    sampleAddr := ADDRESS(LONGCARD(data) + LONGCARD(i * t.numFeatures * TSIZE(LONGREAL)));
    pred := Predict(t, sampleAddr);
    SetInt(predictions, i, pred)
  END
END PredictBatch;

(* ---- Public: Free ---- *)

PROCEDURE Free(VAR t: Tree);
BEGIN
  IF t.nodes # NIL THEN
    DEALLOCATE(t.nodes, t.maxNodes * TSIZE(TreeNode));
    t.nodes := NIL
  END;
  t.numNodes := 0
END Free;

END DTree.
