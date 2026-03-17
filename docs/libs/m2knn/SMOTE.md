# SMOTE

The `SMOTE` module implements the Synthetic Minority Over-sampling Technique for balancing imbalanced class distributions. It generates synthetic samples by interpolating between existing minority-class samples and their nearest neighbors.

## Why SMOTE?

Imbalanced datasets cause classifiers to be biased toward the majority class. SMOTE creates plausible synthetic samples for underrepresented classes, improving classifier performance without simply duplicating existing data.

## Procedures

### Oversample

```modula2
PROCEDURE Oversample(data: ADDRESS; labels: ADDRESS;
                     numSamples, numFeatures, numClasses: CARDINAL;
                     VAR newData: ADDRESS; VAR newLabels: ADDRESS;
                     VAR newNumSamples: CARDINAL);
```

Balance classes by generating synthetic samples. Each minority class is oversampled to match the majority class count.

- `data`: `numSamples x numFeatures` LONGREALs (row-major)
- `labels`: `numSamples` INTEGERs (0-based class indices)
- `newData`, `newLabels`: allocated balanced dataset
- `newNumSamples`: total samples after oversampling
- Caller must free with `FreeOversampled`

```modula2
VAR balData, balLabels: ADDRESS; balN: CARDINAL;
Oversample(data, labels, 100, 34, 3, balData, balLabels, balN);
(* balN >= 100, all classes now have equal representation *)
```

### FreeOversampled

```modula2
PROCEDURE FreeOversampled(VAR data: ADDRESS; VAR labels: ADDRESS);
```

Deallocate arrays from `Oversample`.
