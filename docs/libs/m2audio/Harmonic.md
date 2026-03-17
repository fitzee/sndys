# Harmonic

The `Harmonic` module estimates the harmonic ratio and fundamental frequency (F0) of an audio frame via autocorrelation. The harmonic ratio measures how periodic a signal is (1.0 = pure tone, 0.0 = noise), while F0 gives the pitch in Hz.

## Why Harmonic?

Harmonic ratio separates tonal from noisy content -- voiced speech from unvoiced, pitched instruments from percussion. F0 estimation is the basis of pitch tracking, melody extraction, and speaker identification.

## Procedures

### ComputeHarmonicF0

```modula2
PROCEDURE ComputeHarmonicF0(frame: ADDRESS; frameLen, sampleRate: CARDINAL;
                             VAR harmonicRatio: LONGREAL;
                             VAR f0: LONGREAL);
```

Estimate harmonic ratio and fundamental frequency for a single audio frame. Searches for the autocorrelation peak in the 50-500 Hz range.

- `frame`: `frameLen` LONGREALs
- `sampleRate`: sampling frequency in Hz
- `harmonicRatio`: 0.0 (noise) to 1.0 (pure tone)
- `f0`: fundamental frequency in Hz

```modula2
VAR hr, f0: LONGREAL;
ComputeHarmonicF0(framePtr, 2048, 44100, hr, f0);
(* hr = 0.85, f0 = 440.0 for an A4 note *)
```
