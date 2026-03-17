# Thumbnail

The `Thumbnail` module finds the most representative segment of a musical audio signal. It builds a self-similarity matrix from mid-term features, applies diagonal convolution, and selects the segment that best captures the overall structure of the piece.

## Why Thumbnail?

Music thumbnailing answers "what part of this song best represents the whole?" -- useful for previews, search results, and content summarization. The self-similarity approach finds repeated structural elements (chorus, main theme) without needing genre-specific rules.

## Procedures

### FindThumbnail

```modula2
PROCEDURE FindThumbnail(featureMatrix: ADDRESS;
                         numFrames, numFeatures: CARDINAL;
                         thumbDurationFrames: CARDINAL;
                         VAR startFrame: CARDINAL;
                         VAR score: LONGREAL);
```

Find the most representative segment in a feature matrix.

- `featureMatrix`: `numFrames x numFeatures` LONGREALs (row-major), typically mid-term features
- `thumbDurationFrames`: desired thumbnail length in frames
- `startFrame`: index of the best thumbnail's first frame
- `score`: similarity score (higher = more representative)

```modula2
VAR start: CARDINAL; score: LONGREAL;
FindThumbnail(midFeats, nFrames, 68, 30, start, score);
(* start = 142, score = 0.87 — the chorus at frame 142 *)
```
