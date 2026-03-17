# AudioIO

The `AudioIO` module provides higher-level audio I/O built on top of the `m2wav` library. It handles reading WAV files into normalized mono `LONGREAL` signals and applying pre-emphasis filtering, giving you a clean starting point for any audio analysis pipeline without worrying about channel layout, bit depth, or sample format details.

## Why AudioIO?

Raw WAV file reading requires dealing with channel counts, sample formats, and byte-level parsing. When you are building an audio analysis tool, you want to go from a file path to a normalized floating-point mono signal in one call. `AudioIO` wraps the low-level `Wav` module to give you exactly that: a single `ReadAudio` call that accepts any mono or stereo WAV file and hands back a `LONGREAL` array in the [-1.0, 1.0] range. It also provides `PreEmphasis`, the standard first step in speech and audio feature extraction, which boosts high-frequency content and improves the performance of downstream algorithms like MFCC computation.

## Procedures

### ReadAudio

```modula2
PROCEDURE ReadAudio(path: ARRAY OF CHAR;
                    VAR signal: ADDRESS;
                    VAR numSamples: CARDINAL;
                    VAR sampleRate: CARDINAL;
                    VAR ok: BOOLEAN);
```

Reads a WAV file from disk and returns a mono signal normalized to the [-1.0, 1.0] range. If the input file is stereo, the two channels are automatically averaged into a single mono signal. Files with more than two channels are rejected. The returned `signal` is a dynamically allocated array of `numSamples` `LONGREAL` values that the caller must free with `FreeSignal` when finished. On failure, `ok` is set to `FALSE` and `signal` is `NIL`.

**Usage example:**

```modula2
VAR
  sig      : ADDRESS;
  nSamples : CARDINAL;
  rate     : CARDINAL;
  ok       : BOOLEAN;

ReadAudio("recording.wav", sig, nSamples, rate, ok);
IF ok THEN
  (* sig points to nSamples LONGREALs, sample rate is in rate *)
  FreeSignal(sig)
END;
```

### FreeSignal

```modula2
PROCEDURE FreeSignal(VAR signal: ADDRESS);
```

Deallocates the signal array returned by `ReadAudio`. After this call, `signal` is set to `NIL`. It is safe to call on a `NIL` pointer (it does nothing).

**Usage example:**

```modula2
FreeSignal(sig);
(* sig is now NIL *)
```

### PreEmphasis

```modula2
PROCEDURE PreEmphasis(signal: ADDRESS; n: CARDINAL;
                      coeff: LONGREAL; output: ADDRESS);
```

Applies a first-order pre-emphasis filter to the signal. The filter is defined as `y[n] = x[n] - coeff * x[n-1]`, with `y[0] = x[0]`. The typical coefficient value is 0.97, which amplifies higher frequencies relative to lower ones. This is a standard preprocessing step in speech analysis and MFCC computation. The `output` buffer must be caller-allocated with space for `n` `LONGREAL` values. It is safe for `output` to point to the same buffer as `signal` (in-place operation), but only if you do not need the original signal afterward.

**Usage example:**

```modula2
VAR
  filtered : ADDRESS;

ALLOCATE(filtered, nSamples * TSIZE(LONGREAL));
PreEmphasis(sig, nSamples, 0.97, filtered);
(* filtered now contains the pre-emphasized signal *)
```

## Example

A complete program that reads a WAV file, applies pre-emphasis, and prints the first 10 samples of both the original and filtered signals:

```modula2
MODULE AudioIODemo;

FROM SYSTEM  IMPORT ADR, ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM InOut   IMPORT WriteString, WriteLn, WriteCard;
FROM AudioIO IMPORT ReadAudio, FreeSignal, PreEmphasis;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

VAR
  sig, filtered : ADDRESS;
  nSamples, rate : CARDINAL;
  ok : BOOLEAN;
  i  : CARDINAL;
  p  : RealPtr;

BEGIN
  ReadAudio("speech.wav", sig, nSamples, rate, ok);
  IF NOT ok THEN
    WriteString("Failed to read WAV file.");
    WriteLn;
    RETURN
  END;

  WriteString("Sample rate: ");
  WriteCard(rate, 0);
  WriteLn;
  WriteString("Samples:     ");
  WriteCard(nSamples, 0);
  WriteLn;
  WriteLn;

  (* Allocate and apply pre-emphasis *)
  ALLOCATE(filtered, nSamples * TSIZE(LONGREAL));
  PreEmphasis(sig, nSamples, 0.97, filtered);

  (* Print first 10 samples: original vs. filtered *)
  WriteString("  Index   Original   Filtered");
  WriteLn;
  FOR i := 0 TO 9 DO
    WriteCard(i, 6);
    WriteString("  ");
    p := Elem(sig, i);
    (* print p^ *)
    WriteString("  ");
    p := Elem(filtered, i);
    (* print p^ *)
    WriteLn
  END;

  DEALLOCATE(filtered, nSamples * TSIZE(LONGREAL));
  FreeSignal(sig)
END AudioIODemo.
```
