# LDA

The `LDA` module implements Linear Discriminant Analysis for supervised dimensionality reduction. Unlike PCA, LDA finds projections that maximize class separation, making it ideal as a preprocessing step before classification.

## Why LDA?

PCA finds directions of maximum variance regardless of class labels. LDA specifically maximizes the ratio of between-class to within-class scatter, producing projections where different classes are better separated. This often improves classifier accuracy when the number of classes is small relative to the feature count.

## Types

```modula2
TYPE
  LDAState = RECORD
    numComponents: CARDINAL;
    numFeatures:   CARDINAL;
    projection:    ADDRESS;
    mean:          ADDRESS;
    fitted:        BOOLEAN;
  END;
```

## Procedures

### Init

```modula2
PROCEDURE Init(VAR l: LDAState; nComponents, nFeatures: CARDINAL);
```

Initialize LDA to project to `nComponents` dimensions. Typically `nComponents <= numClasses - 1`.

### Fit

```modula2
PROCEDURE Fit(VAR l: LDAState;
              data: ADDRESS;
              labels: ADDRESS;
              numSamples, numFeatures, numClasses: CARDINAL);
```

Compute discriminant projections from labeled data. `labels` is `numSamples` INTEGERs (0-based class indices).

### Transform

```modula2
PROCEDURE Transform(VAR l: LDAState;
                    data: ADDRESS;
                    numSamples: CARDINAL;
                    output: ADDRESS);
```

Project data onto fitted discriminants. `output` is `numSamples x numComponents` LONGREALs.

### FitTransform

```modula2
PROCEDURE FitTransform(VAR l: LDAState;
                       data: ADDRESS;
                       labels: ADDRESS;
                       numSamples, numFeatures, numClasses: CARDINAL;
                       output: ADDRESS);
```

Fit and transform in one step.

### Free

```modula2
PROCEDURE Free(VAR l: LDAState);
```

Deallocate internal buffers.

```modula2
VAR l: LDAState;
Init(l, 2, 34);
FitTransform(l, data, labels, 500, 34, 3, reduced);
(* reduced is 500 x 2, optimally separating 3 classes *)
Free(l);
```
