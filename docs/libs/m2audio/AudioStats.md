# AudioStats

The `AudioStats` module computes summary statistics for a mono audio signal: RMS level, peak level, crest factor, DC offset, dB values, and clipping detection.

## Why AudioStats?

These are the standard metrics for assessing audio quality and loudness. RMS and peak levels reveal dynamic range, crest factor indicates compression, DC offset flags recording issues, and clipping counts identify distortion.

## Types

```modula2
TYPE
  StatsResult = RECORD
    rmsLevel:    LONGREAL;  (* root mean square *)
    peakLevel:   LONGREAL;  (* maximum absolute value *)
    crestFactor: LONGREAL;  (* peak / RMS in dB *)
    dcOffset:    LONGREAL;  (* mean sample value *)
    rmsDB:       LONGREAL;  (* 20*log10(rms), relative to 1.0 *)
    peakDB:      LONGREAL;  (* 20*log10(peak), relative to 1.0 *)
    numClipped:  CARDINAL;  (* samples at or above 0.99 *)
    numSamples:  CARDINAL;
    duration:    LONGREAL;  (* seconds *)
  END;
```

## Procedures

### Analyze

```modula2
PROCEDURE Analyze(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                  VAR result: StatsResult);
```

Compute all audio statistics on a mono signal normalized to [-1.0, 1.0].

```modula2
VAR r: StatsResult;
Analyze(signal, n, 44100, r);
(* r.rmsDB = -18.5, r.peakDB = -3.2, r.crestFactor = 15.3 *)
```
