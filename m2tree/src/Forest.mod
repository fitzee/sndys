IMPLEMENTATION MODULE Forest;

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
IMPORT DTree;
FROM DTree IMPORT TrainSubset;

TYPE
  CardPtr = POINTER TO CARDINAL;

(* ---- Pointer helpers ---- *)

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

(* ---- LCG ---- *)

PROCEDURE LCGNext(seed: CARDINAL): CARDINAL;
BEGIN
  RETURN (seed * 1103515245 + 12345) MOD 2147483648
END LCGNext;

(* ---- Approximate integer square root ---- *)

PROCEDURE ISqrt(n: CARDINAL): CARDINAL;
VAR
  x, y: CARDINAL;
BEGIN
  IF n = 0 THEN
    RETURN 0
  END;
  x := n;
  y := (x + 1) DIV 2;
  WHILE y < x DO
    x := y;
    y := (x + n DIV x) DIV 2
  END;
  RETURN x
END ISqrt;

(* ---- Init ---- *)

PROCEDURE Init(VAR f: Forest; nTrees, nFeatures, nClasses, maxDepth: CARDINAL;
               fType: ForestType);
BEGIN
  IF nTrees > 100 THEN
    f.numTrees := 100
  ELSE
    f.numTrees := nTrees
  END;
  f.forestType := fType;
  f.numFeatures := nFeatures;
  f.numClasses := nClasses;
  f.maxDepth := maxDepth
END Init;

(* ---- Train ---- *)

PROCEDURE Train(VAR f: Forest; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
VAR
  i, j, s: CARDINAL;
  seed: CARDINAL;
  sampleIndices: ADDRESS;
  featureMask: ADDRESS;
  numSubFeatures: CARDINAL;
  bootstrapSize: CARDINAL;
  useRandom: BOOLEAN;
  featurePool: ARRAY [0..255] OF CARDINAL;
  selected: ARRAY [0..255] OF BOOLEAN;
  fi, pick, count: CARDINAL;
BEGIN
  (* Number of features to consider at each split: sqrt(numFeatures) *)
  numSubFeatures := ISqrt(numFeatures);
  IF numSubFeatures < 1 THEN
    numSubFeatures := 1
  END;

  bootstrapSize := numSamples;
  useRandom := (f.forestType = ExtraTrees);

  ALLOCATE(sampleIndices, numSamples * TSIZE(CARDINAL));
  ALLOCATE(featureMask, numSubFeatures * TSIZE(CARDINAL));

  FOR i := 0 TO f.numTrees - 1 DO
    seed := (i + 1) * 7919;

    (* Initialize tree *)
    DTree.Init(f.trees[i], numFeatures, f.numClasses, f.maxDepth);

    (* Create sample indices *)
    IF f.forestType = RandomForest THEN
      (* Bootstrap sample *)
      FOR j := 0 TO numSamples - 1 DO
        seed := LCGNext(seed);
        s := seed MOD numSamples;
        SetCard(sampleIndices, j, s)
      END
    ELSE
      (* ExtraTrees: use all data *)
      FOR j := 0 TO numSamples - 1 DO
        SetCard(sampleIndices, j, j)
      END
    END;

    (* Select random feature subset *)
    FOR fi := 0 TO numFeatures - 1 DO
      selected[fi] := FALSE
    END;
    count := 0;
    WHILE count < numSubFeatures DO
      seed := LCGNext(seed);
      pick := seed MOD numFeatures;
      IF NOT selected[pick] THEN
        selected[pick] := TRUE;
        SetCard(featureMask, count, pick);
        INC(count)
      END
    END;

    (* Train the tree *)
    TrainSubset(f.trees[i], data, labels, numSamples, numFeatures,
                sampleIndices, bootstrapSize,
                featureMask, numSubFeatures,
                useRandom, seed)
  END;

  DEALLOCATE(sampleIndices, numSamples * TSIZE(CARDINAL));
  DEALLOCATE(featureMask, numSubFeatures * TSIZE(CARDINAL))
END Train;

(* ---- Predict: majority vote ---- *)

PROCEDURE Predict(VAR f: Forest; sample: ADDRESS): INTEGER;
VAR
  votes: ARRAY [0..31] OF CARDINAL;
  i, cls: CARDINAL;
  pred, bestClass: INTEGER;
  bestCount: CARDINAL;
BEGIN
  FOR i := 0 TO f.numClasses - 1 DO
    votes[i] := 0
  END;

  FOR i := 0 TO f.numTrees - 1 DO
    pred := DTree.Predict(f.trees[i], sample);
    cls := CARDINAL(pred);
    IF cls < f.numClasses THEN
      INC(votes[cls])
    END
  END;

  bestClass := 0;
  bestCount := 0;
  FOR i := 0 TO f.numClasses - 1 DO
    IF votes[i] > bestCount THEN
      bestCount := votes[i];
      bestClass := INTEGER(i)
    END
  END;
  RETURN bestClass
END Predict;

(* ---- PredictProba ---- *)

PROCEDURE PredictProba(VAR f: Forest; sample: ADDRESS;
                       VAR proba: ARRAY OF LONGREAL): INTEGER;
VAR
  votes: ARRAY [0..31] OF CARDINAL;
  i, cls: CARDINAL;
  pred, bestClass: INTEGER;
  bestCount: CARDINAL;
BEGIN
  FOR i := 0 TO f.numClasses - 1 DO
    votes[i] := 0
  END;

  FOR i := 0 TO f.numTrees - 1 DO
    pred := DTree.Predict(f.trees[i], sample);
    cls := CARDINAL(pred);
    IF cls < f.numClasses THEN
      INC(votes[cls])
    END
  END;

  bestClass := 0;
  bestCount := 0;
  FOR i := 0 TO f.numClasses - 1 DO
    proba[i] := LFLOAT(votes[i]) / LFLOAT(f.numTrees);
    IF votes[i] > bestCount THEN
      bestCount := votes[i];
      bestClass := INTEGER(i)
    END
  END;
  RETURN bestClass
END PredictProba;

(* ---- Free ---- *)

PROCEDURE Free(VAR f: Forest);
VAR
  i: CARDINAL;
BEGIN
  FOR i := 0 TO f.numTrees - 1 DO
    DTree.Free(f.trees[i])
  END;
  f.numTrees := 0
END Free;

END Forest.
