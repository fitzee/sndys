IMPLEMENTATION MODULE FFT;
(* Radix-2 Cooley-Tukey FFT — decimation-in-time.

   Complex data is interleaved: [re0, im0, re1, im1, ...].
   An N-point transform uses 2*N LONGREALs.

   Twiddle factors use sin/cos from MathLib0 (REAL precision),
   widened to LONGREAL for accumulation. *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathLib0 IMPORT sin, cos, sqrt;

TYPE
  RealPtr = POINTER TO LONGREAL;

CONST
  Pi = 3.14159265358979323846D0;

(* ── Helper: element access via pointer arithmetic ──── *)

PROCEDURE Get(base: ADDRESS; idx: CARDINAL): LONGREAL;
VAR p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(LONGREAL)));
  RETURN p^
END Get;

PROCEDURE Put(base: ADDRESS; idx: CARDINAL; val: LONGREAL);
VAR p: RealPtr;
BEGIN
  p := RealPtr(LONGCARD(base) + LONGCARD(idx) * LONGCARD(TSIZE(LONGREAL)));
  p^ := val
END Put;

(* ── Bit-reversal permutation ──────────────────────── *)

PROCEDURE BitReverse(data: ADDRESS; n: CARDINAL);
VAR i, j, m: CARDINAL;
    tmpRe, tmpIm: LONGREAL;
BEGIN
  j := 0;
  i := 0;
  WHILE i < n DO
    IF i < j THEN
      (* swap complex elements i and j *)
      tmpRe := Get(data, 2 * i);
      tmpIm := Get(data, 2 * i + 1);
      Put(data, 2 * i, Get(data, 2 * j));
      Put(data, 2 * i + 1, Get(data, 2 * j + 1));
      Put(data, 2 * j, tmpRe);
      Put(data, 2 * j + 1, tmpIm)
    END;
    m := n DIV 2;
    WHILE (m >= 1) AND (j >= m) DO
      j := j - m;
      m := m DIV 2
    END;
    j := j + m;
    INC(i)
  END
END BitReverse;

(* ── Power-of-two check ────────────────────────────── *)

PROCEDURE IsPowerOfTwo(n: CARDINAL): BOOLEAN;
VAR v: CARDINAL;
BEGIN
  IF n = 0 THEN RETURN FALSE END;
  v := n;
  WHILE (v > 1) AND (v MOD 2 = 0) DO
    v := v DIV 2
  END;
  RETURN v = 1
END IsPowerOfTwo;

(* ── Forward FFT ───────────────────────────────────── *)

PROCEDURE Forward(data: ADDRESS; n: CARDINAL);
VAR size, halfSize, k, idx1, idx2: CARDINAL;
    angle, wr, wi, tRe, tIm: LONGREAL;
    re1, im1, re2, im2: LONGREAL;
BEGIN
  IF n <= 1 THEN RETURN END;
  IF NOT IsPowerOfTwo(n) THEN RETURN END;

  BitReverse(data, n);

  size := 2;
  WHILE size <= n DO
    halfSize := size DIV 2;
    angle := -2.0D0 * Pi / LFLOAT(size);
    k := 0;
    WHILE k < halfSize DO
      wr := LFLOAT(cos(FLOAT(angle * LFLOAT(k))));
      wi := LFLOAT(sin(FLOAT(angle * LFLOAT(k))));
      idx1 := k;
      WHILE idx1 < n DO
        idx2 := idx1 + halfSize;
        (* butterfly — load both elements once *)
        re2 := Get(data, 2 * idx2);
        im2 := Get(data, 2 * idx2 + 1);
        tRe := wr * re2 - wi * im2;
        tIm := wr * im2 + wi * re2;
        re1 := Get(data, 2 * idx1);
        im1 := Get(data, 2 * idx1 + 1);
        Put(data, 2 * idx1, re1 + tRe);
        Put(data, 2 * idx1 + 1, im1 + tIm);
        Put(data, 2 * idx2, re1 - tRe);
        Put(data, 2 * idx2 + 1, im1 - tIm);
        idx1 := idx1 + size
      END;
      INC(k)
    END;
    size := size * 2
  END
END Forward;

(* ── Inverse FFT ───────────────────────────────────── *)

PROCEDURE Conjugate(data: ADDRESS; n: CARDINAL);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE i < n DO
    Put(data, 2 * i + 1, -Get(data, 2 * i + 1));
    INC(i)
  END
END Conjugate;

PROCEDURE Inverse(data: ADDRESS; n: CARDINAL);
VAR i: CARDINAL;
    scale: LONGREAL;
BEGIN
  IF n <= 1 THEN RETURN END;
  IF NOT IsPowerOfTwo(n) THEN RETURN END;
  Conjugate(data, n);
  Forward(data, n);
  Conjugate(data, n);
  scale := 1.0 / LFLOAT(n);
  i := 0;
  WHILE i < n DO
    Put(data, 2 * i, Get(data, 2 * i) * scale);
    Put(data, 2 * i + 1, Get(data, 2 * i + 1) * scale);
    INC(i)
  END
END Inverse;

(* ── Magnitude spectrum ────────────────────────────── *)

PROCEDURE Magnitude(data: ADDRESS; n: CARDINAL; mag: ADDRESS);
VAR i: CARDINAL;
    re, im: LONGREAL;
BEGIN
  i := 0;
  WHILE i < n DO
    re := Get(data, 2 * i);
    im := Get(data, 2 * i + 1);
    Put(mag, i, LFLOAT(sqrt(FLOAT(re * re + im * im))));
    INC(i)
  END
END Magnitude;

(* ── Power spectrum ────────────────────────────────── *)

PROCEDURE PowerSpectrum(data: ADDRESS; n: CARDINAL;
                        power: ADDRESS);
VAR i: CARDINAL;
    re, im: LONGREAL;
BEGIN
  i := 0;
  WHILE i < n DO
    re := Get(data, 2 * i);
    im := Get(data, 2 * i + 1);
    Put(power, i, re * re + im * im);
    INC(i)
  END
END PowerSpectrum;

(* ── Normalized power spectrum ─────────────────────── *)
(* power[i] = (re[i]^2 + im[i]^2) / n.
   Dividing by n (not n^2) gives the one-sided energy-per-bin
   scaling used by pyAudioAnalysis for feature extraction. *)

PROCEDURE NormalizedPowerSpectrum(data: ADDRESS; n: CARDINAL;
                                  power: ADDRESS);
VAR i: CARDINAL;
    re, im, scale: LONGREAL;
BEGIN
  scale := 1.0 / LFLOAT(n);
  i := 0;
  WHILE i < n DO
    re := Get(data, 2 * i);
    im := Get(data, 2 * i + 1);
    Put(power, i, (re * re + im * im) * scale);
    INC(i)
  END
END NormalizedPowerSpectrum;

(* ── Real to complex packing ──────────────────────── *)

PROCEDURE RealToComplex(realIn: ADDRESS; n: CARDINAL;
                        complexOut: ADDRESS);
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE i < n DO
    Put(complexOut, 2 * i, Get(realIn, i));
    Put(complexOut, 2 * i + 1, 0.0);
    INC(i)
  END
END RealToComplex;

END FFT.
