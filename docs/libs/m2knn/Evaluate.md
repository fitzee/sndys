# Evaluate

The `Evaluate` module provides classification evaluation tools: confusion matrix construction, per-class precision/recall/F1 computation, macro-averaged accuracy and F1, and k-fold cross-validation for the `KNN` classifier. All metrics operate on integer label arrays (actual vs. predicted), and the cross-validation procedure handles data partitioning, training, and evaluation internally so that a single call produces reliable performance estimates.

## Why Evaluate?

A classifier is only as trustworthy as its evaluation. Raw accuracy can be misleading with imbalanced classes, so per-class precision, recall, and F1 scores are essential for understanding where a model succeeds and where it fails. Cross-validation goes further by testing the model on every portion of the dataset, producing performance estimates that do not depend on a single lucky or unlucky train/test split. This module bundles all of these metrics together with the confusion matrix that underlies them, giving a complete evaluation toolkit in a single import with no external dependencies.

## Constants

### MaxClasses

```modula2
CONST
  MaxClasses = 32;
```

The maximum number of distinct class labels supported, matching the limit in the `KNN` module.

## Types

### ConfMatrix

```modula2
TYPE
  ConfMatrix = RECORD
    numClasses: CARDINAL;
    cells: ARRAY [0..31] OF ARRAY [0..31] OF CARDINAL;
  END;
```

A square confusion matrix storing classification counts. The indexing convention is `cells[actual][predicted]`: the value at row `a`, column `p` is the number of samples whose true label is `a` that the classifier assigned label `p`.

Reading the matrix:

- **Diagonal entries** `cells[c][c]` are correct classifications (true positives for class `c`).
- **Row `a` off-diagonal entries** `cells[a][p]` where `a <> p` are misclassifications -- samples of class `a` that were incorrectly predicted as class `p`.
- **The sum of row `a`** is the total number of actual samples of class `a`.
- **The sum of column `p`** is the total number of samples predicted as class `p`.

For example, with three classes (0, 1, 2):

```
              Predicted
              0    1    2
Actual  0  [ 45    3    2 ]
        1  [  1   38    1 ]
        2  [  4    2   44 ]
```

Here, 45 samples of class 0 were correctly classified, 3 samples of class 0 were misclassified as class 1, and so on.

### ClassMetrics

```modula2
TYPE
  ClassMetrics = RECORD
    accuracy:  LONGREAL;
    precision: ARRAY [0..31] OF LONGREAL;
    recall:    ARRAY [0..31] OF LONGREAL;
    f1:        ARRAY [0..31] OF LONGREAL;
    macroF1:   LONGREAL;
  END;
```

Holds computed evaluation metrics. `accuracy` is the overall fraction of correctly classified samples. `precision[c]`, `recall[c]`, and `f1[c]` are per-class metrics. `macroF1` is the unweighted mean of all per-class F1 scores, which gives equal importance to each class regardless of its size.

The per-class metrics are defined as:

- **Precision(c)** = `cells[c][c] / SUM_a(cells[a][c])` -- of all samples predicted as class `c`, how many actually belong to class `c`.
- **Recall(c)** = `cells[c][c] / SUM_p(cells[c][p])` -- of all actual samples of class `c`, how many were correctly predicted.
- **F1(c)** = `2 * Precision(c) * Recall(c) / (Precision(c) + Recall(c))` -- the harmonic mean of precision and recall.

## Procedures

### ComputeConfusion

```modula2
PROCEDURE ComputeConfusion(actual, predicted: ADDRESS;
                           numSamples, numClasses: CARDINAL;
                           VAR cm: ConfMatrix);
```

Builds a confusion matrix from two parallel label arrays. `actual` and `predicted` each point to `numSamples` `INTEGER` values containing 0-based class indices. The procedure zeroes the matrix, then increments `cells[actual[i]][predicted[i]]` for each sample. `numClasses` sets the dimension of the matrix.

**Example:**

```modula2
VAR
  actual:    ARRAY [0..4] OF INTEGER;
  predicted: ARRAY [0..4] OF INTEGER;
  cm: ConfMatrix;
actual[0] := 0; predicted[0] := 0;
actual[1] := 1; predicted[1] := 1;
actual[2] := 0; predicted[2] := 1;  (* misclassification *)
actual[3] := 1; predicted[3] := 1;
actual[4] := 0; predicted[4] := 0;
Evaluate.ComputeConfusion(ADR(actual), ADR(predicted), 5, 2, cm);
(* cm.cells[0][0] = 2, cm.cells[0][1] = 1, cm.cells[1][0] = 0, cm.cells[1][1] = 2 *)
```

---

### ComputeMetrics

```modula2
PROCEDURE ComputeMetrics(VAR cm: ConfMatrix; VAR met: ClassMetrics);
```

Computes accuracy, per-class precision, per-class recall, per-class F1, and macro-averaged F1 from a confusion matrix. The confusion matrix must have been previously filled by `ComputeConfusion`. If a class has zero support (no actual samples) or zero predictions, its precision and recall are set to `0.0` to avoid division by zero.

**Example:**

```modula2
VAR met: ClassMetrics;
Evaluate.ComputeMetrics(cm, met);
(* met.accuracy = 4/5 = 0.8 *)
(* met.precision[0] = 2/2 = 1.0, met.precision[1] = 2/3 ~ 0.667 *)
(* met.recall[0] = 2/3 ~ 0.667, met.recall[1] = 2/2 = 1.0 *)
(* met.f1[0] = 2 * 1.0 * 0.667 / (1.0 + 0.667) ~ 0.8 *)
(* met.f1[1] = 2 * 0.667 * 1.0 / (0.667 + 1.0) ~ 0.8 *)
(* met.macroF1 = (0.8 + 0.8) / 2 = 0.8 *)
```

---

### CrossValidate

```modula2
PROCEDURE CrossValidate(data: ADDRESS; labels: ADDRESS;
                        numSamples, numFeatures, numClasses: CARDINAL;
                        nFolds, kNeighbors: CARDINAL;
                        VAR met: ClassMetrics): LONGREAL;
```

Performs k-fold cross-validation on the given dataset using a k-NN classifier. `data` is a row-major matrix of `numSamples` rows by `numFeatures` columns of `LONGREAL` values. `labels` is `numSamples` `INTEGER` values. `nFolds` is the number of folds (typically 5 or 10). `kNeighbors` is the k parameter for the KNN classifier. Returns the overall accuracy and fills `met` with macro-averaged metrics across all folds.

**The cross-validation algorithm:**

1. **Partition**: The dataset is divided into `nFolds` consecutive, roughly equal-sized folds. If `numSamples` is not evenly divisible by `nFolds`, the earlier folds receive one extra sample each. For example, 10 samples with 3 folds yields folds of size 4, 3, and 3.

2. **Iterate**: For each fold `f` from 0 to `nFolds - 1`:
   - Fold `f` is held out as the **test set**.
   - All remaining folds are combined to form the **training set**.
   - A fresh k-NN model is initialized with `kNeighbors` neighbors, Euclidean distance, and scaling enabled.
   - The model is trained on the training set.
   - The model predicts labels for every sample in the test set.
   - A confusion matrix is computed for this fold's predictions.

3. **Aggregate**: The per-fold confusion matrices are summed element-wise into a single combined confusion matrix spanning all samples. Accuracy, precision, recall, F1, and macro F1 are then computed from this combined matrix. This is equivalent to computing metrics on the full set of out-of-fold predictions and avoids averaging artifacts that can occur with small folds.

The returned accuracy is the overall accuracy from the combined confusion matrix. The `met` record contains the full per-class breakdown.

**Example:**

```modula2
VAR
  met: ClassMetrics;
  acc: LONGREAL;
acc := Evaluate.CrossValidate(ADR(data), ADR(labels),
                              150, 4, 3,
                              5, 3, met);
(* 5-fold cross-validation with 3-NN on 150 samples *)
(* acc ~ 0.96, met.macroF1 ~ 0.96 *)
```

## Example

A complete program that evaluates a k-NN classifier using both a train/test split and cross-validation, printing the confusion matrix and all metrics.

```modula2
MODULE EvaluateDemo;

FROM SYSTEM IMPORT ADR;
FROM STextIO IMPORT WriteString, WriteLn;
FROM SWholeIO IMPORT WriteCard, WriteInt;
FROM SLongIO IMPORT WriteFixed;
IMPORT KNN, Evaluate;

CONST
  NTotal    = 12;
  NTrain    = 8;
  NTest     = 4;
  NFeatures = 2;
  NClasses  = 2;

VAR
  data:   ARRAY [0..NTotal * NFeatures - 1] OF LONGREAL;
  labels: ARRAY [0..NTotal - 1] OF INTEGER;
  preds:  ARRAY [0..NTest - 1] OF INTEGER;
  m: KNN.Model;
  cm: Evaluate.ConfMatrix;
  met: Evaluate.ClassMetrics;
  cvAcc: LONGREAL;
  i, j: CARDINAL;

BEGIN
  (* Class 0: points near (1, 1) *)
  data[0] := 0.5; data[1] := 0.8;
  data[2] := 1.0; data[3] := 1.2;
  data[4] := 0.9; data[5] := 0.7;
  data[6] := 1.1; data[7] := 1.0;
  data[8] := 0.7; data[9] := 1.1;
  data[10] := 1.3; data[11] := 0.9;
  (* Class 1: points near (5, 5) *)
  data[12] := 4.8; data[13] := 5.2;
  data[14] := 5.1; data[15] := 4.9;
  data[16] := 5.3; data[17] := 5.0;
  data[18] := 4.7; data[19] := 5.1;
  data[20] := 5.0; data[21] := 4.8;
  data[22] := 5.2; data[23] := 5.3;

  FOR i := 0 TO 5 DO labels[i] := 0 END;
  FOR i := 6 TO 11 DO labels[i] := 1 END;

  (* --- Train/test split evaluation --- *)
  KNN.Init(m, 3, NFeatures, NClasses, KNN.Euclidean, TRUE);
  KNN.Train(m, ADR(data), ADR(labels), NTrain, TRUE);

  (* Predict on the last 4 samples *)
  KNN.PredictBatch(m, ADR(data[NTrain * NFeatures]),
                   NTest, ADR(preds));

  (* Build confusion matrix *)
  Evaluate.ComputeConfusion(ADR(labels[NTrain]), ADR(preds),
                            NTest, NClasses, cm);
  Evaluate.ComputeMetrics(cm, met);

  WriteString("=== Train/Test Split ==="); WriteLn;
  WriteString("Confusion Matrix:"); WriteLn;
  WriteString("             Pred 0  Pred 1"); WriteLn;
  FOR i := 0 TO NClasses - 1 DO
    WriteString("  Actual "); WriteCard(i, 1); WriteString(":  ");
    FOR j := 0 TO NClasses - 1 DO
      WriteCard(cm.cells[i][j], 6);
    END;
    WriteLn;
  END;

  WriteString("Accuracy:  "); WriteFixed(met.accuracy, 4, 8); WriteLn;
  WriteString("Macro F1:  "); WriteFixed(met.macroF1, 4, 8); WriteLn;
  FOR i := 0 TO NClasses - 1 DO
    WriteString("  Class "); WriteCard(i, 1);
    WriteString("  P="); WriteFixed(met.precision[i], 4, 6);
    WriteString("  R="); WriteFixed(met.recall[i], 4, 6);
    WriteString("  F1="); WriteFixed(met.f1[i], 4, 6);
    WriteLn;
  END;

  (* --- Cross-validation on the full dataset --- *)
  WriteString("=== 4-Fold Cross-Validation ==="); WriteLn;
  cvAcc := Evaluate.CrossValidate(ADR(data), ADR(labels),
                                  NTotal, NFeatures, NClasses,
                                  4, 3, met);
  WriteString("CV Accuracy: "); WriteFixed(cvAcc, 4, 8); WriteLn;
  WriteString("CV Macro F1: "); WriteFixed(met.macroF1, 4, 8); WriteLn;
END EvaluateDemo.
```
