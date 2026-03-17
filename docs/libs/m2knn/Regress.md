# Regress

The `Regress` module provides k-NN regression for predicting continuous values. It works like k-NN classification but averages neighbor target values instead of majority voting, with optional distance weighting and StandardScaler support.

## Why Regress?

k-NN regression is a simple, non-parametric approach for predicting continuous variables (loudness, pitch, tempo) from feature vectors. It requires no model fitting beyond storing training data and works well when the relationship between features and targets is locally smooth.

## Types

```modula2
TYPE
  RegModel = RECORD
    trainData:    ADDRESS;
    trainTargets: ADDRESS;
    numTrain:     CARDINAL;
    numFeatures:  CARDINAL;
    k:            CARDINAL;
    weighted:     BOOLEAN;
    scaler:       ScalerState;
    hasScaler:    BOOLEAN;
  END;
```

## Procedures

### Init

```modula2
PROCEDURE Init(VAR m: RegModel; k, numFeatures: CARDINAL;
               weighted: BOOLEAN);
```

Initialize a regression model with the given k and feature count.

### Train

```modula2
PROCEDURE Train(VAR m: RegModel;
                data: ADDRESS; targets: ADDRESS;
                numSamples: CARDINAL; scale: BOOLEAN);
```

Store training data and targets. `data` is `numSamples x numFeatures` LONGREALs. `targets` is `numSamples` LONGREALs. If `scale=TRUE`, fits and applies a StandardScaler.

### Predict

```modula2
PROCEDURE Predict(VAR m: RegModel; sample: ADDRESS): LONGREAL;
```

Predict a continuous value for a single sample (`numFeatures` LONGREALs).

### PredictBatch

```modula2
PROCEDURE PredictBatch(VAR m: RegModel;
                       data: ADDRESS; numSamples: CARDINAL;
                       predictions: ADDRESS);
```

Predict values for multiple samples. `predictions` is `numSamples` LONGREALs.

### MSE

```modula2
PROCEDURE MSE(VAR m: RegModel;
              data: ADDRESS; targets: ADDRESS;
              numSamples: CARDINAL): LONGREAL;
```

Compute mean squared error on test data.

```modula2
VAR m: RegModel;
Init(m, 5, 34, TRUE);
Train(m, trainData, trainTargets, 100, TRUE);
val := Predict(m, testSample);
err := MSE(m, testData, testTargets, 20);
```
