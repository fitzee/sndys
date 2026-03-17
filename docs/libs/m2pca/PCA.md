# PCA

The `PCA` module implements Principal Component Analysis for dimensionality reduction. It projects high-dimensional feature vectors onto their principal components, retaining the directions of maximum variance.

## Why PCA?

Audio feature vectors (34 or 68 dimensions) can be redundant. PCA reduces dimensionality while preserving the most informative variation, speeding up downstream classifiers and enabling 2D/3D visualization of audio similarity.

## Types

```modula2
TYPE
  PCAState = RECORD
    numComponents: CARDINAL;
    numFeatures:   CARDINAL;
    components:    ADDRESS;
    mean:          ADDRESS;
    fitted:        BOOLEAN;
  END;
```

## Procedures

### Init

```modula2
PROCEDURE Init(VAR p: PCAState; nComponents, nFeatures: CARDINAL);
```

Initialize PCA to reduce `nFeatures` dimensions to `nComponents`.

### Fit

```modula2
PROCEDURE Fit(VAR p: PCAState;
              data: ADDRESS;
              numSamples, numFeatures: CARDINAL);
```

Compute principal components from training data (`numSamples x numFeatures` LONGREALs).

### Transform

```modula2
PROCEDURE Transform(VAR p: PCAState;
                    data: ADDRESS;
                    numSamples: CARDINAL;
                    output: ADDRESS);
```

Project data onto the fitted components. `output` is `numSamples x numComponents` LONGREALs. Must call `Fit` first.

### FitTransform

```modula2
PROCEDURE FitTransform(VAR p: PCAState;
                       data: ADDRESS;
                       numSamples, numFeatures: CARDINAL;
                       output: ADDRESS);
```

Fit and transform in one step. `output` is `numSamples x numComponents` LONGREALs.

### Free

```modula2
PROCEDURE Free(VAR p: PCAState);
```

Deallocate internal buffers.

```modula2
VAR p: PCAState;
Init(p, 10, 34);
FitTransform(p, data, 500, 34, reduced);
(* reduced is 500 x 10 LONGREALs *)
Free(p);
```
