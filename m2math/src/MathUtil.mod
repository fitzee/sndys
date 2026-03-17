IMPLEMENTATION MODULE MathUtil;
(* Extended math utilities for DSP and audio analysis.
   Uses MathLib (sqrt, exp, ln) internally, converting between
   REAL (MathLib) and LONGREAL (our API) as needed. *)

FROM MathLib IMPORT sqrt, exp, ln;

CONST
  Ln2 = 0.693147180559945309417D0;

PROCEDURE Log10(x: LONGREAL): LONGREAL;
VAR r: REAL;
BEGIN
  r := ln(VAL(REAL, x));
  RETURN VAL(LONGREAL, r) / Ln10
END Log10;

PROCEDURE Log2(x: LONGREAL): LONGREAL;
VAR r: REAL;
BEGIN
  r := ln(VAL(REAL, x));
  RETURN VAL(LONGREAL, r) / Ln2
END Log2;

PROCEDURE Pow(base, expon: LONGREAL): LONGREAL;
VAR r: REAL;
    lnBase: REAL;
BEGIN
  IF base = 0.0D0 THEN
    IF expon > 0.0D0 THEN
      RETURN 0.0D0
    ELSIF expon = 0.0D0 THEN
      RETURN 1.0D0
    ELSE
      RETURN 0.0D0
    END
  END;
  lnBase := ln(VAL(REAL, base));
  r := exp(VAL(REAL, expon) * lnBase);
  RETURN VAL(LONGREAL, r)
END Pow;

PROCEDURE Floor(x: LONGREAL): LONGINT;
VAR t: LONGINT;
BEGIN
  IF x >= 0.0D0 THEN
    RETURN VAL(LONGINT, TRUNC(x))
  ELSE
    t := VAL(LONGINT, TRUNC(-x));
    IF VAL(LONGREAL, t) = -x THEN
      RETURN -t
    ELSE
      RETURN -t - 1
    END
  END
END Floor;

PROCEDURE Ceil(x: LONGREAL): LONGINT;
VAR t: LONGINT;
BEGIN
  IF x <= 0.0D0 THEN
    RETURN -VAL(LONGINT, TRUNC(-x))
  ELSE
    t := VAL(LONGINT, TRUNC(x));
    IF VAL(LONGREAL, t) = x THEN
      RETURN t
    ELSE
      RETURN t + 1
    END
  END
END Ceil;

PROCEDURE FAbs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0D0 THEN
    RETURN -x
  ELSE
    RETURN x
  END
END FAbs;

PROCEDURE FMod(x, y: LONGREAL): LONGREAL;
VAR q: LONGINT;
BEGIN
  q := VAL(LONGINT, TRUNC(x / y));
  RETURN x - VAL(LONGREAL, q) * y
END FMod;

PROCEDURE Clamp(x, lo, hi: LONGREAL): LONGREAL;
BEGIN
  IF x < lo THEN
    RETURN lo
  ELSIF x > hi THEN
    RETURN hi
  ELSE
    RETURN x
  END
END Clamp;

PROCEDURE Hypot(x, y: LONGREAL): LONGREAL;
VAR r: REAL;
BEGIN
  r := sqrt(VAL(REAL, x * x + y * y));
  RETURN VAL(LONGREAL, r)
END Hypot;

PROCEDURE NextPow2(n: CARDINAL): CARDINAL;
VAR p: CARDINAL;
BEGIN
  IF n = 0 THEN RETURN 1 END;
  p := 1;
  WHILE p < n DO
    p := p * 2
  END;
  RETURN p
END NextPow2;

PROCEDURE IsPow2(n: CARDINAL): BOOLEAN;
VAR p: CARDINAL;
BEGIN
  IF n = 0 THEN RETURN FALSE END;
  p := n;
  WHILE p > 1 DO
    IF p MOD 2 # 0 THEN RETURN FALSE END;
    p := p DIV 2
  END;
  RETURN TRUE
END IsPow2;

END MathUtil.
