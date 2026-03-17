IMPLEMENTATION MODULE LDA;

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;

TYPE
  LRPtr = POINTER TO LONGREAL;
  CardPtr = POINTER TO CARDINAL;

PROCEDURE Elem(base: ADDRESS; index: CARDINAL): LRPtr;
VAR
  addr: LONGCARD;
BEGIN
  addr := LONGCARD(base) + LONGCARD(index) * LONGCARD(TSIZE(LONGREAL));
  RETURN LRPtr(addr)
END Elem;

PROCEDURE GetVal(base: ADDRESS; index: CARDINAL): LONGREAL;
VAR
  ptr: LRPtr;
BEGIN
  ptr := Elem(base, index);
  RETURN ptr^
END GetVal;

PROCEDURE SetVal(base: ADDRESS; index: CARDINAL; val: LONGREAL);
VAR
  ptr: LRPtr;
BEGIN
  ptr := Elem(base, index);
  ptr^ := val
END SetVal;

PROCEDURE GetLabel(base: ADDRESS; index: CARDINAL): CARDINAL;
VAR
  addr: LONGCARD;
  ptr: CardPtr;
BEGIN
  addr := LONGCARD(base) + LONGCARD(index) * LONGCARD(TSIZE(CARDINAL));
  ptr := CardPtr(addr);
  RETURN ptr^
END GetLabel;

PROCEDURE Init(VAR l: LDAState; nComponents, nFeatures: CARDINAL);
BEGIN
  l.numComponents := nComponents;
  l.numFeatures := nFeatures;
  l.projection := NIL;
  l.mean := NIL;
  l.fitted := FALSE
END Init;

PROCEDURE Fit(VAR l: LDAState;
              data: ADDRESS;
              labels: ADDRESS;
              numSamples, numFeatures, numClasses: CARDINAL);
VAR
  i, j, k, c, iter, comp: CARDINAL;
  nf, nc, maxComp: CARDINAL;
  sum, norm, val, dot: LONGREAL;
  classMeans: ADDRESS;
  classCounts: ADDRESS;
  sw: ADDRESS;
  sb: ADDRESS;
  mat: ADDRESS;
  vec: ADDRESS;
  newVec: ADDRESS;
  diff: ADDRESS;
  classMeansSize, classCountsSize: CARDINAL;
  swSize, sbSize, matSize, vecSize, diffSize: CARDINAL;
  projSize, meanSize: CARDINAL;
  label: CARDINAL;
  countVal: LONGREAL;
  countPtr: LRPtr;
BEGIN
  nf := numFeatures;
  l.numFeatures := nf;

  (* Limit components to min(numClasses-1, numFeatures) *)
  maxComp := numClasses - 1;
  IF nf < maxComp THEN
    maxComp := nf
  END;
  IF l.numComponents > maxComp THEN
    l.numComponents := maxComp
  END;
  nc := l.numComponents;

  (* Allocate global mean *)
  meanSize := nf * TSIZE(LONGREAL);
  ALLOCATE(l.mean, meanSize);

  (* Compute global mean *)
  FOR j := 0 TO nf - 1 DO
    sum := 0.0;
    FOR i := 0 TO numSamples - 1 DO
      sum := sum + GetVal(data, i * nf + j)
    END;
    SetVal(l.mean, j, sum / LFLOAT(numSamples))
  END;

  (* Allocate class means: numClasses x nf *)
  classMeansSize := numClasses * nf * TSIZE(LONGREAL);
  ALLOCATE(classMeans, classMeansSize);

  (* Allocate class counts as LONGREALs for easy division *)
  classCountsSize := numClasses * TSIZE(LONGREAL);
  ALLOCATE(classCounts, classCountsSize);

  (* Initialize class means and counts to zero *)
  FOR c := 0 TO numClasses - 1 DO
    SetVal(classCounts, c, 0.0);
    FOR j := 0 TO nf - 1 DO
      SetVal(classMeans, c * nf + j, 0.0)
    END
  END;

  (* Accumulate class sums *)
  FOR i := 0 TO numSamples - 1 DO
    label := GetLabel(labels, i);
    SetVal(classCounts, label, GetVal(classCounts, label) + 1.0);
    FOR j := 0 TO nf - 1 DO
      val := GetVal(classMeans, label * nf + j) + GetVal(data, i * nf + j);
      SetVal(classMeans, label * nf + j, val)
    END
  END;

  (* Divide by counts to get means *)
  FOR c := 0 TO numClasses - 1 DO
    countVal := GetVal(classCounts, c);
    IF countVal > 0.5 THEN
      FOR j := 0 TO nf - 1 DO
        SetVal(classMeans, c * nf + j, GetVal(classMeans, c * nf + j) / countVal)
      END
    END
  END;

  (* Allocate within-class scatter Sw: nf x nf *)
  swSize := nf * nf * TSIZE(LONGREAL);
  ALLOCATE(sw, swSize);
  FOR i := 0 TO nf * nf - 1 DO
    SetVal(sw, i, 0.0)
  END;

  (* Compute Sw = sum over samples of (x - mean_c)(x - mean_c)^T *)
  FOR i := 0 TO numSamples - 1 DO
    label := GetLabel(labels, i);
    FOR j := 0 TO nf - 1 DO
      FOR k := 0 TO nf - 1 DO
        val := GetVal(sw, j * nf + k)
              + (GetVal(data, i * nf + j) - GetVal(classMeans, label * nf + j))
              * (GetVal(data, i * nf + k) - GetVal(classMeans, label * nf + k));
        SetVal(sw, j * nf + k, val)
      END
    END
  END;

  (* Allocate between-class scatter Sb: nf x nf *)
  sbSize := nf * nf * TSIZE(LONGREAL);
  ALLOCATE(sb, sbSize);
  FOR i := 0 TO nf * nf - 1 DO
    SetVal(sb, i, 0.0)
  END;

  (* Allocate diff vector *)
  diffSize := nf * TSIZE(LONGREAL);
  ALLOCATE(diff, diffSize);

  (* Compute Sb = sum over classes of n_c * (mean_c - mean)(mean_c - mean)^T *)
  FOR c := 0 TO numClasses - 1 DO
    countVal := GetVal(classCounts, c);
    FOR j := 0 TO nf - 1 DO
      SetVal(diff, j, GetVal(classMeans, c * nf + j) - GetVal(l.mean, j))
    END;
    FOR j := 0 TO nf - 1 DO
      FOR k := 0 TO nf - 1 DO
        val := GetVal(sb, j * nf + k)
              + countVal * GetVal(diff, j) * GetVal(diff, k);
        SetVal(sb, j * nf + k, val)
      END
    END
  END;

  (* We need to solve Sw^{-1} * Sb eigenproblem.
     Instead of inverting Sw, we add regularization and use power iteration
     on Sw^{-1} * Sb by solving Sw * y = Sb * v at each step.
     For simplicity, we regularize Sw and invert it directly for small matrices. *)

  (* Add regularization to Sw diagonal *)
  FOR i := 0 TO nf - 1 DO
    val := GetVal(sw, i * nf + i);
    SetVal(sw, i * nf + i, val + 1.0E-6)
  END;

  (* Compute Sw^{-1} by Gauss-Jordan elimination *)
  (* We build an augmented matrix [Sw | I] and row-reduce *)
  (* swInv stored in-place: we use mat as nf x 2*nf *)
  matSize := nf * 2 * nf * TSIZE(LONGREAL);
  ALLOCATE(mat, matSize);

  (* Fill augmented matrix *)
  FOR i := 0 TO nf - 1 DO
    FOR j := 0 TO nf - 1 DO
      SetVal(mat, i * 2 * nf + j, GetVal(sw, i * nf + j));
      IF i = j THEN
        SetVal(mat, i * 2 * nf + nf + j, 1.0)
      ELSE
        SetVal(mat, i * 2 * nf + nf + j, 0.0)
      END
    END
  END;

  (* Gauss-Jordan with partial pivoting *)
  FOR i := 0 TO nf - 1 DO
    (* Find pivot *)
    norm := 0.0;
    k := i;
    FOR j := i TO nf - 1 DO
      val := GetVal(mat, j * 2 * nf + i);
      IF val < 0.0 THEN
        val := -val
      END;
      IF val > norm THEN
        norm := val;
        k := j
      END
    END;

    (* Swap rows i and k *)
    IF k # i THEN
      FOR j := 0 TO 2 * nf - 1 DO
        val := GetVal(mat, i * 2 * nf + j);
        SetVal(mat, i * 2 * nf + j, GetVal(mat, k * 2 * nf + j));
        SetVal(mat, k * 2 * nf + j, val)
      END
    END;

    (* Scale pivot row *)
    val := GetVal(mat, i * 2 * nf + i);
    FOR j := 0 TO 2 * nf - 1 DO
      SetVal(mat, i * 2 * nf + j, GetVal(mat, i * 2 * nf + j) / val)
    END;

    (* Eliminate column *)
    FOR k := 0 TO nf - 1 DO
      IF k # i THEN
        val := GetVal(mat, k * 2 * nf + i);
        FOR j := 0 TO 2 * nf - 1 DO
          dot := GetVal(mat, k * 2 * nf + j) - val * GetVal(mat, i * 2 * nf + j);
          SetVal(mat, k * 2 * nf + j, dot)
        END
      END
    END
  END;

  (* Now mat right half is Sw^{-1}. Compute M = Sw^{-1} * Sb and store in sw *)
  FOR i := 0 TO nf - 1 DO
    FOR j := 0 TO nf - 1 DO
      sum := 0.0;
      FOR k := 0 TO nf - 1 DO
        sum := sum + GetVal(mat, i * 2 * nf + nf + k) * GetVal(sb, k * nf + j)
      END;
      SetVal(sw, i * nf + j, sum)
    END
  END;

  (* Now sw holds M = Sw^{-1} * Sb. Do power iteration + deflation. *)
  projSize := nc * nf * TSIZE(LONGREAL);
  ALLOCATE(l.projection, projSize);

  vecSize := nf * TSIZE(LONGREAL);
  ALLOCATE(vec, vecSize);
  ALLOCATE(newVec, vecSize);

  FOR comp := 0 TO nc - 1 DO
    (* Initialize vector *)
    norm := 1.0 / LFLOAT(sqrt(FLOAT(LFLOAT(nf))));
    FOR i := 0 TO nf - 1 DO
      SetVal(vec, i, norm + LFLOAT(i) * 0.01)
    END;

    (* Normalize *)
    sum := 0.0;
    FOR i := 0 TO nf - 1 DO
      val := GetVal(vec, i);
      sum := sum + val * val
    END;
    norm := LFLOAT(sqrt(FLOAT(sum)));
    FOR i := 0 TO nf - 1 DO
      SetVal(vec, i, GetVal(vec, i) / norm)
    END;

    (* Power iteration: 100 steps *)
    FOR iter := 1 TO 100 DO
      FOR i := 0 TO nf - 1 DO
        sum := 0.0;
        FOR j := 0 TO nf - 1 DO
          sum := sum + GetVal(sw, i * nf + j) * GetVal(vec, j)
        END;
        SetVal(newVec, i, sum)
      END;

      sum := 0.0;
      FOR i := 0 TO nf - 1 DO
        val := GetVal(newVec, i);
        sum := sum + val * val
      END;
      norm := LFLOAT(sqrt(FLOAT(sum)));
      IF norm > 1.0E-15 THEN
        FOR i := 0 TO nf - 1 DO
          SetVal(vec, i, GetVal(newVec, i) / norm)
        END
      END
    END;

    (* Store projection vector *)
    FOR i := 0 TO nf - 1 DO
      SetVal(l.projection, comp * nf + i, GetVal(vec, i))
    END;

    (* Deflate: M = M - eigenvalue * v * v^T *)
    FOR i := 0 TO nf - 1 DO
      FOR j := 0 TO nf - 1 DO
        val := GetVal(sw, i * nf + j);
        dot := norm * GetVal(vec, i) * GetVal(vec, j);
        SetVal(sw, i * nf + j, val - dot)
      END
    END
  END;

  DEALLOCATE(vec, vecSize);
  DEALLOCATE(newVec, vecSize);
  DEALLOCATE(diff, diffSize);
  DEALLOCATE(mat, matSize);
  DEALLOCATE(sb, sbSize);
  DEALLOCATE(sw, swSize);
  DEALLOCATE(classCounts, classCountsSize);
  DEALLOCATE(classMeans, classMeansSize);

  l.fitted := TRUE
END Fit;

PROCEDURE Transform(VAR l: LDAState;
                    data: ADDRESS;
                    numSamples: CARDINAL;
                    output: ADDRESS);
VAR
  i, j, k: CARDINAL;
  nf, nc: CARDINAL;
  sum, centered: LONGREAL;
BEGIN
  nf := l.numFeatures;
  nc := l.numComponents;

  FOR i := 0 TO numSamples - 1 DO
    FOR k := 0 TO nc - 1 DO
      sum := 0.0;
      FOR j := 0 TO nf - 1 DO
        centered := GetVal(data, i * nf + j) - GetVal(l.mean, j);
        sum := sum + centered * GetVal(l.projection, k * nf + j)
      END;
      SetVal(output, i * nc + k, sum)
    END
  END
END Transform;

PROCEDURE FitTransform(VAR l: LDAState;
                       data: ADDRESS;
                       labels: ADDRESS;
                       numSamples, numFeatures, numClasses: CARDINAL;
                       output: ADDRESS);
BEGIN
  Fit(l, data, labels, numSamples, numFeatures, numClasses);
  Transform(l, data, numSamples, output)
END FitTransform;

PROCEDURE Free(VAR l: LDAState);
VAR
  projSize, meanSize: CARDINAL;
BEGIN
  IF l.projection # NIL THEN
    projSize := l.numComponents * l.numFeatures * TSIZE(LONGREAL);
    DEALLOCATE(l.projection, projSize);
    l.projection := NIL
  END;
  IF l.mean # NIL THEN
    meanSize := l.numFeatures * TSIZE(LONGREAL);
    DEALLOCATE(l.mean, meanSize);
    l.mean := NIL
  END;
  l.fitted := FALSE
END Free;

END LDA.
