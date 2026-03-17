# Stats

The `Stats` module provides basic statistical functions designed for audio and DSP feature extraction. All procedures operate on flat `LONGREAL` arrays passed as raw `ADDRESS` values with an explicit element count, using `LONGCARD` pointer arithmetic internally for 64-bit safety. Every function that returns a value degrades gracefully to `0.0` (or index `0`) when given an empty array.

## Why Stats?

Audio feature pipelines -- spectral analysis, MFCC extraction, onset detection -- lean heavily on a small set of statistical primitives: means, variances, entropy, normalization, and dot products. Implementing these once in a low-level, allocation-free module avoids repeated boilerplate across higher-level libraries like `ShortFeats` and `MidFeats`, keeps the hot path predictable, and makes the operations easy to call from any module that can produce an `ADDRESS`/`CARDINAL` pair from its buffer.

## Types

### RealPtr

```modula2
TYPE
  RealPtr = POINTER TO LONGREAL;
```

A typed pointer to a single `LONGREAL` element. Useful when callers need to dereference individual elements from a raw `ADDRESS` buffer by casting or advancing the pointer manually.

## Procedures

### Mean

```modula2
PROCEDURE Mean(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Computes the arithmetic mean of `n` elements starting at `data`. The array is interpreted as contiguous `LONGREAL` values. Returns `0.0` when `n` is `0`.

**Example:**

```modula2
VAR buf: ARRAY [0..3] OF LONGREAL;
    avg: LONGREAL;
buf[0] := 1.0; buf[1] := 2.0; buf[2] := 3.0; buf[3] := 4.0;
avg := Stats.Mean(ADR(buf), 4);
(* avg = 2.5 *)
```

---

### Variance

```modula2
PROCEDURE Variance(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Computes the population variance of `n` elements. This is the mean of the squared deviations from the arithmetic mean. Returns `0.0` when `n` is `0`.

**Example:**

```modula2
VAR buf: ARRAY [0..3] OF LONGREAL;
    v: LONGREAL;
buf[0] := 1.0; buf[1] := 2.0; buf[2] := 3.0; buf[3] := 4.0;
v := Stats.Variance(ADR(buf), 4);
(* v = 1.25 *)
```

---

### StdDev

```modula2
PROCEDURE StdDev(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Computes the population standard deviation -- the square root of the population variance. Returns `0.0` when `n` is `0`.

**Example:**

```modula2
VAR sd: LONGREAL;
sd := Stats.StdDev(ADR(buf), 4);
(* sd ~ 1.118 *)
```

---

### Min

```modula2
PROCEDURE Min(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Returns the minimum value found among the `n` elements. Returns `0.0` when `n` is `0`.

**Example:**

```modula2
VAR lo: LONGREAL;
lo := Stats.Min(ADR(buf), 4);
(* lo = 1.0 *)
```

---

### Max

```modula2
PROCEDURE Max(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Returns the maximum value found among the `n` elements. Returns `0.0` when `n` is `0`.

**Example:**

```modula2
VAR hi: LONGREAL;
hi := Stats.Max(ADR(buf), 4);
(* hi = 4.0 *)
```

---

### ArgMin

```modula2
PROCEDURE ArgMin(data: ADDRESS; n: CARDINAL): CARDINAL;
```

Returns the zero-based index of the minimum value in the array. If multiple elements share the minimum value, the index of the first occurrence is returned. Returns `0` when `n` is `0`.

**Example:**

```modula2
VAR idx: CARDINAL;
idx := Stats.ArgMin(ADR(buf), 4);
(* idx = 0 *)
```

---

### ArgMax

```modula2
PROCEDURE ArgMax(data: ADDRESS; n: CARDINAL): CARDINAL;
```

Returns the zero-based index of the maximum value in the array. If multiple elements share the maximum value, the index of the first occurrence is returned. Returns `0` when `n` is `0`.

**Example:**

```modula2
VAR idx: CARDINAL;
idx := Stats.ArgMax(ADR(buf), 4);
(* idx = 3 *)
```

---

### Sum

```modula2
PROCEDURE Sum(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Returns the sum of all `n` elements. Returns `0.0` when `n` is `0`.

**Example:**

```modula2
VAR s: LONGREAL;
s := Stats.Sum(ADR(buf), 4);
(* s = 10.0 *)
```

---

### SumSq

```modula2
PROCEDURE SumSq(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Returns the sum of squares of all `n` elements (i.e., the dot product of the array with itself). Useful for energy calculations in audio frames. Returns `0.0` when `n` is `0`.

**Example:**

```modula2
VAR ss: LONGREAL;
ss := Stats.SumSq(ADR(buf), 4);
(* ss = 1 + 4 + 9 + 16 = 30.0 *)
```

---

### Entropy

```modula2
PROCEDURE Entropy(data: ADDRESS; n: CARDINAL): LONGREAL;
```

Computes the Shannon entropy of the array using the natural logarithm. The data is treated as an unnormalized probability distribution: the procedure first normalizes by the sum, then computes `-SUM(p[i] * ln(p[i]))` over all non-zero elements. Returns `0.0` for all-zero input or when `n` is `0`. This is commonly used for spectral flatness and onset detection features.

**Example:**

```modula2
VAR prob: ARRAY [0..2] OF LONGREAL;
    h: LONGREAL;
prob[0] := 1.0; prob[1] := 1.0; prob[2] := 1.0;
h := Stats.Entropy(ADR(prob), 3);
(* h = ln(3) ~ 1.0986 -- uniform distribution has maximum entropy *)
```

---

### Normalize

```modula2
PROCEDURE Normalize(data: ADDRESS; n: CARDINAL);
```

Normalizes the array in-place so that its elements sum to `1.0`. Each element is divided by the sum of all elements. This is a no-op if the sum is `0.0` or `n` is `0`, preventing division by zero.

**Example:**

```modula2
VAR buf: ARRAY [0..2] OF LONGREAL;
buf[0] := 2.0; buf[1] := 3.0; buf[2] := 5.0;
Stats.Normalize(ADR(buf), 3);
(* buf = [0.2, 0.3, 0.5] *)
```

---

### ZScore

```modula2
PROCEDURE ZScore(data: ADDRESS; n: CARDINAL; mean, sd: LONGREAL);
```

Applies z-score normalization in-place: each element becomes `(x[i] - mean) / sd`. The caller supplies the precomputed `mean` and standard deviation `sd`, allowing reuse of values already calculated via `Mean` and `StdDev`. This is a no-op if `sd` is `0.0` or `n` is `0`.

**Example:**

```modula2
VAR buf: ARRAY [0..3] OF LONGREAL;
    m, s: LONGREAL;
buf[0] := 1.0; buf[1] := 2.0; buf[2] := 3.0; buf[3] := 4.0;
m := Stats.Mean(ADR(buf), 4);
s := Stats.StdDev(ADR(buf), 4);
Stats.ZScore(ADR(buf), 4, m, s);
(* buf ~ [-1.342, -0.447, 0.447, 1.342] *)
```

---

### DotProduct

```modula2
PROCEDURE DotProduct(a, b: ADDRESS; n: CARDINAL): LONGREAL;
```

Computes the dot product (inner product) of two vectors `a` and `b`, each containing `n` `LONGREAL` elements. Returns `0.0` when `n` is `0`. Useful for correlation and similarity calculations between audio feature vectors.

**Example:**

```modula2
VAR x, y: ARRAY [0..2] OF LONGREAL;
    dp: LONGREAL;
x[0] := 1.0; x[1] := 2.0; x[2] := 3.0;
y[0] := 4.0; y[1] := 5.0; y[2] := 6.0;
dp := Stats.DotProduct(ADR(x), ADR(y), 3);
(* dp = 4 + 10 + 18 = 32.0 *)
```

## Example

A complete program that loads sample data into a buffer, computes several descriptive statistics, normalizes the data, and prints the results.

```modula2
MODULE StatsDemo;

FROM SYSTEM IMPORT ADR;
FROM STextIO IMPORT WriteString, WriteLn;
FROM SLongIO IMPORT WriteFixed;
IMPORT Stats;

CONST
  N = 5;

VAR
  buf: ARRAY [0..N-1] OF LONGREAL;
  m, sd, v, s, h, dp: LONGREAL;
  lo, hi: LONGREAL;
  iMin, iMax: CARDINAL;
  i: CARDINAL;

BEGIN
  (* populate the buffer *)
  buf[0] := 4.0;
  buf[1] := 8.0;
  buf[2] := 15.0;
  buf[3] := 16.0;
  buf[4] := 23.0;

  (* descriptive statistics *)
  m  := Stats.Mean(ADR(buf), N);
  v  := Stats.Variance(ADR(buf), N);
  sd := Stats.StdDev(ADR(buf), N);
  s  := Stats.Sum(ADR(buf), N);
  lo := Stats.Min(ADR(buf), N);
  hi := Stats.Max(ADR(buf), N);
  iMin := Stats.ArgMin(ADR(buf), N);
  iMax := Stats.ArgMax(ADR(buf), N);

  WriteString("Mean:     "); WriteFixed(m,  4, 10); WriteLn;
  WriteString("Variance: "); WriteFixed(v,  4, 10); WriteLn;
  WriteString("StdDev:   "); WriteFixed(sd, 4, 10); WriteLn;
  WriteString("Sum:      "); WriteFixed(s,  4, 10); WriteLn;
  WriteString("Min:      "); WriteFixed(lo, 4, 10); WriteLn;
  WriteString("Max:      "); WriteFixed(hi, 4, 10); WriteLn;

  (* entropy of the raw values treated as weights *)
  h := Stats.Entropy(ADR(buf), N);
  WriteString("Entropy:  "); WriteFixed(h, 4, 10); WriteLn;

  (* dot product of the buffer with itself (= SumSq) *)
  dp := Stats.DotProduct(ADR(buf), ADR(buf), N);
  WriteString("SumSq:    "); WriteFixed(dp, 4, 10); WriteLn;

  (* z-score normalize in-place *)
  Stats.ZScore(ADR(buf), N, m, sd);
  WriteString("After ZScore:"); WriteLn;
  FOR i := 0 TO N-1 DO
    WriteString("  buf["); WriteFixed(LFLOAT(i), 0, 1);
    WriteString("] = "); WriteFixed(buf[i], 4, 10); WriteLn;
  END;
END StatsDemo.
```
