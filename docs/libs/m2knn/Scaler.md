# Scaler

The `Scaler` module implements per-feature z-score (standard score) normalization for row-major feature matrices stored as flat `LONGREAL` arrays. It computes the mean and standard deviation of each feature column from training data, then transforms any compatible matrix so that every column has zero mean and unit variance. This is essential preprocessing for distance-based classifiers like k-NN, where features on different scales would otherwise dominate the distance calculation in proportion to their magnitude rather than their informational value.

## Why Scaler?

Distance-based algorithms treat every dimension of the feature space equally. If one feature ranges from 0 to 1000 while another ranges from 0 to 1, the first feature will overwhelm the distance computation and the second feature will contribute almost nothing, regardless of its actual predictive power. Z-score normalization eliminates this problem by centering each feature at zero and scaling it to unit variance. The `Scaler` module encapsulates this transform in a fit/transform pattern so that the same statistics learned from training data can be applied consistently to test data and new samples at prediction time, avoiding data leakage and ensuring reproducible results.

## Constants

### MaxFeatures

```modula2
CONST
  MaxFeatures = 128;
```

The maximum number of features (columns) the scaler can handle. The internal `means` and `stds` arrays are sized to this limit. Attempting to initialize a scaler with more than 128 features will exceed the array bounds.

## Types

### ScalerState

```modula2
TYPE
  ScalerState = RECORD
    numFeatures: CARDINAL;
    means: ARRAY [0..127] OF LONGREAL;
    stds:  ARRAY [0..127] OF LONGREAL;
    fitted: BOOLEAN;
  END;
```

Holds the learned statistics for normalization. `numFeatures` records how many feature columns the scaler was initialized for. `means` and `stds` store the per-column arithmetic mean and population standard deviation computed during fitting. `fitted` is `TRUE` once `Fit` or `FitTransform` has been called, and must be `TRUE` before `Transform` or `InverseTransform` can be used.

## Procedures

### Init

```modula2
PROCEDURE Init(VAR sc: ScalerState; nFeatures: CARDINAL);
```

Initializes a `ScalerState` for the given number of features. Sets `numFeatures`, zeros out the `means` and `stds` arrays, and sets `fitted` to `FALSE`. This must be called before any other scaler procedure.

**Example:**

```modula2
VAR sc: ScalerState;
Scaler.Init(sc, 4);
(* sc is ready for a 4-feature dataset *)
```

---

### Fit

```modula2
PROCEDURE Fit(VAR sc: ScalerState;
              data: ADDRESS; numSamples, numFeatures: CARDINAL);
```

Computes the mean and standard deviation for each feature column from the supplied data and stores them in the scaler. `data` points to a row-major matrix of `numSamples` rows and `numFeatures` columns of `LONGREAL` values, where element `[i, j]` is at index `i * numFeatures + j`. After this call, `sc.fitted` is `TRUE`. The data itself is not modified.

**Example:**

```modula2
VAR
  sc: ScalerState;
  data: ARRAY [0..11] OF LONGREAL;
  (* 3 samples x 4 features *)
data[0] := 1.0;  data[1] := 2.0;  data[2] := 3.0;  data[3] := 4.0;
data[4] := 5.0;  data[5] := 6.0;  data[6] := 7.0;  data[7] := 8.0;
data[8] := 9.0;  data[9] := 10.0; data[10] := 11.0; data[11] := 12.0;
Scaler.Init(sc, 4);
Scaler.Fit(sc, ADR(data), 3, 4);
(* sc.means = [5.0, 6.0, 7.0, 8.0], sc.stds ~ [3.27, 3.27, 3.27, 3.27] *)
```

---

### Transform

```modula2
PROCEDURE Transform(VAR sc: ScalerState;
                    data: ADDRESS; numSamples, numFeatures: CARDINAL);
```

Applies z-score normalization in-place using the previously fitted means and standard deviations. Each element is replaced by `(x[i,j] - mean[j]) / std[j]`. The scaler must have been fitted first via `Fit` or `FitTransform`. This is the procedure to use when transforming test data or new samples using statistics learned from training data.

**Example:**

```modula2
(* After fitting on training data: *)
Scaler.Transform(sc, ADR(testData), numTestSamples, 4);
(* testData is now normalized using training statistics *)
```

---

### FitTransform

```modula2
PROCEDURE FitTransform(VAR sc: ScalerState;
                       data: ADDRESS; numSamples, numFeatures: CARDINAL);
```

A convenience procedure that calls `Fit` followed by `Transform` on the same data. This is the typical workflow for training data: learn the statistics and normalize in a single step. The data is modified in-place.

**Example:**

```modula2
VAR sc: ScalerState;
Scaler.Init(sc, 4);
Scaler.FitTransform(sc, ADR(trainData), numTrainSamples, 4);
(* trainData is now normalized; sc holds the learned statistics *)
```

---

### InverseTransform

```modula2
PROCEDURE InverseTransform(VAR sc: ScalerState;
                           data: ADDRESS;
                           numSamples, numFeatures: CARDINAL);
```

Reverses the z-score normalization in-place, restoring the original scale of the data. Each element is replaced by `x[i,j] * std[j] + mean[j]`. The scaler must have been fitted first. This is useful when you need to convert normalized predictions or feature values back to their original units for display or further processing.

**Example:**

```modula2
(* Undo normalization to recover original-scale values *)
Scaler.InverseTransform(sc, ADR(data), numSamples, 4);
(* data is back in original feature space *)
```

## Example

A complete program that creates a small feature matrix, fits a scaler, normalizes the data, prints the result, and then reverses the transformation to recover the original values.

```modula2
MODULE ScalerDemo;

FROM SYSTEM IMPORT ADR;
FROM STextIO IMPORT WriteString, WriteLn;
FROM SLongIO IMPORT WriteFixed;
IMPORT Scaler;

CONST
  NSamples  = 3;
  NFeatures = 2;

VAR
  data: ARRAY [0..NSamples * NFeatures - 1] OF LONGREAL;
  sc: Scaler.ScalerState;
  i, j: CARDINAL;

BEGIN
  (* 3 samples, 2 features:
     Sample 0: height=170cm, weight=60kg
     Sample 1: height=180cm, weight=75kg
     Sample 2: height=160cm, weight=50kg *)
  data[0] := 170.0; data[1] := 60.0;
  data[2] := 180.0; data[3] := 75.0;
  data[4] := 160.0; data[5] := 50.0;

  (* Initialize and fit-transform *)
  Scaler.Init(sc, NFeatures);
  Scaler.FitTransform(sc, ADR(data), NSamples, NFeatures);

  WriteString("After z-score normalization:"); WriteLn;
  FOR i := 0 TO NSamples - 1 DO
    WriteString("  Sample "); WriteFixed(LFLOAT(i), 0, 1);
    WriteString(": [");
    FOR j := 0 TO NFeatures - 1 DO
      WriteFixed(data[i * NFeatures + j], 4, 8);
      IF j < NFeatures - 1 THEN WriteString(", ") END;
    END;
    WriteString("]"); WriteLn;
  END;

  (* Print learned parameters *)
  WriteString("Means: [");
  WriteFixed(sc.means[0], 2, 8); WriteString(", ");
  WriteFixed(sc.means[1], 2, 8); WriteString("]"); WriteLn;
  WriteString("Stds:  [");
  WriteFixed(sc.stds[0], 2, 8); WriteString(", ");
  WriteFixed(sc.stds[1], 2, 8); WriteString("]"); WriteLn;

  (* Inverse transform to recover original values *)
  Scaler.InverseTransform(sc, ADR(data), NSamples, NFeatures);

  WriteString("After inverse transform:"); WriteLn;
  FOR i := 0 TO NSamples - 1 DO
    WriteString("  Sample "); WriteFixed(LFLOAT(i), 0, 1);
    WriteString(": [");
    FOR j := 0 TO NFeatures - 1 DO
      WriteFixed(data[i * NFeatures + j], 2, 8);
      IF j < NFeatures - 1 THEN WriteString(", ") END;
    END;
    WriteString("]"); WriteLn;
  END;
END ScalerDemo.
```
