# AudioConcat

The `AudioConcat` module joins two mono audio signals end-to-end with an optional crossfade overlap.

## Why AudioConcat?

Concatenation with crossfading is essential for assembling audio from segments -- joining clips, building playlists, or reconstructing edited audio without audible clicks at boundaries.

## Procedures

### Concat

```modula2
PROCEDURE Concat(sigA: ADDRESS; numA: CARDINAL;
                 sigB: ADDRESS; numB: CARDINAL;
                 sampleRate: CARDINAL;
                 crossfadeSec: LONGREAL;
                 VAR output: ADDRESS; VAR outSamples: CARDINAL);
```

Join two mono signals. When `crossfadeSec > 0`, the end of A is linearly faded out while the start of B is faded in over the overlap region. When `crossfadeSec = 0`, signals are concatenated with a hard cut. Caller must free with `FreeConcat`.

```modula2
Concat(sigA, nA, sigB, nB, 44100, 0.5, result, nOut);
(* 0.5s crossfade between A and B *)
```

### FreeConcat

```modula2
PROCEDURE FreeConcat(VAR output: ADDRESS);
```

Deallocate concatenated output.
