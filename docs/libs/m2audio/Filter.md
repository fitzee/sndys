# Filter

The `Filter` module provides FFT-based frequency domain filtering: lowpass, highpass, and bandpass. Filtering is performed by zeroing spectral bins outside the passband, then inverse-transforming back to the time domain.

## Why Filter?

Frequency filtering is a core DSP operation -- removing noise, isolating frequency bands for analysis, or preprocessing audio before feature extraction. The spectral zeroing approach is simple and efficient for offline processing.

## Procedures

### Lowpass

```modula2
PROCEDURE Lowpass(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  cutoffHz: LONGREAL);
```

Remove frequencies above `cutoffHz`. In-place operation.

```modula2
Lowpass(signal, n, 44100, 4000.0);
(* Everything above 4 kHz is removed *)
```

### Highpass

```modula2
PROCEDURE Highpass(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                   cutoffHz: LONGREAL);
```

Remove frequencies below `cutoffHz`. In-place operation.

### Bandpass

```modula2
PROCEDURE Bandpass(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                   loHz, hiHz: LONGREAL);
```

Keep only frequencies between `loHz` and `hiHz`. In-place operation.

```modula2
Bandpass(signal, n, 44100, 300.0, 3400.0);
(* Telephone-band filtering *)
```
