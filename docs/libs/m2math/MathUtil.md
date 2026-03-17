# MathUtil

Extended math utilities for DSP and audio analysis. All floating-point procedures operate on `LONGREAL` (64-bit double) and are built on top of `MathLib` (`sqrt`, `sin`, `cos`, `exp`, `ln`, `arctan`). The module provides common transcendental functions, rounding, clamping, and power-of-two helpers that the standard library omits.

## Why MathUtil?

Modula-2's `MathLib` exposes only a handful of primitives -- natural log, square root, and the basic trigonometric functions. Real-world DSP and audio code constantly needs base-10 and base-2 logarithms, arbitrary exponentiation, floor/ceil rounding, floating-point remainder, and fast power-of-two queries. Scattering the same `ln(x) / ln(10)` expression across every call site is error-prone and hard to read. `MathUtil` collects these derived operations into one place with clear names, correct edge-case handling, and double-precision constants so that higher-level modules can focus on signal processing rather than arithmetic boilerplate.

## Constants

### Pi
```
Pi = 3.14159265358979323846D0
```
The ratio of a circle's circumference to its diameter. Used throughout trigonometric calculations, FFT twiddle factors, and angular conversions.

### TwoPi
```
TwoPi = 6.28318530717958647692D0
```
Two times Pi. Provided as a pre-computed constant to avoid repeated multiplication in phase accumulators and full-rotation calculations.

### Ln10
```
Ln10 = 2.30258509299404568402D0
```
The natural logarithm of 10. Used internally by `Log10` and available for any base-10 logarithmic conversion.

### E
```
E = 2.71828182845904523536D0
```
Euler's number, the base of the natural logarithm. Useful for exponential growth/decay computations and envelope generation.

## Procedures

### Log10
```modula2
PROCEDURE Log10(x: LONGREAL): LONGREAL;
```
Returns the base-10 logarithm of `x`, computed as `ln(x) / ln(10)`. The argument `x` must be strictly greater than zero. This is the function you reach for when converting a linear amplitude ratio to decibels (`20.0 * Log10(ratio)`).

```modula2
VAR dB: LONGREAL;
dB := 20.0D0 * Log10(amplitude / reference);
```

### Log2
```modula2
PROCEDURE Log2(x: LONGREAL): LONGREAL;
```
Returns the base-2 logarithm of `x`, computed as `ln(x) / ln(2)`. The argument `x` must be strictly greater than zero. Handy for determining how many bits are needed to represent a value or for octave calculations in audio.

```modula2
VAR bits: LONGREAL;
bits := Log2(FLOAT(sampleCount));
```

### Pow
```modula2
PROCEDURE Pow(base, expon: LONGREAL): LONGREAL;
```
Raises `base` to the power `expon` by computing `exp(expon * ln(base))`. When `base` is `0.0` and `expon` is positive, the result is `0.0`. Use this for any arbitrary exponentiation that the language does not provide natively.

```modula2
VAR gain: LONGREAL;
gain := Pow(10.0D0, dB / 20.0D0);  (* dB back to linear *)
```

### Floor
```modula2
PROCEDURE Floor(x: LONGREAL): LONGINT;
```
Returns the largest integer not greater than `x`. The result type is `LONGINT`. Use `Floor` when you need to round toward negative infinity -- for example, mapping a continuous frequency value to a discrete bin index.

```modula2
VAR bin: LONGINT;
bin := Floor(freq / binWidth);
```

### Ceil
```modula2
PROCEDURE Ceil(x: LONGREAL): LONGINT;
```
Returns the smallest integer not less than `x`. The result type is `LONGINT`. Useful when you must round up to guarantee that a buffer is large enough to hold all samples.

```modula2
VAR frames: LONGINT;
frames := Ceil(durationSec * sampleRate);
```

### FAbs
```modula2
PROCEDURE FAbs(x: LONGREAL): LONGREAL;
```
Returns the absolute value of `x`. A simple convenience that avoids an `IF` branch and makes intent clear when working with `LONGREAL` values.

```modula2
VAR error: LONGREAL;
error := FAbs(measured - expected);
```

### FMod
```modula2
PROCEDURE FMod(x, y: LONGREAL): LONGREAL;
```
Returns the floating-point remainder of `x / y`, computed as `x - TRUNC(x/y) * y`. The divisor `y` must not be zero. Use `FMod` to wrap a phase accumulator back into a fixed range.

```modula2
VAR phase: LONGREAL;
phase := FMod(phase + increment, TwoPi);
```

### Clamp
```modula2
PROCEDURE Clamp(x, lo, hi: LONGREAL): LONGREAL;
```
Constrains `x` to the closed interval `[lo, hi]`. Returns `lo` if `x < lo`, `hi` if `x > hi`, and `x` otherwise. Essential for keeping signal values within a legal output range.

```modula2
VAR sample: LONGREAL;
sample := Clamp(sample, -1.0D0, 1.0D0);
```

### Hypot
```modula2
PROCEDURE Hypot(x, y: LONGREAL): LONGREAL;
```
Returns the hypotenuse length `sqrt(x*x + y*y)`. Use it to compute the magnitude of a complex FFT bin from its real and imaginary parts.

```modula2
VAR mag: LONGREAL;
mag := Hypot(re, im);
```

### NextPow2
```modula2
PROCEDURE NextPow2(n: CARDINAL): CARDINAL;
```
Returns the smallest power of two that is greater than or equal to `n`. When `n` is zero the result is `1`. This is the standard way to round a buffer size up to a power-of-two length required by radix-2 FFT algorithms.

```modula2
VAR fftLen: CARDINAL;
fftLen := NextPow2(windowSize);  (* e.g. 600 -> 1024 *)
```

### IsPow2
```modula2
PROCEDURE IsPow2(n: CARDINAL): BOOLEAN;
```
Returns `TRUE` if `n` is a power of two and `n > 0`. A quick guard before calling an FFT routine that requires power-of-two input length.

```modula2
IF NOT IsPow2(bufLen) THEN
  bufLen := NextPow2(bufLen);
END;
```

## Example

A complete program module that reads a linear amplitude ratio, converts it to decibels, clamps the result, and prints the dB value along with the next power-of-two FFT size for a given window length.

```modula2
MODULE MathDemo;

FROM InOut    IMPORT WriteString, WriteLn;
FROM RealInOut IMPORT WriteReal;
FROM MathUtil IMPORT Pi, TwoPi, Log10, Pow, Clamp, Hypot,
                     NextPow2, IsPow2, FAbs;

VAR
  amplitude, reference, dB, clamped: LONGREAL;
  re, im, mag: LONGREAL;
  windowSize, fftLen: CARDINAL;

BEGIN
  (* --- dB conversion --- *)
  amplitude := 0.25D0;
  reference := 1.0D0;
  dB := 20.0D0 * Log10(amplitude / reference);
  clamped := Clamp(dB, -96.0D0, 0.0D0);

  WriteString("Amplitude : ");  WriteReal(amplitude, 12);  WriteLn;
  WriteString("dB        : ");  WriteReal(dB, 12);         WriteLn;
  WriteString("Clamped dB: ");  WriteReal(clamped, 12);    WriteLn;

  (* --- complex magnitude --- *)
  re :=  0.6D0;
  im := -0.8D0;
  mag := Hypot(re, im);
  WriteString("Magnitude : ");  WriteReal(mag, 12);  WriteLn;

  (* --- FFT size selection --- *)
  windowSize := 600;
  fftLen := NextPow2(windowSize);
  WriteString("Window    : ");  WriteReal(FLOAT(windowSize), 8);  WriteLn;
  WriteString("FFT length: ");  WriteReal(FLOAT(fftLen), 8);      WriteLn;

  IF IsPow2(fftLen) THEN
    WriteString("FFT length is a power of two -- ready.");
  END;
  WriteLn;

  (* --- verify round-trip --- *)
  dB := -12.0D0;
  amplitude := Pow(10.0D0, dB / 20.0D0);
  WriteString("Round-trip: ");
  WriteReal(20.0D0 * Log10(amplitude), 12);
  WriteString(" dB");
  WriteLn;
END MathDemo.
```
