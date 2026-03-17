# FFT

The `FFT` module provides a radix-2 Cooley-Tukey Fast Fourier Transform implementation designed for audio and DSP work. All routines operate in-place on flat `LONGREAL` arrays using interleaved complex format, and the transform size must always be a power of two.

## Why FFT?

The naive Discrete Fourier Transform runs in O(n^2) time, which is unusable for real-time audio at buffer sizes of 1024 samples or more. The Cooley-Tukey radix-2 algorithm computes the same result in O(n log n) time by recursively splitting the transform into smaller sub-problems. This module gives you a single-call interface to forward and inverse transforms, plus the most common post-processing steps (magnitude spectrum, power spectrum), so you can go from raw PCM samples to frequency-domain analysis without pulling in an external C library.

## Data Format

Every routine in this module works with **interleaved complex arrays**. A complex signal of N points is stored as a flat array of 2*N `LONGREAL` values laid out as:

```
[re0, im0, re1, im1, re2, im2, ..., re(N-1), im(N-1)]
```

Element `2*i` is the real part of sample `i`, and element `2*i + 1` is the imaginary part. When you start from a purely real signal (the common case for audio), use `RealToComplex` to pack it into this layout with all imaginary parts set to zero before calling `Forward`.

Output arrays for `Magnitude`, `PowerSpectrum`, and `NormalizedPowerSpectrum` are plain real arrays of N `LONGREAL` values, one per frequency bin.

## Procedures

### Forward

```modula2
PROCEDURE Forward(data: ADDRESS; n: CARDINAL);
```

Performs an in-place forward FFT using decimation-in-time. `data` must point to an array of `2*n` `LONGREAL` values in interleaved complex format. After the call, `data` contains the complex frequency-domain representation of the input signal. `n` must be a power of two.

**Usage example:**

```modula2
(* Assuming buf already holds interleaved complex data for 1024 points *)
Forward(ADR(buf), 1024);
(* buf now contains the frequency-domain spectrum *)
```

### Inverse

```modula2
PROCEDURE Inverse(data: ADDRESS; n: CARDINAL);
```

Performs an in-place inverse FFT. Internally this conjugates the data, applies the forward transform, conjugates again, and scales every element by `1/n`. The result is the original time-domain signal (within floating-point precision). `data` must point to `2*n` `LONGREAL` values and `n` must be a power of two.

**Usage example:**

```modula2
(* Round-trip: forward then inverse recovers the original signal *)
Forward(ADR(buf), 1024);
(* ... manipulate spectrum ... *)
Inverse(ADR(buf), 1024);
(* buf is back in the time domain *)
```

### Magnitude

```modula2
PROCEDURE Magnitude(data: ADDRESS; n: CARDINAL; mag: ADDRESS);
```

Computes the magnitude spectrum from frequency-domain data. For each bin `i`, the output is `sqrt(re[i]^2 + im[i]^2)`. `data` points to `2*n` interleaved `LONGREAL` values (the FFT output). `mag` points to a separate output array of `n` `LONGREAL` values that receives the magnitudes.

**Usage example:**

```modula2
VAR
  spectrum : ARRAY [0..2047] OF LONGREAL; (* 1024-point interleaved *)
  mag      : ARRAY [0..1023] OF LONGREAL;

Forward(ADR(spectrum), 1024);
Magnitude(ADR(spectrum), 1024, ADR(mag));
(* mag[i] now holds the amplitude of bin i *)
```

### PowerSpectrum

```modula2
PROCEDURE PowerSpectrum(data: ADDRESS; n: CARDINAL; power: ADDRESS);
```

Computes the power spectrum from frequency-domain data. For each bin `i`, the output is `re[i]^2 + im[i]^2` (the squared magnitude, without the square root). `data` points to `2*n` interleaved `LONGREAL` values. `power` points to a separate output array of `n` `LONGREAL` values.

**Usage example:**

```modula2
VAR
  spectrum : ARRAY [0..2047] OF LONGREAL;
  pwr      : ARRAY [0..1023] OF LONGREAL;

Forward(ADR(spectrum), 1024);
PowerSpectrum(ADR(spectrum), 1024, ADR(pwr));
(* pwr[i] = re[i]^2 + im[i]^2 *)
```

### NormalizedPowerSpectrum

```modula2
PROCEDURE NormalizedPowerSpectrum(data: ADDRESS; n: CARDINAL;
                                  power: ADDRESS);
```

Computes the power spectrum and divides each bin by `n`. This is the standard normalization used in spectral analysis so that the power values are independent of the transform size. `data` points to `2*n` interleaved `LONGREAL` values. `power` points to a separate output array of `n` `LONGREAL` values.

**Usage example:**

```modula2
VAR
  spectrum : ARRAY [0..2047] OF LONGREAL;
  pwr      : ARRAY [0..1023] OF LONGREAL;

Forward(ADR(spectrum), 1024);
NormalizedPowerSpectrum(ADR(spectrum), 1024, ADR(pwr));
(* pwr[i] = (re[i]^2 + im[i]^2) / 1024 *)
```

### RealToComplex

```modula2
PROCEDURE RealToComplex(realIn: ADDRESS; n: CARDINAL;
                        complexOut: ADDRESS);
```

Packs a real-valued signal into interleaved complex format suitable for the FFT routines. `realIn` points to `n` `LONGREAL` values (the raw signal). `complexOut` points to an output array of `2*n` `LONGREAL` values. Each real sample is copied into the real part of the corresponding complex slot, and the imaginary part is set to zero.

**Usage example:**

```modula2
VAR
  samples  : ARRAY [0..1023] OF LONGREAL; (* raw audio *)
  spectrum : ARRAY [0..2047] OF LONGREAL; (* interleaved complex *)

RealToComplex(ADR(samples), 1024, ADR(spectrum));
(* spectrum is now [samples[0], 0.0, samples[1], 0.0, ...] *)
```

## Example

A complete program that reads 1024 real samples from an array, computes the FFT, and prints the magnitude of each frequency bin:

```modula2
MODULE FFTDemo;

FROM SYSTEM IMPORT ADR;
FROM FFT   IMPORT RealToComplex, Forward, Magnitude;
FROM STextIO IMPORT WriteString, WriteLn;
FROM SRealIO IMPORT WriteFixed;
FROM SWholeIO IMPORT WriteCard;

CONST
  N = 1024;

VAR
  samples  : ARRAY [0..N-1]   OF LONGREAL;
  spectrum : ARRAY [0..2*N-1] OF LONGREAL;
  mag      : ARRAY [0..N-1]   OF LONGREAL;
  i        : CARDINAL;

BEGIN
  (* Fill samples with a test signal -- a pure 32-cycle sine wave *)
  FOR i := 0 TO N-1 DO
    samples[i] := LFLOAT(0) (* replace with actual signal data *)
  END;

  (* Pack real samples into interleaved complex format *)
  RealToComplex(ADR(samples), N, ADR(spectrum));

  (* Forward FFT *)
  Forward(ADR(spectrum), N);

  (* Extract magnitudes *)
  Magnitude(ADR(spectrum), N, ADR(mag));

  (* Print each bin *)
  FOR i := 0 TO N-1 DO
    WriteString("Bin ");
    WriteCard(i, 4);
    WriteString(": ");
    WriteFixed(mag[i], 6, 12);
    WriteLn
  END
END FFTDemo.
```
