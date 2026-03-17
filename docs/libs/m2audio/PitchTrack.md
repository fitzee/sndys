# PitchTrack

The `PitchTrack` module extracts a continuous F0 (fundamental frequency) contour from a mono audio signal with median smoothing. It produces a time series of pitch estimates suitable for melody analysis, intonation tracking, or pitch-based classification.

## Why PitchTrack?

Single-frame F0 estimates (as in `Harmonic`) are noisy. PitchTrack produces a smoothed pitch contour over the entire signal, enabling melody extraction, speaker prosody analysis, and music transcription.

## Procedures

### TrackPitch

```modula2
PROCEDURE TrackPitch(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                     smoothWindow: CARDINAL;
                     VAR pitches: ADDRESS;
                     VAR times: ADDRESS;
                     VAR numFrames: CARDINAL);
```

Extract a pitch contour from a mono signal.

- `smoothWindow`: median filter size (odd number, e.g. 5)
- `pitches`: allocated array of `numFrames` LONGREALs (Hz, 0.0 = unvoiced)
- `times`: allocated array of `numFrames` LONGREALs (seconds)
- Caller must free with `FreePitch`

```modula2
TrackPitch(signal, n, 44100, 5, pitches, times, nF);
(* pitches[0] = 440.0, pitches[1] = 441.2, ... *)
```

### FreePitch

```modula2
PROCEDURE FreePitch(VAR pitches: ADDRESS; VAR times: ADDRESS);
```

Deallocate pitch and time arrays.
