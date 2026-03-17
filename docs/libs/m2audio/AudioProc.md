# AudioProc

The `AudioProc` module provides audio processing utilities: trimming, mixing, normalization, fading, reversing, and signal generation. All operations work on mono LONGREAL sample arrays.

## Why AudioProc?

These are the building blocks for audio editing pipelines -- extracting regions, combining files, adjusting levels, and generating test signals. Having them in a library enables scripted audio processing without external tools.

## Procedures

### Trim

```modula2
PROCEDURE Trim(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
               startSec, endSec: LONGREAL;
               VAR output: ADDRESS; VAR outSamples: CARDINAL);
```

Extract a time region from a signal. Caller must free output with `FreeProc`.

### Mix

```modula2
PROCEDURE Mix(signalA: ADDRESS; numA: CARDINAL;
              signalB: ADDRESS; numB: CARDINAL;
              mixRatio: LONGREAL;
              VAR output: ADDRESS; VAR outSamples: CARDINAL);
```

Mix two mono signals. `mixRatio`: 0.0 = only A, 1.0 = only B, 0.5 = equal mix. Shorter signal is zero-padded. Caller must free with `FreeProc`.

### Normalize

```modula2
PROCEDURE Normalize(signal: ADDRESS; numSamples: CARDINAL;
                    targetPeak: LONGREAL);
```

Peak normalization in-place. Scales so the maximum absolute value equals `targetPeak` (typical 1.0 or 0.95).

### NormalizeRMS

```modula2
PROCEDURE NormalizeRMS(signal: ADDRESS; numSamples: CARDINAL;
                       targetRMS: LONGREAL);
```

RMS normalization in-place. Scales so the RMS level equals `targetRMS` (typical 0.1).

### FadeIn / FadeOut

```modula2
PROCEDURE FadeIn(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                 fadeSec: LONGREAL);
PROCEDURE FadeOut(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  fadeSec: LONGREAL);
```

Apply linear fade-in or fade-out in-place over `fadeSec` seconds.

### Reverse

```modula2
PROCEDURE Reverse(signal: ADDRESS; numSamples: CARDINAL);
```

Reverse signal in-place.

### GenerateSine

```modula2
PROCEDURE GenerateSine(freq: LONGREAL; durationSec: LONGREAL;
                       sampleRate: CARDINAL; amplitude: LONGREAL;
                       VAR output: ADDRESS; VAR outSamples: CARDINAL);
```

Generate a sine wave. Caller must free with `FreeProc`.

### GenerateChirp

```modula2
PROCEDURE GenerateChirp(startFreq, endFreq, durationSec: LONGREAL;
                        sampleRate: CARDINAL; amplitude: LONGREAL;
                        VAR output: ADDRESS; VAR outSamples: CARDINAL);
```

Generate a linear frequency sweep from `startFreq` to `endFreq`. Caller must free with `FreeProc`.

### GenerateNoise

```modula2
PROCEDURE GenerateNoise(durationSec: LONGREAL;
                        sampleRate: CARDINAL; amplitude: LONGREAL;
                        VAR output: ADDRESS; VAR outSamples: CARDINAL);
```

Generate white noise using LCG PRNG. Values in `[-amplitude, amplitude]`. Caller must free with `FreeProc`.

### GenerateClick

```modula2
PROCEDURE GenerateClick(bpm, durationSec: LONGREAL;
                        sampleRate: CARDINAL;
                        VAR output: ADDRESS; VAR outSamples: CARDINAL);
```

Generate a click track at the given BPM. Caller must free with `FreeProc`.

### FreeProc

```modula2
PROCEDURE FreeProc(VAR output: ADDRESS);
```

Deallocate output from any processing/generation function.
