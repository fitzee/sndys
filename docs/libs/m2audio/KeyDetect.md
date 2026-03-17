# KeyDetect

The `KeyDetect` module determines the musical key of an audio signal using the Krumhansl-Schmuckler key-finding algorithm. It correlates the averaged chroma vector against major and minor key profiles to find the best match.

## Why KeyDetect?

Key detection enables automatic music organization, harmonic mixing for DJs, transposition assistance, and music information retrieval. The Krumhansl-Schmuckler algorithm is a well-established musicological approach that works across genres.

## Procedures

### DetectKey

```modula2
PROCEDURE DetectKey(signal: ADDRESS; numSamples, sampleRate: CARDINAL;
                    VAR keyName: ARRAY OF CHAR;
                    VAR confidence: LONGREAL);
```

Determine the musical key of a mono audio signal. Extracts short-term chroma features, averages them, and correlates against all 24 major/minor key profiles.

- `signal`: `numSamples` LONGREALs (mono)
- `keyName`: filled with the detected key (e.g., "C major", "A minor")
- `confidence`: correlation with the best-matching profile, 0.0 to 1.0

```modula2
VAR key: ARRAY [0..31] OF CHAR; conf: LONGREAL;
DetectKey(signal, n, 44100, key, conf);
(* key = "G major", conf = 0.72 *)
```
