MODULE pca_tests;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM InOut IMPORT WriteString, WriteLn;
FROM PCA IMPORT PCAState, Init, Fit, Transform, FitTransform, Free;
IMPORT LDA;

TYPE
  LRPtr = POINTER TO LONGREAL;
  CardPtr = POINTER TO CARDINAL;

PROCEDURE ElemLR(base: ADDRESS; index: CARDINAL): LRPtr;
VAR
  addr: LONGCARD;
BEGIN
  addr := LONGCARD(base) + LONGCARD(index) * LONGCARD(TSIZE(LONGREAL));
  RETURN LRPtr(addr)
END ElemLR;

PROCEDURE GetVal(base: ADDRESS; index: CARDINAL): LONGREAL;
VAR
  ptr: LRPtr;
BEGIN
  ptr := ElemLR(base, index);
  RETURN ptr^
END GetVal;

PROCEDURE SetVal(base: ADDRESS; index: CARDINAL; val: LONGREAL);
VAR
  ptr: LRPtr;
BEGIN
  ptr := ElemLR(base, index);
  ptr^ := val
END SetVal;

PROCEDURE SetLabel(base: ADDRESS; index: CARDINAL; val: CARDINAL);
VAR
  addr: LONGCARD;
  ptr: CardPtr;
BEGIN
  addr := LONGCARD(base) + LONGCARD(index) * LONGCARD(TSIZE(CARDINAL));
  ptr := CardPtr(addr);
  ptr^ := val
END SetLabel;

PROCEDURE Abs(x: LONGREAL): LONGREAL;
BEGIN
  IF x < 0.0 THEN
    RETURN -x
  ELSE
    RETURN x
  END
END Abs;

PROCEDURE AssertTrue(cond: BOOLEAN; msg: ARRAY OF CHAR);
BEGIN
  IF cond THEN
    WriteString("  PASS: ");
    WriteString(msg);
    WriteLn
  ELSE
    WriteString("  FAIL: ");
    WriteString(msg);
    WriteLn
  END
END AssertTrue;

(* Test 1: PCA reduces 3D data to 2D, preserves variance *)
PROCEDURE TestPCAReduceDim;
VAR
  p: PCAState;
  data: ADDRESS;
  output: ADDRESS;
  dataSize, outSize: CARDINAL;
  i: CARDINAL;
  var2d: LONGREAL;
BEGIN
  WriteString("Test: PCA reduces 3D to 2D, preserves variance");
  WriteLn;

  (* 6 samples x 3 features: data with most variance in first 2 dims *)
  dataSize := 6 * 3 * TSIZE(LONGREAL);
  ALLOCATE(data, dataSize);

  (* Sample data: first two features have large spread, third is near-constant *)
  SetVal(data, 0, 1.0);  SetVal(data, 1, 2.0);  SetVal(data, 2, 0.1);
  SetVal(data, 3, 3.0);  SetVal(data, 4, 4.0);  SetVal(data, 5, 0.2);
  SetVal(data, 6, 5.0);  SetVal(data, 7, 6.0);  SetVal(data, 8, 0.1);
  SetVal(data, 9, 2.0);  SetVal(data, 10, 1.0); SetVal(data, 11, 0.3);
  SetVal(data, 12, 4.0); SetVal(data, 13, 3.0); SetVal(data, 14, 0.2);
  SetVal(data, 15, 6.0); SetVal(data, 16, 5.0); SetVal(data, 17, 0.1);

  outSize := 6 * 2 * TSIZE(LONGREAL);
  ALLOCATE(output, outSize);

  Init(p, 2, 3);
  FitTransform(p, data, 6, 3, output);

  AssertTrue(p.fitted, "PCA state is fitted");

  (* Compute variance of 2D output *)
  var2d := 0.0;
  FOR i := 0 TO 11 DO
    var2d := var2d + GetVal(output, i) * GetVal(output, i)
  END;

  (* Check that 2D output captures non-trivial variance *)
  AssertTrue(var2d > 0.1, "2D output has non-trivial variance");

  (* Verify we got 2 components *)
  AssertTrue(p.numComponents = 2, "numComponents is 2");

  Free(p);
  DEALLOCATE(output, outSize);
  DEALLOCATE(data, dataSize)
END TestPCAReduceDim;

(* Test 2: PCA transform roundtrip — project and reconstruct *)
PROCEDURE TestPCARoundtrip;
VAR
  p: PCAState;
  data: ADDRESS;
  projected: ADDRESS;
  reconstructed: ADDRESS;
  dataSize, projSize, reconSize: CARDINAL;
  i, j, k: CARDINAL;
  nf, nc, ns: CARDINAL;
  sum, err, maxErr: LONGREAL;
BEGIN
  WriteString("Test: PCA roundtrip (project + reconstruct)");
  WriteLn;

  ns := 4;
  nf := 2;
  nc := 2;  (* keep all components for perfect reconstruction *)

  dataSize := ns * nf * TSIZE(LONGREAL);
  ALLOCATE(data, dataSize);

  SetVal(data, 0, 1.0); SetVal(data, 1, 2.0);
  SetVal(data, 2, 3.0); SetVal(data, 3, 4.0);
  SetVal(data, 4, 5.0); SetVal(data, 5, 6.0);
  SetVal(data, 6, 7.0); SetVal(data, 7, 8.0);

  projSize := ns * nc * TSIZE(LONGREAL);
  ALLOCATE(projected, projSize);

  Init(p, nc, nf);
  FitTransform(p, data, ns, nf, projected);

  (* Reconstruct: for each sample, x_recon = mean + sum_k (proj_k * component_k) *)
  reconSize := ns * nf * TSIZE(LONGREAL);
  ALLOCATE(reconstructed, reconSize);

  FOR i := 0 TO ns - 1 DO
    FOR j := 0 TO nf - 1 DO
      sum := GetVal(p.mean, j);
      FOR k := 0 TO nc - 1 DO
        sum := sum + GetVal(projected, i * nc + k)
                   * GetVal(p.components, k * nf + j)
      END;
      SetVal(reconstructed, i * nf + j, sum)
    END
  END;

  (* Check reconstruction error *)
  maxErr := 0.0;
  FOR i := 0 TO ns * nf - 1 DO
    err := Abs(GetVal(data, i) - GetVal(reconstructed, i));
    IF err > maxErr THEN
      maxErr := err
    END
  END;

  AssertTrue(maxErr < 1.0E-6, "Reconstruction error < 1e-6");

  Free(p);
  DEALLOCATE(reconstructed, reconSize);
  DEALLOCATE(projected, projSize);
  DEALLOCATE(data, dataSize)
END TestPCARoundtrip;

(* Test 3: LDA separates 2 classes better than raw features *)
PROCEDURE TestLDASeparation;
VAR
  l: LDA.LDAState;
  data: ADDRESS;
  labels: ADDRESS;
  output: ADDRESS;
  dataSize, labelsSize, outSize: CARDINAL;
  i: CARDINAL;
  meanClass0, meanClass1: LONGREAL;
  separation: LONGREAL;
  count0, count1: CARDINAL;
BEGIN
  WriteString("Test: LDA separates 2 classes");
  WriteLn;

  (* 8 samples, 3 features, 2 classes *)
  (* Class 0: cluster around (1,1,1), Class 1: cluster around (5,5,5) *)
  dataSize := 8 * 3 * TSIZE(LONGREAL);
  ALLOCATE(data, dataSize);
  labelsSize := 8 * TSIZE(CARDINAL);
  ALLOCATE(labels, labelsSize);

  (* Class 0 samples *)
  SetVal(data, 0, 1.0); SetVal(data, 1, 1.2); SetVal(data, 2, 0.9);
  SetLabel(labels, 0, 0);
  SetVal(data, 3, 1.1); SetVal(data, 4, 0.9); SetVal(data, 5, 1.1);
  SetLabel(labels, 1, 0);
  SetVal(data, 6, 0.9); SetVal(data, 7, 1.1); SetVal(data, 8, 1.0);
  SetLabel(labels, 2, 0);
  SetVal(data, 9, 1.2); SetVal(data, 10, 1.0); SetVal(data, 11, 0.8);
  SetLabel(labels, 3, 0);

  (* Class 1 samples *)
  SetVal(data, 12, 5.0); SetVal(data, 13, 5.1); SetVal(data, 14, 4.9);
  SetLabel(labels, 4, 1);
  SetVal(data, 15, 5.2); SetVal(data, 16, 4.8); SetVal(data, 17, 5.1);
  SetLabel(labels, 5, 1);
  SetVal(data, 18, 4.9); SetVal(data, 19, 5.2); SetVal(data, 20, 5.0);
  SetLabel(labels, 6, 1);
  SetVal(data, 21, 5.1); SetVal(data, 22, 5.0); SetVal(data, 23, 4.8);
  SetLabel(labels, 7, 1);

  (* LDA to 1 component *)
  outSize := 8 * 1 * TSIZE(LONGREAL);
  ALLOCATE(output, outSize);

  LDA.Init(l, 1, 3);
  LDA.FitTransform(l, data, labels, 8, 3, 2, output);

  AssertTrue(l.fitted, "LDA state is fitted");

  (* Compute mean projected value per class *)
  meanClass0 := 0.0;
  meanClass1 := 0.0;
  count0 := 0;
  count1 := 0;
  FOR i := 0 TO 7 DO
    IF i < 4 THEN
      meanClass0 := meanClass0 + GetVal(output, i);
      INC(count0)
    ELSE
      meanClass1 := meanClass1 + GetVal(output, i);
      INC(count1)
    END
  END;
  meanClass0 := meanClass0 / LFLOAT(count0);
  meanClass1 := meanClass1 / LFLOAT(count1);

  separation := Abs(meanClass1 - meanClass0);
  AssertTrue(separation > 1.0, "LDA class separation > 1.0");

  LDA.Free(l);
  DEALLOCATE(output, outSize);
  DEALLOCATE(labels, labelsSize);
  DEALLOCATE(data, dataSize)
END TestLDASeparation;

(* Test 4: LDA numComponents = min(numClasses-1, numFeatures) *)
PROCEDURE TestLDAComponentLimit;
VAR
  l: LDA.LDAState;
  data: ADDRESS;
  labels: ADDRESS;
  output: ADDRESS;
  dataSize, labelsSize, outSize: CARDINAL;
BEGIN
  WriteString("Test: LDA limits numComponents to min(numClasses-1, numFeatures)");
  WriteLn;

  (* 6 samples, 5 features, 2 classes => max components = 1 *)
  dataSize := 6 * 5 * TSIZE(LONGREAL);
  ALLOCATE(data, dataSize);
  labelsSize := 6 * TSIZE(CARDINAL);
  ALLOCATE(labels, labelsSize);

  (* Fill with simple data *)
  SetVal(data, 0, 1.0); SetVal(data, 1, 0.0); SetVal(data, 2, 0.0);
  SetVal(data, 3, 0.0); SetVal(data, 4, 0.0);
  SetLabel(labels, 0, 0);

  SetVal(data, 5, 0.0); SetVal(data, 6, 1.0); SetVal(data, 7, 0.0);
  SetVal(data, 8, 0.0); SetVal(data, 9, 0.0);
  SetLabel(labels, 1, 0);

  SetVal(data, 10, 0.0); SetVal(data, 11, 0.0); SetVal(data, 12, 1.0);
  SetVal(data, 13, 0.0); SetVal(data, 14, 0.0);
  SetLabel(labels, 2, 0);

  SetVal(data, 15, 5.0); SetVal(data, 16, 5.0); SetVal(data, 17, 5.0);
  SetVal(data, 18, 5.0); SetVal(data, 19, 5.0);
  SetLabel(labels, 3, 1);

  SetVal(data, 20, 6.0); SetVal(data, 21, 6.0); SetVal(data, 22, 6.0);
  SetVal(data, 23, 6.0); SetVal(data, 24, 6.0);
  SetLabel(labels, 4, 1);

  SetVal(data, 25, 7.0); SetVal(data, 26, 7.0); SetVal(data, 27, 7.0);
  SetVal(data, 28, 7.0); SetVal(data, 29, 7.0);
  SetLabel(labels, 5, 1);

  (* Request 10 components, but should be capped to min(2-1, 5) = 1 *)
  LDA.Init(l, 10, 5);
  outSize := 6 * 1 * TSIZE(LONGREAL);
  ALLOCATE(output, outSize);

  LDA.Fit(l, data, labels, 6, 5, 2);

  AssertTrue(l.numComponents = 1, "numComponents capped to 1 for 2 classes");
  AssertTrue(l.fitted, "LDA fitted with capped components");

  (* Also test: 4 classes, 2 features => max = min(3, 2) = 2 *)
  LDA.Free(l);
  DEALLOCATE(output, outSize);
  DEALLOCATE(labels, labelsSize);
  DEALLOCATE(data, dataSize);

  (* Second sub-test: 2 features, 4 classes => max = min(3, 2) = 2 *)
  dataSize := 8 * 2 * TSIZE(LONGREAL);
  ALLOCATE(data, dataSize);
  labelsSize := 8 * TSIZE(CARDINAL);
  ALLOCATE(labels, labelsSize);

  SetVal(data, 0, 0.0); SetVal(data, 1, 0.0); SetLabel(labels, 0, 0);
  SetVal(data, 2, 0.0); SetVal(data, 3, 0.0); SetLabel(labels, 1, 0);
  SetVal(data, 4, 5.0); SetVal(data, 5, 0.0); SetLabel(labels, 2, 1);
  SetVal(data, 6, 5.0); SetVal(data, 7, 0.0); SetLabel(labels, 3, 1);
  SetVal(data, 8, 0.0); SetVal(data, 9, 5.0); SetLabel(labels, 4, 2);
  SetVal(data, 10, 0.0); SetVal(data, 11, 5.0); SetLabel(labels, 5, 2);
  SetVal(data, 12, 5.0); SetVal(data, 13, 5.0); SetLabel(labels, 6, 3);
  SetVal(data, 14, 5.0); SetVal(data, 15, 5.0); SetLabel(labels, 7, 3);

  LDA.Init(l, 10, 2);
  outSize := 8 * 2 * TSIZE(LONGREAL);
  ALLOCATE(output, outSize);

  LDA.Fit(l, data, labels, 8, 2, 4);

  AssertTrue(l.numComponents = 2, "numComponents capped to 2 for 4 classes, 2 features");

  LDA.Free(l);
  DEALLOCATE(output, outSize);
  DEALLOCATE(labels, labelsSize);
  DEALLOCATE(data, dataSize)
END TestLDAComponentLimit;

BEGIN
  WriteString("=== m2pca Test Suite ===");
  WriteLn;
  WriteLn;

  TestPCAReduceDim;
  WriteLn;
  TestPCARoundtrip;
  WriteLn;
  TestLDASeparation;
  WriteLn;
  TestLDAComponentLimit;

  WriteLn;
  WriteString("=== Tests Complete ===");
  WriteLn
END pca_tests.
