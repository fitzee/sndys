IMPLEMENTATION MODULE Evaluate;

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM KNN IMPORT Model, Init, Train, Predict, Euclidean;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i * TSIZE(INTEGER)))
END ElemI;

PROCEDURE ComputeConfusion(actual, predicted: ADDRESS;
                           numSamples, numClasses: CARDINAL;
                           VAR cm: ConfMatrix);
VAR
  i: CARDINAL;
  a, p: INTEGER;
  pa, pp: IntPtr;
BEGIN
  cm.numClasses := numClasses;
  FOR a := 0 TO INTEGER(numClasses) - 1 DO
    FOR p := 0 TO INTEGER(numClasses) - 1 DO
      cm.cells[a][p] := 0
    END
  END;

  FOR i := 0 TO numSamples - 1 DO
    pa := ElemI(actual, i);
    pp := ElemI(predicted, i);
    a := pa^;
    p := pp^;
    IF (a >= 0) AND (CARDINAL(a) < numClasses) AND
       (p >= 0) AND (CARDINAL(p) < numClasses) THEN
      INC(cm.cells[a][p])
    END
  END
END ComputeConfusion;

PROCEDURE ComputeMetrics(VAR cm: ConfMatrix; VAR met: ClassMetrics);
VAR
  c, j: CARDINAL;
  tp, fp, fn, totalCorrect, totalSamples: CARDINAL;
  p, r: LONGREAL;
BEGIN
  totalCorrect := 0;
  totalSamples := 0;

  FOR c := 0 TO cm.numClasses - 1 DO
    (* True positives *)
    tp := cm.cells[c][c];
    totalCorrect := totalCorrect + tp;

    (* False positives: predicted as c but actually j *)
    fp := 0;
    FOR j := 0 TO cm.numClasses - 1 DO
      IF j # c THEN fp := fp + cm.cells[j][c] END;
      totalSamples := totalSamples + cm.cells[c][j]
    END;

    (* False negatives: actually c but predicted as j *)
    fn := 0;
    FOR j := 0 TO cm.numClasses - 1 DO
      IF j # c THEN fn := fn + cm.cells[c][j] END
    END;

    (* Precision *)
    IF tp + fp > 0 THEN
      p := LFLOAT(tp) / LFLOAT(tp + fp)
    ELSE
      p := 0.0
    END;
    met.precision[c] := p;

    (* Recall *)
    IF tp + fn > 0 THEN
      r := LFLOAT(tp) / LFLOAT(tp + fn)
    ELSE
      r := 0.0
    END;
    met.recall[c] := r;

    (* F1 *)
    IF p + r > 0.0 THEN
      met.f1[c] := 2.0 * p * r / (p + r)
    ELSE
      met.f1[c] := 0.0
    END
  END;

  (* Overall accuracy *)
  IF totalSamples > 0 THEN
    met.accuracy := LFLOAT(totalCorrect) / LFLOAT(totalSamples)
  ELSE
    met.accuracy := 0.0
  END;

  (* Macro F1 *)
  met.macroF1 := 0.0;
  FOR c := 0 TO cm.numClasses - 1 DO
    met.macroF1 := met.macroF1 + met.f1[c]
  END;
  IF cm.numClasses > 0 THEN
    met.macroF1 := met.macroF1 / LFLOAT(cm.numClasses)
  END
END ComputeMetrics;

(* ── Cross-validation ──────────────────────────────── *)

PROCEDURE CrossValidate(data: ADDRESS; labels: ADDRESS;
                        numSamples, numFeatures, numClasses: CARDINAL;
                        nFolds, kNeighbors: CARDINAL;
                        VAR met: ClassMetrics): LONGREAL;
VAR
  fold, i, j, trainCount, testCount: CARDINAL;
  foldSize, foldStart, foldEnd: CARDINAL;
  trainData, trainLabels, testData, testLabels, predictions: ADDRESS;
  trainBytes, testBytes, trainLabelBytes, testLabelBytes, predBytes: CARDINAL;
  srcRow, dstRow: ADDRESS;
  pSrcI, pDstI: IntPtr;
  pSrcR, pDstR: RealPtr;
  model: Model;
  cm: ConfMatrix;
  foldMet: ClassMetrics;
  totalCorrect, totalSamples: CARDINAL;
  c: CARDINAL;
BEGIN
  IF (nFolds < 2) OR (numSamples < nFolds) THEN
    met.accuracy := 0.0;
    met.macroF1 := 0.0;
    RETURN 0.0
  END;

  foldSize := numSamples DIV nFolds;

  (* Initialize accumulators *)
  totalCorrect := 0;
  totalSamples := 0;
  FOR c := 0 TO numClasses - 1 DO
    met.precision[c] := 0.0;
    met.recall[c] := 0.0;
    met.f1[c] := 0.0
  END;

  FOR fold := 0 TO nFolds - 1 DO
    foldStart := fold * foldSize;
    IF fold = nFolds - 1 THEN
      foldEnd := numSamples - 1
    ELSE
      foldEnd := foldStart + foldSize - 1
    END;
    testCount := foldEnd - foldStart + 1;
    trainCount := numSamples - testCount;

    (* Allocate fold arrays *)
    trainBytes := trainCount * numFeatures * TSIZE(LONGREAL);
    testBytes := testCount * numFeatures * TSIZE(LONGREAL);
    trainLabelBytes := trainCount * TSIZE(INTEGER);
    testLabelBytes := testCount * TSIZE(INTEGER);
    predBytes := testCount * TSIZE(INTEGER);

    ALLOCATE(trainData, trainBytes);
    ALLOCATE(trainLabels, trainLabelBytes);
    ALLOCATE(testData, testBytes);
    ALLOCATE(testLabels, testLabelBytes);
    ALLOCATE(predictions, predBytes);

    (* Copy training data (everything except fold) *)
    j := 0;
    FOR i := 0 TO numSamples - 1 DO
      IF (i < foldStart) OR (i > foldEnd) THEN
        (* Copy feature row *)
        srcRow := ADDRESS(LONGCARD(data)
                  + LONGCARD(i * numFeatures * TSIZE(LONGREAL)));
        dstRow := ADDRESS(LONGCARD(trainData)
                  + LONGCARD(j * numFeatures * TSIZE(LONGREAL)));
        (* Copy numFeatures LONGREALs *)
        FOR c := 0 TO numFeatures - 1 DO
          pSrcR := ElemR(srcRow, c);
          pDstR := ElemR(dstRow, c);
          pDstR^ := pSrcR^
        END;
        (* Copy label *)
        pSrcI := ElemI(labels, i);
        pDstI := ElemI(trainLabels, j);
        pDstI^ := pSrcI^;
        INC(j)
      END
    END;

    (* Copy test data (the fold) *)
    FOR i := 0 TO testCount - 1 DO
      srcRow := ADDRESS(LONGCARD(data)
                + LONGCARD((foldStart + i) * numFeatures * TSIZE(LONGREAL)));
      dstRow := ADDRESS(LONGCARD(testData)
                + LONGCARD(i * numFeatures * TSIZE(LONGREAL)));
      FOR c := 0 TO numFeatures - 1 DO
        pSrcR := ElemR(srcRow, c);
        pDstR := ElemR(dstRow, c);
        pDstR^ := pSrcR^
      END;
      pSrcI := ElemI(labels, foldStart + i);
      pDstI := ElemI(testLabels, i);
      pDstI^ := pSrcI^
    END;

    (* Train and predict *)
    Init(model, kNeighbors, numFeatures, numClasses, Euclidean, TRUE);
    Train(model, trainData, trainLabels, trainCount, TRUE);

    (* Scale test data with the training scaler *)
    IF model.hasScaler THEN
      FOR i := 0 TO testCount - 1 DO
        dstRow := ADDRESS(LONGCARD(testData)
                  + LONGCARD(i * numFeatures * TSIZE(LONGREAL)));
        FOR c := 0 TO numFeatures - 1 DO
          pDstR := ElemR(dstRow, c);
          pDstR^ := (pDstR^ - model.scaler.means[c]) / model.scaler.stds[c]
        END
      END
    END;

    (* Predict on test fold — data is already scaled, disable auto-scaling *)
    model.hasScaler := FALSE;
    FOR i := 0 TO testCount - 1 DO
      srcRow := ADDRESS(LONGCARD(testData)
                + LONGCARD(i * numFeatures * TSIZE(LONGREAL)));
      pDstI := ElemI(predictions, i);
      pDstI^ := Predict(model, srcRow)
    END;

    (* Evaluate this fold *)
    ComputeConfusion(testLabels, predictions,
                     testCount, numClasses, cm);
    ComputeMetrics(cm, foldMet);

    FOR c := 0 TO numClasses - 1 DO
      met.precision[c] := met.precision[c] + foldMet.precision[c];
      met.recall[c] := met.recall[c] + foldMet.recall[c];
      met.f1[c] := met.f1[c] + foldMet.f1[c]
    END;

    (* Count correct *)
    FOR i := 0 TO testCount - 1 DO
      pSrcI := ElemI(testLabels, i);
      pDstI := ElemI(predictions, i);
      IF pSrcI^ = pDstI^ THEN INC(totalCorrect) END;
      INC(totalSamples)
    END;

    (* Free fold arrays *)
    DEALLOCATE(trainData, 0);
    DEALLOCATE(trainLabels, 0);
    DEALLOCATE(testData, 0);
    DEALLOCATE(testLabels, 0);
    DEALLOCATE(predictions, 0)
  END;

  (* Average per-class metrics across folds *)
  FOR c := 0 TO numClasses - 1 DO
    met.precision[c] := met.precision[c] / LFLOAT(nFolds);
    met.recall[c] := met.recall[c] / LFLOAT(nFolds);
    met.f1[c] := met.f1[c] / LFLOAT(nFolds)
  END;

  IF totalSamples > 0 THEN
    met.accuracy := LFLOAT(totalCorrect) / LFLOAT(totalSamples)
  ELSE
    met.accuracy := 0.0
  END;

  met.macroF1 := 0.0;
  FOR c := 0 TO numClasses - 1 DO
    met.macroF1 := met.macroF1 + met.f1[c]
  END;
  IF numClasses > 0 THEN
    met.macroF1 := met.macroF1 / LFLOAT(numClasses)
  END;

  RETURN met.accuracy
END CrossValidate;

END Evaluate.
