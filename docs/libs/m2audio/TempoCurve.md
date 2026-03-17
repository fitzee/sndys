# TempoCurve

The `TempoCurve` module estimates BPM over time using windowed beat detection. Unlike `Beat` which produces a single BPM for the whole file, TempoCurve shows how tempo evolves -- useful for live performances, rubato passages, or DJ transitions.

## Why TempoCurve?

Most real music does not have a perfectly constant tempo. TempoCurve reveals tempo changes, accelerandos, ritardandos, and tempo transitions between sections.

## Procedures

### ComputeTempoCurve

```modula2
PROCEDURE ComputeTempoCurve(signal: ADDRESS;
                             numSamples, sampleRate: CARDINAL;
                             windowSec, hopSec: LONGREAL;
                             VAR bpms: ADDRESS;
                             VAR times: ADDRESS;
                             VAR numPoints: CARDINAL);
```

Estimate BPM in sliding windows across the signal.

- `windowSec`: analysis window duration (e.g. 10.0 seconds)
- `hopSec`: step between windows (e.g. 5.0 seconds)
- `bpms`: allocated array of `numPoints` LONGREALs
- `times`: allocated array of `numPoints` LONGREALs (center time of each window)
- Caller must free with `FreeTempoCurve`

```modula2
ComputeTempoCurve(signal, n, 44100, 10.0, 5.0, bpms, times, nP);
(* bpms[0] = 120.0, bpms[1] = 121.5, ... *)
```

### FreeTempoCurve

```modula2
PROCEDURE FreeTempoCurve(VAR bpms: ADDRESS; VAR times: ADDRESS);
```

Deallocate BPM and time arrays.
