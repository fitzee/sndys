# DTree

The `DTree` module implements a decision tree classifier with configurable maximum depth. It supports standard training on full datasets and subset training with feature masking (used internally by Random Forest and Gradient Boosting).

## Why DTree?

Decision trees are interpretable, fast to train, and serve as the foundation for ensemble methods (Random Forest, Gradient Boosting). A single tree can overfit, but ensembles of trees are among the most effective classifiers for structured data.

## Types

```modula2
TYPE
  TreeNode = RECORD
    featureIdx:  INTEGER;
    threshold:   LONGREAL;
    leftChild:   INTEGER;
    rightChild:  INTEGER;
    classLabel:  INTEGER;
    numSamples:  CARDINAL;
  END;

  Tree = RECORD
    nodes:       ADDRESS;
    numNodes:    CARDINAL;
    maxNodes:    CARDINAL;
    numFeatures: CARDINAL;
    numClasses:  CARDINAL;
    maxDepth:    CARDINAL;
  END;
```

## Procedures

### Init

```modula2
PROCEDURE Init(VAR t: Tree; nFeatures, nClasses, maxDepth: CARDINAL);
```

Initialize a tree for the given feature count, class count, and maximum depth.

### Train

```modula2
PROCEDURE Train(VAR t: Tree; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
```

Train on the full dataset. `data` is `numSamples x numFeatures` LONGREALs. `labels` is `numSamples` INTEGERs.

### Predict

```modula2
PROCEDURE Predict(VAR t: Tree; sample: ADDRESS): INTEGER;
```

Classify a single sample. Returns the class index.

### PredictBatch

```modula2
PROCEDURE PredictBatch(VAR t: Tree; data: ADDRESS; numSamples: CARDINAL;
                       predictions: ADDRESS);
```

Classify multiple samples. `predictions` is `numSamples` INTEGERs.

### Free

```modula2
PROCEDURE Free(VAR t: Tree);
```

Deallocate tree nodes.

### TrainSubset

```modula2
PROCEDURE TrainSubset(VAR t: Tree; data: ADDRESS; labels: ADDRESS;
                      numSamples, numFeatures: CARDINAL;
                      sampleIndices: ADDRESS; numSubSamples: CARDINAL;
                      featureMask: ADDRESS; numMaskFeatures: CARDINAL;
                      useRandomThresholds: BOOLEAN; seed: CARDINAL);
```

Train on a subset of samples and features. Used internally by `Forest` and `GBoost` for bagging and feature subsampling.

```modula2
VAR t: Tree;
Init(t, 34, 3, 10);
Train(t, data, labels, 500, 34);
cls := Predict(t, sample);
Free(t);
```
