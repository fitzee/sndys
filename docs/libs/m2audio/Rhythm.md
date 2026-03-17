# Rhythm

The `Rhythm` module provides rhythm analysis features that complement the tempo estimation in `Beat`: tempo stability and beat strength. These measure how consistent and prominent the rhythmic pulse is over time.

## Why Rhythm?

Tempo estimation gives a single BPM value, but music varies in how steady and pronounced its beat is. Tempo stability distinguishes a metronomic electronic track from a rubato classical performance. Beat strength separates music with a strong rhythmic drive from ambient or arrhythmic material. Together, these features are useful for genre classification, playlist generation, and music similarity.

## Procedures

### TempoStability

```modula2
PROCEDURE TempoStability(bpms: ADDRESS;
                          numPoints: CARDINAL): LONGREAL;
```

Compute tempo stability as the coefficient of variation (standard deviation / mean) of a BPM curve. The `bpms` array is `numPoints` LONGREALs, typically produced by `TempoCurve`. Lower values indicate more stable tempo; 0.0 means perfectly steady. Values above 0.3 suggest significant tempo variation.

### BeatStrength

```modula2
PROCEDURE BeatStrength(signal: ADDRESS;
                        numSamples, sampleRate: CARDINAL): LONGREAL;
```

Compute beat strength as the ratio of peak spectral flux at the beat period to average flux. Higher values indicate a more pronounced, perceptible beat. Strongly rhythmic music (dance, rock) typically scores above 2.0; ambient and speech score below 1.5.

```modula2
VAR stability, strength: LONGREAL;
TempoStability(bpmCurve, numPoints, stability);
(* stability = 0.05 for steady electronic music *)
BeatStrength(signal, numSamples, 44100, strength);
(* strength = 3.2 for a dance track *)
```
