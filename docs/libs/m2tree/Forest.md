# Forest

The `Forest` module implements Random Forest and Extra Trees ensemble classifiers. Both aggregate predictions from multiple decision trees trained on random subsets of data and features.

## Why Forest?

Random Forests are robust, resistant to overfitting, and consistently among the top performers for classification tasks. Extra Trees (Extremely Randomized Trees) add further randomization for faster training and sometimes better generalization.

## Types

```modula2
TYPE
  ForestType = (RandomForest, ExtraTrees);

  Forest = RECORD
    trees:       ARRAY [0..99] OF Tree;
    numTrees:    CARDINAL;
    forestType:  ForestType;
    numFeatures: CARDINAL;
    numClasses:  CARDINAL;
    maxDepth:    CARDINAL;
  END;
```

Supports up to 100 trees per forest.

## Procedures

### Init

```modula2
PROCEDURE Init(VAR f: Forest; nTrees, nFeatures, nClasses, maxDepth: CARDINAL;
               fType: ForestType);
```

Initialize a forest. `fType` selects between `RandomForest` and `ExtraTrees`.

### Train

```modula2
PROCEDURE Train(VAR f: Forest; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
```

Train all trees with bootstrap sampling and random feature subsets.

### Predict

```modula2
PROCEDURE Predict(VAR f: Forest; sample: ADDRESS): INTEGER;
```

Classify by majority vote across all trees.

### PredictProba

```modula2
PROCEDURE PredictProba(VAR f: Forest; sample: ADDRESS;
                       VAR proba: ARRAY OF LONGREAL): INTEGER;
```

Classify and return per-class vote proportions. `proba` is filled with `numClasses` values summing to 1.0. Returns the predicted class.

### Free

```modula2
PROCEDURE Free(VAR f: Forest);
```

Deallocate all trees.

```modula2
VAR f: Forest;
Init(f, 50, 34, 3, 15, RandomForest);
Train(f, data, labels, 500, 34);
cls := Predict(f, sample);
Free(f);
```
