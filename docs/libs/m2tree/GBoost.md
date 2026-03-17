# GBoost

The `GBoost` module implements gradient boosting classification using decision tree stumps. It builds an ensemble of shallow trees sequentially, with each tree correcting the errors of the previous ones. Multi-class is handled via one-vs-rest.

## Why GBoost?

Gradient boosting often achieves the highest accuracy among tree-based methods by focusing each successive tree on the hardest-to-classify samples. It trades training speed for prediction quality.

## Types

```modula2
TYPE
  GBModel = RECORD
    trees:          ARRAY [0..199] OF Tree;
    weights:        ARRAY [0..199] OF LONGREAL;
    numTrees:       CARDINAL;
    numClasses:     CARDINAL;
    numFeatures:    CARDINAL;
    learningRate:   LONGREAL;
    actualNumTrees: CARDINAL;
  END;
```

Supports up to 200 trees. For multi-class, trees are grouped by class: tree index = `round * numClasses + classIdx`.

## Procedures

### Init

```modula2
PROCEDURE Init(VAR m: GBModel; nTrees, nFeatures, nClasses: CARDINAL;
               lr: LONGREAL);
```

Initialize with `nTrees` boosting rounds and learning rate `lr` (typical 0.1).

### Train

```modula2
PROCEDURE Train(VAR m: GBModel; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
```

Train the boosting ensemble. `data` is `numSamples x numFeatures` LONGREALs. `labels` is `numSamples` INTEGERs.

### Predict

```modula2
PROCEDURE Predict(VAR m: GBModel; sample: ADDRESS): INTEGER;
```

Classify a single sample by summing weighted tree predictions.

### Free

```modula2
PROCEDURE Free(VAR m: GBModel);
```

Deallocate all trees.

```modula2
VAR m: GBModel;
Init(m, 100, 34, 3, 0.1);
Train(m, data, labels, 500, 34);
cls := Predict(m, sample);
Free(m);
```
