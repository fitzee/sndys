# Onset

The `Onset` module detects note and beat attack points in audio using spectral flux peak detection. It identifies transient moments where new sonic events begin.

## Why Onset?

Onset detection is fundamental to beat tracking, automatic transcription, audio-to-MIDI conversion, and rhythmic analysis. Spectral flux captures sudden changes in the frequency spectrum that correspond to note attacks, drum hits, and other transients.

## Constants

```modula2
CONST MaxOnsets = 4096;
```

Maximum number of onsets that can be detected in a single call.

## Procedures

### DetectOnsets

```modula2
PROCEDURE DetectOnsets(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                       sensitivity: LONGREAL;
                       VAR onsets: ARRAY OF LONGREAL;
                       VAR numOnsets: CARDINAL);
```

Find onset positions in a mono audio signal.

- `sensitivity`: multiplier for the detection threshold (typical 1.5). Lower values detect more onsets, higher values detect fewer.
- `onsets`: filled with onset times in seconds
- `numOnsets`: number of onsets detected

```modula2
VAR onsets: ARRAY [0..4095] OF LONGREAL; n: CARDINAL;
DetectOnsets(signal, numSamples, 44100, 1.5, onsets, n);
(* n = 42, onsets[0] = 0.12, onsets[1] = 0.58, ... *)
```
