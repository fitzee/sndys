IMPLEMENTATION MODULE GBoost;

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM DTree IMPORT Tree;
IMPORT DTree;
FROM MathLib IMPORT exp;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr = POINTER TO INTEGER;
  CardPtr = POINTER TO CARDINAL;

(* ---- Pointer helpers ---- *)

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

PROCEDURE GetCard(base: ADDRESS; idx: CARDINAL): CARDINAL;
VAR
  p: CardPtr;
BEGIN
  p := CardPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(CARDINAL)));
  RETURN p^
END GetCard;

PROCEDURE SetCard(base: ADDRESS; idx: CARDINAL; val: CARDINAL);
VAR
  p: CardPtr;
BEGIN
  p := CardPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(CARDINAL)));
  p^ := val
END SetCard;

PROCEDURE GetFeature(data: ADDRESS; sample, feature, numFeatures: CARDINAL): LONGREAL;
BEGIN
  RETURN GetReal(data, sample * numFeatures + feature)
END GetFeature;

(* ---- Sigmoid ---- *)

PROCEDURE Sigmoid(x: LONGREAL): LONGREAL;
VAR
  ex: LONGREAL;
BEGIN
  IF x > 20.0 THEN
    RETURN 1.0
  ELSIF x < -20.0 THEN
    RETURN 0.0
  ELSE
    ex := LFLOAT(exp(FLOAT(-x)));
    RETURN 1.0 / (1.0 + ex)
  END
END Sigmoid;

(* ---- Init ---- *)

PROCEDURE Init(VAR m: GBModel; nTrees, nFeatures, nClasses: CARDINAL;
               lr: LONGREAL);
VAR
  i: CARDINAL;
BEGIN
  IF nTrees > 200 THEN
    m.numTrees := 200
  ELSE
    m.numTrees := nTrees
  END;
  m.numFeatures := nFeatures;
  m.numClasses := nClasses;
  m.learningRate := lr;
  m.actualNumTrees := 0;
  FOR i := 0 TO 199 DO
    m.weights[i] := 1.0
  END
END Init;

(* ---- Train binary classifier on pseudo-residuals ---- *)
(* We quantize residuals into pseudo-labels for the CART tree:
   residual > 0 => label 1, else label 0.
   The tree learns the direction of the gradient. *)

PROCEDURE TrainBinaryOVR(VAR m: GBModel; data: ADDRESS; labels: ADDRESS;
                         numSamples, numFeatures: CARDINAL;
                         targetClass: CARDINAL;
                         treeOffset: CARDINAL);
VAR
  scores: ADDRESS;       (* LONGREAL per sample: current F(x) *)
  pseudoLabels: ADDRESS; (* INTEGER per sample *)
  residualData: ADDRESS; (* augmented data: original features + residual as extra *)
  i, round: CARDINAL;
  target: LONGREAL;
  prob, residual: LONGREAL;
  treeIdx: CARDINAL;
  pred: INTEGER;
  sampleAddr: ADDRESS;
  predScore: LONGREAL;
BEGIN
  ALLOCATE(scores, numSamples * TSIZE(LONGREAL));
  ALLOCATE(pseudoLabels, numSamples * TSIZE(INTEGER));

  (* Initialize scores to 0 *)
  FOR i := 0 TO numSamples - 1 DO
    SetReal(scores, i, 0.0)
  END;

  FOR round := 0 TO m.numTrees - 1 DO
    treeIdx := treeOffset + round;
    IF treeIdx >= 200 THEN
      RETURN
    END;

    (* Compute pseudo-residuals *)
    FOR i := 0 TO numSamples - 1 DO
      IF CARDINAL(GetInt(labels, i)) = targetClass THEN
        target := 1.0
      ELSE
        target := 0.0
      END;
      prob := Sigmoid(GetReal(scores, i));
      residual := target - prob;
      (* Quantize: positive residual => class 1 *)
      IF residual > 0.0 THEN
        SetInt(pseudoLabels, i, 1)
      ELSE
        SetInt(pseudoLabels, i, 0)
      END
    END;

    (* Train a shallow tree (depth 2) on pseudo-labels *)
    DTree.Init(m.trees[treeIdx], numFeatures, 2, 2);
    DTree.Train(m.trees[treeIdx], data, pseudoLabels, numSamples, numFeatures);
    m.weights[treeIdx] := m.learningRate;

    (* Update scores *)
    FOR i := 0 TO numSamples - 1 DO
      sampleAddr := ADDRESS(LONGCARD(data) + LONGCARD(i * numFeatures * TSIZE(LONGREAL)));
      pred := DTree.Predict(m.trees[treeIdx], sampleAddr);
      (* Map prediction: 0 => -1.0, 1 => +1.0 *)
      IF pred = 1 THEN
        predScore := 1.0
      ELSE
        predScore := -1.0
      END;
      SetReal(scores, i, GetReal(scores, i) + m.learningRate * predScore)
    END
  END;

  m.actualNumTrees := treeOffset + m.numTrees;
  IF m.actualNumTrees > 200 THEN
    m.actualNumTrees := 200
  END;

  DEALLOCATE(scores, numSamples * TSIZE(LONGREAL));
  DEALLOCATE(pseudoLabels, numSamples * TSIZE(INTEGER))
END TrainBinaryOVR;

(* ---- Public: Train ---- *)

PROCEDURE Train(VAR m: GBModel; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
VAR
  c: CARDINAL;
  treesPerClass: CARDINAL;
BEGIN
  IF m.numClasses <= 2 THEN
    (* Binary classification *)
    TrainBinaryOVR(m, data, labels, numSamples, numFeatures, 1, 0)
  ELSE
    (* Multi-class: one-vs-rest *)
    treesPerClass := m.numTrees DIV m.numClasses;
    IF treesPerClass < 1 THEN
      treesPerClass := 1
    END;
    (* Temporarily reduce numTrees for per-class training *)
    m.numTrees := treesPerClass;
    FOR c := 0 TO m.numClasses - 1 DO
      TrainBinaryOVR(m, data, labels, numSamples, numFeatures,
                     c, c * treesPerClass)
    END;
    m.numTrees := treesPerClass;
    m.actualNumTrees := m.numClasses * treesPerClass
  END
END Train;

(* ---- Public: Predict ---- *)

PROCEDURE Predict(VAR m: GBModel; sample: ADDRESS): INTEGER;
VAR
  scores: ARRAY [0..31] OF LONGREAL;
  c, round, treeIdx, treesPerClass: CARDINAL;
  pred: INTEGER;
  predScore: LONGREAL;
  bestClass: INTEGER;
  bestScore: LONGREAL;
BEGIN
  IF m.numClasses <= 2 THEN
    (* Binary: sum scores from all trees *)
    scores[0] := 0.0;
    FOR round := 0 TO m.numTrees - 1 DO
      IF round < m.actualNumTrees THEN
        pred := DTree.Predict(m.trees[round], sample);
        IF pred = 1 THEN
          predScore := 1.0
        ELSE
          predScore := -1.0
        END;
        scores[0] := scores[0] + m.weights[round] * predScore
      END
    END;
    IF scores[0] > 0.0 THEN
      RETURN 1
    ELSE
      RETURN 0
    END
  ELSE
    (* Multi-class: one-vs-rest scores — clamp to array size *)
    treesPerClass := m.numTrees;
    IF m.numClasses > 32 THEN
      RETURN 0
    END;
    FOR c := 0 TO m.numClasses - 1 DO
      scores[c] := 0.0;
      FOR round := 0 TO treesPerClass - 1 DO
        treeIdx := c * treesPerClass + round;
        IF treeIdx < m.actualNumTrees THEN
          pred := DTree.Predict(m.trees[treeIdx], sample);
          IF pred = 1 THEN
            predScore := 1.0
          ELSE
            predScore := -1.0
          END;
          scores[c] := scores[c] + m.weights[treeIdx] * predScore
        END
      END
    END;

    bestClass := 0;
    bestScore := scores[0];
    FOR c := 1 TO m.numClasses - 1 DO
      IF scores[c] > bestScore THEN
        bestScore := scores[c];
        bestClass := INTEGER(c)
      END
    END;
    RETURN bestClass
  END
END Predict;

(* ---- Public: Free ---- *)

PROCEDURE Free(VAR m: GBModel);
VAR
  i: CARDINAL;
BEGIN
  FOR i := 0 TO m.actualNumTrees - 1 DO
    DTree.Free(m.trees[i])
  END;
  m.actualNumTrees := 0
END Free;

END GBoost.
