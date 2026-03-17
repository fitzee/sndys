# VoiceFeats

The `VoiceFeats` module extracts voice and speech quality features: formant frequencies (F1, F2, F3), jitter, shimmer, and Harmonics-to-Noise Ratio (HNR). These are standard measures in clinical voice analysis and speaker characterization.

## Why VoiceFeats?

Voice quality features capture physiological and perceptual properties of speech that go beyond spectral shape. Formants define vowel identity and vocal tract resonances. Jitter and shimmer measure cycle-to-cycle pitch and amplitude perturbation, which correlate with voice disorders, breathiness, and roughness. HNR quantifies the ratio of periodic to aperiodic energy in the signal.

## Procedures

### ComputeFormants

```modula2
PROCEDURE ComputeFormants(frame: ADDRESS;
                           frameLen, sampleRate: CARDINAL;
                           VAR f1, f2, f3: LONGREAL);
```

Estimate the first three formant frequencies from a single audio frame using Linear Predictive Coding (LPC). Uses the autocorrelation method with Levinson-Durbin recursion at order 12, then finds peaks in the LPC spectral envelope.

### ComputeJitter

```modula2
PROCEDURE ComputeJitter(pitches: ADDRESS;
                         numFrames: CARDINAL): LONGREAL;
```

Compute relative jitter from a pitch contour. `pitches` is `numFrames` LONGREALs of F0 values (0 = unvoiced, skipped). Returns `mean(|period[i+1] - period[i]|) / mean(period)`. Typical values for healthy voices are below 1%.

### ComputeShimmer

```modula2
PROCEDURE ComputeShimmer(signal: ADDRESS;
                          numSamples, sampleRate: CARDINAL;
                          pitches: ADDRESS;
                          numFrames: CARDINAL): LONGREAL;
```

Compute relative shimmer from a signal and its pitch contour. Returns `mean(|amp[i+1] - amp[i]|) / mean(amp)`, measuring cycle-to-cycle amplitude variation. Typical values for healthy voices are below 3%.

### ComputeHNR

```modula2
PROCEDURE ComputeHNR(signal: ADDRESS;
                      numSamples, sampleRate: CARDINAL): LONGREAL;
```

Compute Harmonics-to-Noise Ratio in dB using autocorrelation: `10 * log10(r_peak / (r_0 - r_peak))`. Higher values indicate cleaner, more periodic voicing. Typical speech values range from 10-25 dB.

```modula2
VAR f1, f2, f3, jit, shim, hnr: LONGREAL;
ComputeFormants(frame, 1024, 16000, f1, f2, f3);
(* f1 = 520.0, f2 = 1480.0, f3 = 2520.0 for an open vowel *)
```
