# KMeans

The `KMeans` module implements k-means clustering with Lloyd's algorithm, including batch prediction and silhouette scoring for cluster quality evaluation.

## Why KMeans?

K-means is the workhorse of unsupervised learning -- it groups data points into k clusters based on feature similarity. In audio, it drives speaker diarization, sound event grouping, and codebook generation for audio retrieval.

## Types

```modula2
TYPE
  KMeansResult = RECORD
    centroids:   ADDRESS;
    labels:      ADDRESS;
    numClusters: CARDINAL;
    numFeatures: CARDINAL;
    numSamples:  CARDINAL;
    iterations:  CARDINAL;
    converged:   BOOLEAN;
  END;
```

## Procedures

### Init

```modula2
PROCEDURE Init(VAR r: KMeansResult; k, nFeatures: CARDINAL);
```

Initialize a KMeansResult for `k` clusters with `nFeatures` dimensions.

### Fit

```modula2
PROCEDURE Fit(VAR r: KMeansResult;
              data: ADDRESS;
              numSamples, numFeatures, numClusters, maxIter: CARDINAL;
              tolerance: LONGREAL);
```

Run k-means clustering on `data` (`numSamples x numFeatures` LONGREALs, row-major). Iterates until convergence or `maxIter` is reached. `tolerance` controls the convergence threshold on centroid movement.

### Predict

```modula2
PROCEDURE Predict(VAR r: KMeansResult; sample: ADDRESS): INTEGER;
```

Assign a single sample to its nearest cluster. Returns the cluster index.

### PredictBatch

```modula2
PROCEDURE PredictBatch(VAR r: KMeansResult;
                       data: ADDRESS;
                       numSamples: CARDINAL;
                       labels: ADDRESS);
```

Assign multiple samples to clusters. `labels` is `numSamples` INTEGERs.

### Silhouette

```modula2
PROCEDURE Silhouette(VAR r: KMeansResult; data: ADDRESS): LONGREAL;
```

Compute the mean silhouette score (-1 to 1). Higher values indicate better-defined clusters.

### FreeResult

```modula2
PROCEDURE FreeResult(VAR r: KMeansResult);
```

Deallocate centroids and labels.

```modula2
VAR r: KMeansResult;
Init(r, 3, 34);
Fit(r, data, 500, 34, 3, 100, 0.001);
cluster := Predict(r, sample);
score := Silhouette(r, data);
FreeResult(r);
```
