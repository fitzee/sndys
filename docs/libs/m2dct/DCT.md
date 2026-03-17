# DCT

The `DCT` module provides Discrete Cosine Transform routines for use in audio feature extraction pipelines. It implements the forward DCT-II, a partial (truncated) DCT-II, and the inverse DCT-III. All procedures operate on buffers of `LONGREAL` values passed by `ADDRESS`, making them compatible with dynamically allocated arrays and foreign-memory workflows common in Modula-2 signal-processing code.

## Why DCT?

In MFCC (Mel-Frequency Cepstral Coefficient) computation, the DCT serves as the final decorrelation step. After the audio signal has been windowed, transformed to the frequency domain via FFT, and passed through a mel-scaled filterbank, the resulting log-energies are still correlated. Applying the DCT-II to these log-energies compresses the information into a small number of cepstral coefficients whose lower indices capture the broad spectral shape of the signal -- exactly the representation that speech and audio classifiers expect. The `ForwardPartial` procedure is purpose-built for this step: it computes only the first few DCT coefficients, avoiding the cost of a full transform when only 12-13 MFCCs are needed out of, say, 26 or 40 filterbank channels. The inverse DCT-III is provided for reconstruction and synthesis tasks where the original filterbank energies must be recovered from their cepstral representation.

## Procedures

### Forward

```modula2
PROCEDURE Forward(input: ADDRESS; n: CARDINAL; output: ADDRESS);
```

Computes the full DCT-II of the input buffer, producing `n` output coefficients. Both `input` and `output` point to contiguous arrays of `n` `LONGREAL` values. The `output` buffer must not alias `input`.

The transform computed is:

```
X[k] = sum_{i=0}^{N-1} x[i] * cos(pi/N * (i + 0.5) * k),   k = 0 .. N-1
```

**Usage example -- full DCT of a 4-element signal:**

```modula2
VAR
  inp, out: ARRAY [0..3] OF LONGREAL;
BEGIN
  inp[0] := 1.0; inp[1] := 2.0; inp[2] := 3.0; inp[3] := 4.0;
  Forward(ADR(inp), 4, ADR(out));
  (* out now contains all 4 DCT-II coefficients *)
END;
```

### ForwardPartial

```modula2
PROCEDURE ForwardPartial(input: ADDRESS; n: CARDINAL;
                         output: ADDRESS; numCoeffs: CARDINAL);
```

Computes only the first `numCoeffs` DCT-II coefficients from an input buffer of `n` `LONGREAL` values. The `output` buffer must hold at least `numCoeffs` `LONGREAL` values. This is the primary entry point for MFCC extraction: pass the log mel-filterbank energies as `input`, the number of filterbank channels as `n`, and the desired number of cepstral coefficients (typically 12 or 13) as `numCoeffs`.

**Usage example -- extracting 13 MFCCs from 26 filterbank energies:**

```modula2
VAR
  logMelEnergies: ARRAY [0..25] OF LONGREAL;
  mfcc:          ARRAY [0..12] OF LONGREAL;
BEGIN
  (* ... fill logMelEnergies from mel filterbank ... *)
  ForwardPartial(ADR(logMelEnergies), 26, ADR(mfcc), 13);
  (* mfcc[0..12] now holds the 13 cepstral coefficients *)
END;
```

### Inverse

```modula2
PROCEDURE Inverse(input: ADDRESS; n: CARDINAL; output: ADDRESS);
```

Computes the inverse DCT (DCT-III) of the input buffer, recovering the original time- or filterbank-domain signal. Both `input` and `output` point to arrays of `n` `LONGREAL` values. The transform computed is:

```
x[i] = (1/N) * X[0]/2 + (1/N) * sum_{k=1}^{N-1} X[k] * cos(pi/N * k * (i + 0.5)),   i = 0 .. N-1
```

**Usage example -- round-trip forward then inverse:**

```modula2
VAR
  original, spectrum, recovered: ARRAY [0..3] OF LONGREAL;
BEGIN
  original[0] := 1.0; original[1] := 2.0;
  original[2] := 3.0; original[3] := 4.0;
  Forward(ADR(original), 4, ADR(spectrum));
  Inverse(ADR(spectrum), 4, ADR(recovered));
  (* recovered should approximate original *)
END;
```

## Example

A complete program module that reads a hard-coded log mel-filterbank vector, extracts 13 MFCCs via `ForwardPartial`, prints them, then reconstructs an approximation of the original energies with `Inverse`.

```modula2
MODULE MFCCDemo;

FROM SYSTEM IMPORT ADR;
FROM DCT   IMPORT ForwardPartial, Forward, Inverse;
FROM InOut  IMPORT WriteString, WriteLn;
FROM RealInOut IMPORT WriteReal;

CONST
  NumFilters = 26;
  NumMFCC    = 13;

VAR
  logMel:      ARRAY [0..NumFilters-1]  OF LONGREAL;
  mfcc:        ARRAY [0..NumMFCC-1]     OF LONGREAL;
  fullDCT:     ARRAY [0..NumFilters-1]  OF LONGREAL;
  recovered:   ARRAY [0..NumFilters-1]  OF LONGREAL;
  i:           CARDINAL;

BEGIN
  (* Populate log mel-filterbank energies with a simple ramp *)
  FOR i := 0 TO NumFilters-1 DO
    logMel[i] := FLOAT(i) * 0.1;
  END;

  (* Step 1: extract 13 MFCCs *)
  ForwardPartial(ADR(logMel), NumFilters, ADR(mfcc), NumMFCC);

  WriteString("MFCC coefficients:"); WriteLn;
  FOR i := 0 TO NumMFCC-1 DO
    WriteString("  c[");
    WriteReal(FLOAT(i), 2);
    WriteString("] = ");
    WriteReal(mfcc[i], 12);
    WriteLn;
  END;

  (* Step 2: full forward + inverse round-trip to verify reconstruction *)
  Forward(ADR(logMel), NumFilters, ADR(fullDCT));
  Inverse(ADR(fullDCT), NumFilters, ADR(recovered));

  WriteLn;
  WriteString("Round-trip reconstruction (first 5 bins):"); WriteLn;
  FOR i := 0 TO 4 DO
    WriteString("  original=");
    WriteReal(logMel[i], 12);
    WriteString("  recovered=");
    WriteReal(recovered[i], 12);
    WriteLn;
  END;
END MFCCDemo.
```
