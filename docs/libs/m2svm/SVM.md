# SVM

The `SVM` module implements a Support Vector Machine classifier in pure Modula-2. It supports binary classification with linear or RBF kernels using simplified SMO (Sequential Minimal Optimization), and multi-class classification via one-vs-rest strategy.

## Why SVM?

SVMs find the maximum-margin decision boundary between classes, which often generalizes well on small-to-medium datasets. The RBF kernel handles non-linear boundaries. One-vs-rest extends binary SVM to any number of classes.

## Constants

```modula2
CONST MaxClasses = 32;
```

## Types

```modula2
TYPE
  KernelType = (Linear, RBF);

  SVMModel = RECORD
    alphas:      ADDRESS;
    trainData:   ADDRESS;
    trainLabels: ADDRESS;
    bias:        LONGREAL;
    numTrain:    CARDINAL;
    numFeatures: CARDINAL;
    C:           LONGREAL;     (* regularization *)
    kernel:      KernelType;
    gamma:       LONGREAL;     (* RBF gamma *)
    trained:     BOOLEAN;
  END;

  MultiSVM = RECORD
    models:      ARRAY [0..31] OF SVMModel;
    numClasses:  CARDINAL;
    numFeatures: CARDINAL;
  END;
```

## Procedures

### Binary SVM

```modula2
PROCEDURE Init(VAR m: SVMModel; nFeatures: CARDINAL;
               C: LONGREAL; kern: KernelType; gamma: LONGREAL);
```

Initialize a binary SVM. `C` controls regularization (typical 1.0). For RBF kernel, `gamma` controls the width (typical 0.01).

```modula2
PROCEDURE Train(VAR m: SVMModel; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
```

Train with simplified SMO. `labels` are `numSamples` LONGREALs valued +1.0 or -1.0.

```modula2
PROCEDURE Predict(VAR m: SVMModel; sample: ADDRESS): LONGREAL;
```

Returns the decision value. Sign indicates the class (+1 or -1).

```modula2
PROCEDURE Free(VAR m: SVMModel);
```

### Multi-class SVM

```modula2
PROCEDURE InitMulti(VAR m: MultiSVM; nClasses, nFeatures: CARDINAL;
                    C: LONGREAL; kern: KernelType; gamma: LONGREAL);
```

Initialize one-vs-rest multi-class SVM. Up to 32 classes.

```modula2
PROCEDURE TrainMulti(VAR m: MultiSVM; data: ADDRESS; labels: ADDRESS;
                     numSamples, numFeatures: CARDINAL);
```

Train one binary SVM per class. `labels` are `numSamples` INTEGERs (0-based).

```modula2
PROCEDURE PredictMulti(VAR m: MultiSVM; sample: ADDRESS): INTEGER;
```

Returns the predicted class index.

```modula2
PROCEDURE PredictMultiProba(VAR m: MultiSVM; sample: ADDRESS;
                            VAR scores: ARRAY OF LONGREAL): INTEGER;
```

Returns class index and fills `scores` with per-class decision values.

```modula2
PROCEDURE FreeMulti(VAR m: MultiSVM);
```

## Example

```modula2
VAR m: MultiSVM;
InitMulti(m, 3, 34, 1.0, RBF, 0.01);
TrainMulti(m, data, labels, 500, 34);
cls := PredictMulti(m, sample);
FreeMulti(m);
```
