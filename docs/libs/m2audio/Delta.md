# Delta

The `Delta` module computes first-order difference (delta) features from a short-term feature matrix. Deltas capture the rate of change of each feature across frames, doubling the feature vector from 34 to 68 dimensions. Matches pyAudioAnalysis delta feature computation.

## Why Delta?

Static features describe "what the signal sounds like now." Delta features describe "how it's changing," which is critical for distinguishing transient events (speech onsets, drum hits) from sustained tones. Adding deltas consistently improves classification accuracy.

## Procedures

### ComputeDeltas

```modula2
PROCEDURE ComputeDeltas(featureMatrix: ADDRESS;
                        numFrames, numFeatures: CARDINAL;
                        VAR deltaMatrix: ADDRESS);
```

Compute frame-to-frame differences for each feature. `deltaMatrix` is allocated as `numFrames x numFeatures` LONGREALs. Delta[t] = features[t] - features[t-1], with Delta[0] = 0. Caller must free with `FreeDelta`.

```modula2
ComputeDeltas(feats, nFrames, 34, deltas);
(* deltas[0] = all zeros, deltas[1] = feats[1] - feats[0], ... *)
```

### CombineWithDeltas

```modula2
PROCEDURE CombineWithDeltas(featureMatrix: ADDRESS;
                            numFrames, numFeatures: CARDINAL;
                            VAR combined: ADDRESS);
```

Concatenate features and their deltas into a single matrix of `numFrames x (2 * numFeatures)` LONGREALs. Each row is `[feat0..feat33, delta0..delta33]`. Caller must free with `FreeDelta`.

```modula2
CombineWithDeltas(feats, nFrames, 34, combined);
(* combined has 68 columns per frame *)
```

### FreeDelta

```modula2
PROCEDURE FreeDelta(VAR matrix: ADDRESS);
```

Deallocate a delta or combined matrix.
