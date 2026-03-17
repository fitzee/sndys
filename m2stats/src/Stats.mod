IMPLEMENTATION MODULE Stats;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM MathLib IMPORT sqrt, ln;

(* Elem -- return pointer to element at index i from base address *)
PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE Mean(data: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  s: LONGREAL;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;
  s := Sum(data, n);
  RETURN s / LFLOAT(n)
END Mean;

PROCEDURE Variance(data: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  m, s, diff: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;
  m := Mean(data, n);
  s := 0.0;
  FOR i := 0 TO n - 1 DO
    p := Elem(data, i);
    diff := p^ - m;
    s := s + diff * diff
  END;
  RETURN s / LFLOAT(n)
END Variance;

PROCEDURE StdDev(data: ADDRESS; n: CARDINAL): LONGREAL;
BEGIN
  RETURN LFLOAT(sqrt(FLOAT(Variance(data, n))))
END StdDev;

PROCEDURE Min(data: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  minVal: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;
  p := Elem(data, 0);
  minVal := p^;
  FOR i := 1 TO n - 1 DO
    p := Elem(data, i);
    IF p^ < minVal THEN
      minVal := p^
    END
  END;
  RETURN minVal
END Min;

PROCEDURE Max(data: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  maxVal: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;
  p := Elem(data, 0);
  maxVal := p^;
  FOR i := 1 TO n - 1 DO
    p := Elem(data, i);
    IF p^ > maxVal THEN
      maxVal := p^
    END
  END;
  RETURN maxVal
END Max;

PROCEDURE ArgMin(data: ADDRESS; n: CARDINAL): CARDINAL;
VAR
  i, idx: CARDINAL;
  minVal: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0 END;
  idx := 0;
  p := Elem(data, 0);
  minVal := p^;
  FOR i := 1 TO n - 1 DO
    p := Elem(data, i);
    IF p^ < minVal THEN
      minVal := p^;
      idx := i
    END
  END;
  RETURN idx
END ArgMin;

PROCEDURE ArgMax(data: ADDRESS; n: CARDINAL): CARDINAL;
VAR
  i, idx: CARDINAL;
  maxVal: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0 END;
  idx := 0;
  p := Elem(data, 0);
  maxVal := p^;
  FOR i := 1 TO n - 1 DO
    p := Elem(data, i);
    IF p^ > maxVal THEN
      maxVal := p^;
      idx := i
    END
  END;
  RETURN idx
END ArgMax;

PROCEDURE Sum(data: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  s: LONGREAL;
  p: RealPtr;
BEGIN
  s := 0.0;
  IF n = 0 THEN RETURN s END;
  FOR i := 0 TO n - 1 DO
    p := Elem(data, i);
    s := s + p^
  END;
  RETURN s
END Sum;

PROCEDURE SumSq(data: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  s: LONGREAL;
  p: RealPtr;
BEGIN
  s := 0.0;
  IF n = 0 THEN RETURN s END;
  FOR i := 0 TO n - 1 DO
    p := Elem(data, i);
    s := s + p^ * p^
  END;
  RETURN s
END SumSq;

PROCEDURE Entropy(data: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  total, h, pi: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN 0.0 END;
  total := Sum(data, n);
  IF total = 0.0 THEN RETURN 0.0 END;
  h := 0.0;
  FOR i := 0 TO n - 1 DO
    p := Elem(data, i);
    pi := p^ / total;
    IF pi > 0.0 THEN
      h := h - pi * LFLOAT(ln(FLOAT(pi)))
    END
  END;
  RETURN h
END Entropy;

PROCEDURE Normalize(data: ADDRESS; n: CARDINAL);
VAR
  i: CARDINAL;
  total: LONGREAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN END;
  total := Sum(data, n);
  IF total = 0.0 THEN RETURN END;
  FOR i := 0 TO n - 1 DO
    p := Elem(data, i);
    p^ := p^ / total
  END
END Normalize;

PROCEDURE ZScore(data: ADDRESS; n: CARDINAL; mean, sd: LONGREAL);
VAR
  i: CARDINAL;
  p: RealPtr;
BEGIN
  IF n = 0 THEN RETURN END;
  IF sd = 0.0 THEN RETURN END;
  FOR i := 0 TO n - 1 DO
    p := Elem(data, i);
    p^ := (p^ - mean) / sd
  END
END ZScore;

PROCEDURE DotProduct(a, b: ADDRESS; n: CARDINAL): LONGREAL;
VAR
  i: CARDINAL;
  s: LONGREAL;
  pa, pb: RealPtr;
BEGIN
  s := 0.0;
  IF n = 0 THEN RETURN s END;
  FOR i := 0 TO n - 1 DO
    pa := Elem(a, i);
    pb := Elem(b, i);
    s := s + pa^ * pb^
  END;
  RETURN s
END DotProduct;

END Stats.
