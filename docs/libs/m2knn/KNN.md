# KNN

The `KNN` module implements a k-Nearest Neighbors classifier in pure Modula-2. It stores training data and labels, computes distances from query samples to all training points, and returns the majority class among the k closest neighbors. The classifier supports three distance metrics (Euclidean, Manhattan, and Cosine), optional distance-weighted voting, optional built-in feature scaling via the `Scaler` module, and binary model persistence for saving and loading trained models.

## Why KNN?

k-NN is one of the simplest and most effective classifiers for moderate-sized datasets, especially in domains like audio genre classification where the feature space is well-defined and the number of training samples is in the thousands rather than millions. It requires no iterative training or gradient computation -- the model is simply the stored training set. This module provides a self-contained implementation that avoids external dependencies, handles the full lifecycle from training through prediction to serialization, and integrates directly with the `Scaler` module so that feature normalization is automatic and consistent between training and inference.

## Constants

### MaxClasses

```modula2
CONST
  MaxClasses = 32;
```

The maximum number of distinct class labels supported. Labels must be integers in the range `0..numClasses-1`.

### MaxK

```modula2
CONST
  MaxK = 51;
```

The maximum value of k (number of neighbors). Odd values are recommended to avoid ties in majority voting.

## Types

### DistMetric

```modula2
TYPE
  DistMetric = (Euclidean, Manhattan, Cosine);
```

An enumeration of the three supported distance functions. See the Distance Metrics section below for details.

### Model

```modula2
TYPE
  Model = RECORD
    trainData:    ADDRESS;
    trainLabels:  ADDRESS;
    numTrain:     CARDINAL;
    numFeatures:  CARDINAL;
    numClasses:   CARDINAL;
    k:            CARDINAL;
    metric:       DistMetric;
    weighted:     BOOLEAN;
    scaler:       ScalerState;
    hasScaler:    BOOLEAN;
  END;
```

The complete state of a k-NN classifier. `trainData` points to a row-major matrix of `numTrain` rows by `numFeatures` columns of `LONGREAL` values. `trainLabels` points to `numTrain` `INTEGER` values (0-based class indices). `k` is the neighbor count, `metric` selects the distance function, and `weighted` enables inverse-distance vote weighting. If `hasScaler` is `TRUE`, the embedded `scaler` holds fitted normalization statistics that are applied automatically during prediction.

Note that the classifier does not copy training data -- it holds a reference to the caller-provided arrays. The caller must keep the training data alive as long as the model is in use, unless the model was loaded from disk via `LoadModel` (which allocates its own copy on the heap).

## Distance Metrics

### Euclidean Distance

The straight-line distance between two points in n-dimensional space:

```
d(a, b) = sqrt( SUM_i (a[i] - b[i])^2 )
```

This is the default and most commonly used metric. It works well when features are on comparable scales (use the built-in scaler to ensure this). Euclidean distance is sensitive to outliers because differences are squared.

### Manhattan Distance

The sum of absolute differences along each dimension, also known as L1 distance or taxicab distance:

```
d(a, b) = SUM_i |a[i] - b[i]|
```

Manhattan distance is more robust to outliers than Euclidean distance because it does not square the differences. It tends to perform well in high-dimensional spaces where the "curse of dimensionality" makes Euclidean distances less discriminative.

### Cosine Distance

Measures the angle between two vectors rather than their magnitude:

```
d(a, b) = 1 - (a . b) / (||a|| * ||b||)
```

where `a . b` is the dot product and `||a||` is the L2 norm. Cosine distance is `0` when vectors point in the same direction and `1` when they are orthogonal. It is particularly useful for feature vectors where the overall magnitude is less meaningful than the relative proportions across dimensions, such as TF-IDF text features or spectral shape descriptors in audio.

## Procedures

### Init

```modula2
PROCEDURE Init(VAR m: Model; k, numFeatures, numClasses: CARDINAL;
               metric: DistMetric; weighted: BOOLEAN);
```

Initializes a model with the specified parameters. Sets the neighbor count `k`, the feature dimensionality, the number of classes, the distance metric, and whether distance-weighted voting is enabled. Training data pointers are set to `NIL` and `hasScaler` is set to `FALSE`. This must be called before `Train`.

**Example:**

```modula2
VAR m: Model;
KNN.Init(m, 5, 13, 3, Euclidean, TRUE);
(* 5-NN classifier, 13 features, 3 classes, Euclidean distance, weighted voting *)
```

---

### Train

```modula2
PROCEDURE Train(VAR m: Model;
                data: ADDRESS; labels: ADDRESS;
                numSamples: CARDINAL; scale: BOOLEAN);
```

Stores the training data and labels in the model. `data` is a row-major matrix of `numSamples` rows by `numFeatures` columns of `LONGREAL` values. `labels` is an array of `numSamples` `INTEGER` values containing 0-based class indices. If `scale` is `TRUE`, the procedure fits a `StandardScaler` on the training data and normalizes it in-place, storing the scaler state in the model for use during prediction. The model stores references to the provided arrays, not copies -- the caller must keep them alive.

**Example:**

```modula2
VAR
  data: ARRAY [0..399] OF LONGREAL;   (* 100 samples x 4 features *)
  labels: ARRAY [0..99] OF INTEGER;
KNN.Train(m, ADR(data), ADR(labels), 100, TRUE);
(* Model is trained with scaling enabled *)
```

---

### Predict

```modula2
PROCEDURE Predict(VAR m: Model; sample: ADDRESS): INTEGER;
```

Classifies a single feature vector and returns the predicted class label. `sample` points to `numFeatures` `LONGREAL` values. If the model has a fitted scaler, the sample is normalized internally using a temporary copy -- the original data is not modified. The procedure computes the distance from the sample to every training point, selects the k nearest neighbors, and returns the class with the highest vote count (or highest weighted vote sum if `weighted` is `TRUE`).

**Example:**

```modula2
VAR
  sample: ARRAY [0..3] OF LONGREAL;
  pred: INTEGER;
sample[0] := 5.1; sample[1] := 3.5; sample[2] := 1.4; sample[3] := 0.2;
pred := KNN.Predict(m, ADR(sample));
(* pred is the predicted class index *)
```

---

### PredictProba

```modula2
PROCEDURE PredictProba(VAR m: Model; sample: ADDRESS;
                       VAR proba: ARRAY OF LONGREAL): INTEGER;
```

Classifies a single feature vector and additionally returns per-class confidence scores. `sample` points to `numFeatures` `LONGREAL` values. The `proba` array is filled with `numClasses` values representing the normalized vote weights for each class (summing to 1.0). Returns the predicted class label. This is useful when you need to assess the confidence of a prediction or implement soft voting across an ensemble.

**Example:**

```modula2
VAR
  sample: ARRAY [0..3] OF LONGREAL;
  proba: ARRAY [0..2] OF LONGREAL;
  pred: INTEGER;
sample[0] := 5.1; sample[1] := 3.5; sample[2] := 1.4; sample[3] := 0.2;
pred := KNN.PredictProba(m, ADR(sample), proba);
(* pred = 0, proba ~ [0.85, 0.10, 0.05] *)
```

---

### PredictBatch

```modula2
PROCEDURE PredictBatch(VAR m: Model;
                       data: ADDRESS; numSamples: CARDINAL;
                       predictions: ADDRESS);
```

Classifies multiple samples in a single call. `data` is a row-major matrix of `numSamples` rows by `numFeatures` columns of `LONGREAL` values. `predictions` points to an array of `numSamples` `INTEGER` values that will be filled with the predicted class labels. This is functionally equivalent to calling `Predict` in a loop but may be more convenient for batch evaluation.

**Example:**

```modula2
VAR
  testData: ARRAY [0..199] OF LONGREAL;  (* 50 samples x 4 features *)
  preds: ARRAY [0..49] OF INTEGER;
KNN.PredictBatch(m, ADR(testData), 50, ADR(preds));
(* preds[i] holds the predicted class for sample i *)
```

---

### SaveModel

```modula2
PROCEDURE SaveModel(VAR m: Model; path: ARRAY OF CHAR;
                    VAR ok: BOOLEAN);
```

Writes the complete model state to a binary file at the given path. This includes all model parameters, the fitted scaler state (if any), and the full training data and label arrays. Sets `ok` to `TRUE` on success, `FALSE` if the file could not be written. See the Model File Format section below for the binary layout.

**Example:**

```modula2
VAR ok: BOOLEAN;
KNN.SaveModel(m, "iris_model.knn", ok);
IF NOT ok THEN
  WriteString("Error: could not save model"); WriteLn;
END;
```

---

### LoadModel

```modula2
PROCEDURE LoadModel(VAR m: Model; path: ARRAY OF CHAR;
                    VAR ok: BOOLEAN);
```

Reads a model from a binary file previously created by `SaveModel`. The procedure allocates memory on the heap for the training data and labels, so the loaded model is self-contained and does not depend on any external arrays. Sets `ok` to `TRUE` on success, `FALSE` if the file could not be read or is malformed. Call `FreeModel` when the model is no longer needed to release the allocated memory.

**Example:**

```modula2
VAR
  m: Model;
  ok: BOOLEAN;
KNN.LoadModel(m, "iris_model.knn", ok);
IF ok THEN
  pred := KNN.Predict(m, ADR(sample));
END;
```

---

### FreeModel

```modula2
PROCEDURE FreeModel(VAR m: Model);
```

Deallocates the training data and label arrays that were allocated by `LoadModel`. If the model was trained via `Train` (where the caller owns the data), this procedure does nothing. Always call this when you are finished with a model that was loaded from disk.

**Example:**

```modula2
KNN.FreeModel(m);
(* Heap memory for training data and labels is released *)
```

## Model File Format

The `SaveModel` and `LoadModel` procedures use a binary format with the following layout. All multi-byte values are written in the native byte order of the platform.

| Offset | Size | Description |
|--------|------|-------------|
| 0 | 4 bytes | `numTrain` (CARDINAL) |
| 4 | 4 bytes | `numFeatures` (CARDINAL) |
| 8 | 4 bytes | `numClasses` (CARDINAL) |
| 12 | 4 bytes | `k` (CARDINAL) |
| 16 | 4 bytes | `metric` (DistMetric enumeration ordinal) |
| 20 | 4 bytes | `weighted` (BOOLEAN, 0 or 1) |
| 24 | 4 bytes | `hasScaler` (BOOLEAN, 0 or 1) |
| 28 | variable | `ScalerState` -- `numFeatures` (4 bytes) + `means` (128 * 8 bytes) + `stds` (128 * 8 bytes) + `fitted` (4 bytes) |
| ... | `numTrain * numFeatures * 8` bytes | Training data (LONGREAL matrix, row-major) |
| ... | `numTrain * 4` bytes | Training labels (INTEGER array) |

The scaler state is always written (even if `hasScaler` is `FALSE`) to keep the format fixed-width in the header portion. When `hasScaler` is `FALSE`, the scaler fields are present but ignored on load.

## Example

A complete program that trains a k-NN classifier on a small dataset, makes predictions, and saves the model to disk.

```modula2
MODULE KNNDemo;

FROM SYSTEM IMPORT ADR;
FROM STextIO IMPORT WriteString, WriteLn;
FROM SWholeIO IMPORT WriteInt;
FROM SLongIO IMPORT WriteFixed;
IMPORT KNN;

CONST
  NTrain    = 6;
  NFeatures = 2;
  NClasses  = 2;

VAR
  trainData: ARRAY [0..NTrain * NFeatures - 1] OF LONGREAL;
  trainLabels: ARRAY [0..NTrain - 1] OF INTEGER;
  sample: ARRAY [0..NFeatures - 1] OF LONGREAL;
  proba: ARRAY [0..NClasses - 1] OF LONGREAL;
  m: KNN.Model;
  pred: INTEGER;
  ok: BOOLEAN;

BEGIN
  (* Training data: two clusters in 2D *)
  (* Class 0: points near (1, 1) *)
  trainData[0] := 0.8; trainData[1] := 0.9;
  trainData[2] := 1.0; trainData[3] := 1.1;
  trainData[4] := 1.2; trainData[5] := 0.8;
  (* Class 1: points near (5, 5) *)
  trainData[6] := 4.8;  trainData[7] := 5.1;
  trainData[8] := 5.0;  trainData[9] := 4.9;
  trainData[10] := 5.2; trainData[11] := 5.0;

  trainLabels[0] := 0; trainLabels[1] := 0; trainLabels[2] := 0;
  trainLabels[3] := 1; trainLabels[4] := 1; trainLabels[5] := 1;

  (* Initialize: 3-NN, Euclidean distance, weighted voting *)
  KNN.Init(m, 3, NFeatures, NClasses, KNN.Euclidean, TRUE);

  (* Train with scaling enabled *)
  KNN.Train(m, ADR(trainData), ADR(trainLabels), NTrain, TRUE);

  (* Predict a new sample *)
  sample[0] := 1.5; sample[1] := 1.2;
  pred := KNN.PredictProba(m, ADR(sample), proba);

  WriteString("Predicted class: "); WriteInt(pred, 1); WriteLn;
  WriteString("  P(class 0) = "); WriteFixed(proba[0], 4, 8); WriteLn;
  WriteString("  P(class 1) = "); WriteFixed(proba[1], 4, 8); WriteLn;

  (* Save the trained model *)
  KNN.SaveModel(m, "demo_model.knn", ok);
  IF ok THEN
    WriteString("Model saved successfully."); WriteLn;
  ELSE
    WriteString("Error saving model."); WriteLn;
  END;
END KNNDemo.
```
