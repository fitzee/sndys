IMPLEMENTATION MODULE PCA;

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;

TYPE
  LRPtr = POINTER TO LONGREAL;

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

PROCEDURE Init(VAR p: PCAState; nComponents, nFeatures: CARDINAL);
BEGIN
  p.numComponents := nComponents;
  p.numFeatures := nFeatures;
  p.components := NIL;
  p.mean := NIL;
  p.fitted := FALSE
END Init;

PROCEDURE Fit(VAR p: PCAState;
              data: ADDRESS;
              numSamples, numFeatures: CARDINAL);
VAR
  i, j, k, iter: CARDINAL;
  nf, nc: CARDINAL;
  sum, norm, dot, val, tmp: LONGREAL;
  cov: ADDRESS;
  vec: ADDRESS;
  newVec: ADDRESS;
  covSize, compSize, meanSize, vecSize: CARDINAL;
BEGIN
  nf := numFeatures;
  nc := p.numComponents;
  p.numFeatures := nf;

  (* Allocate mean *)
  meanSize := nf * TSIZE(LONGREAL);
  ALLOCATE(p.mean, meanSize);

  (* Compute mean *)
  FOR j := 0 TO nf - 1 DO
    sum := 0.0;
    FOR i := 0 TO numSamples - 1 DO
      sum := sum + GetVal(data, i * nf + j)
    END;
    SetVal(p.mean, j, sum / LFLOAT(numSamples))
  END;

  (* Allocate covariance matrix nf x nf *)
  covSize := nf * nf * TSIZE(LONGREAL);
  ALLOCATE(cov, covSize);

  (* Compute covariance matrix *)
  FOR i := 0 TO nf - 1 DO
    FOR j := 0 TO nf - 1 DO
      sum := 0.0;
      FOR k := 0 TO numSamples - 1 DO
        sum := sum + (GetVal(data, k * nf + i) - GetVal(p.mean, i))
                   * (GetVal(data, k * nf + j) - GetVal(p.mean, j))
      END;
      SetVal(cov, i * nf + j, sum / LFLOAT(numSamples))
    END
  END;

  (* Allocate components *)
  compSize := nc * nf * TSIZE(LONGREAL);
  ALLOCATE(p.components, compSize);

  (* Allocate temporary vectors *)
  vecSize := nf * TSIZE(LONGREAL);
  ALLOCATE(vec, vecSize);
  ALLOCATE(newVec, vecSize);

  (* Power iteration for each component *)
  FOR k := 0 TO nc - 1 DO
    (* Initialize vector with 1/sqrt(nf) *)
    norm := 1.0 / LFLOAT(sqrt(FLOAT(LFLOAT(nf))));
    FOR i := 0 TO nf - 1 DO
      SetVal(vec, i, norm + LFLOAT(i) * 0.01)
    END;

    (* Normalize initial vector *)
    sum := 0.0;
    FOR i := 0 TO nf - 1 DO
      val := GetVal(vec, i);
      sum := sum + val * val
    END;
    norm := LFLOAT(sqrt(FLOAT(sum)));
    FOR i := 0 TO nf - 1 DO
      SetVal(vec, i, GetVal(vec, i) / norm)
    END;

    (* Power iteration: 100 iterations *)
    FOR iter := 1 TO 100 DO
      (* newVec = cov * vec *)
      FOR i := 0 TO nf - 1 DO
        sum := 0.0;
        FOR j := 0 TO nf - 1 DO
          sum := sum + GetVal(cov, i * nf + j) * GetVal(vec, j)
        END;
        SetVal(newVec, i, sum)
      END;

      (* Normalize *)
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

    (* Store component *)
    FOR i := 0 TO nf - 1 DO
      SetVal(p.components, k * nf + i, GetVal(vec, i))
    END;

    (* Deflate covariance matrix: cov = cov - eigenvalue * v * v^T *)
    (* eigenvalue = v^T * cov * v, but we can use norm from last iteration *)
    FOR i := 0 TO nf - 1 DO
      FOR j := 0 TO nf - 1 DO
        val := GetVal(cov, i * nf + j);
        dot := norm * GetVal(vec, i) * GetVal(vec, j);
        SetVal(cov, i * nf + j, val - dot)
      END
    END
  END;

  DEALLOCATE(vec, vecSize);
  DEALLOCATE(newVec, vecSize);
  DEALLOCATE(cov, covSize);

  p.fitted := TRUE
END Fit;

PROCEDURE Transform(VAR p: PCAState;
                    data: ADDRESS;
                    numSamples: CARDINAL;
                    output: ADDRESS);
VAR
  i, j, k: CARDINAL;
  nf, nc: CARDINAL;
  sum, centered: LONGREAL;
BEGIN
  nf := p.numFeatures;
  nc := p.numComponents;

  FOR i := 0 TO numSamples - 1 DO
    FOR k := 0 TO nc - 1 DO
      sum := 0.0;
      FOR j := 0 TO nf - 1 DO
        centered := GetVal(data, i * nf + j) - GetVal(p.mean, j);
        sum := sum + centered * GetVal(p.components, k * nf + j)
      END;
      SetVal(output, i * nc + k, sum)
    END
  END
END Transform;

PROCEDURE FitTransform(VAR p: PCAState;
                       data: ADDRESS;
                       numSamples, numFeatures: CARDINAL;
                       output: ADDRESS);
BEGIN
  Fit(p, data, numSamples, numFeatures);
  Transform(p, data, numSamples, output)
END FitTransform;

PROCEDURE Free(VAR p: PCAState);
VAR
  compSize, meanSize: CARDINAL;
BEGIN
  IF p.components # NIL THEN
    compSize := p.numComponents * p.numFeatures * TSIZE(LONGREAL);
    DEALLOCATE(p.components, compSize);
    p.components := NIL
  END;
  IF p.mean # NIL THEN
    meanSize := p.numFeatures * TSIZE(LONGREAL);
    DEALLOCATE(p.mean, meanSize);
    p.mean := NIL
  END;
  p.fitted := FALSE
END Free;

END PCA.
