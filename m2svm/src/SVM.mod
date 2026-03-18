IMPLEMENTATION MODULE SVM;

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt, exp;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;
  BytePtr = POINTER TO CHAR;

CONST
  MaxIter = 1000;
  Tol     = 1.0D-3;
  Eps     = 1.0D-12;

(* ── Pointer arithmetic helpers ──────────────────────── *)

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(INTEGER)))
END ElemI;

(* ── Memory helpers ──────────────────────────────────── *)

PROCEDURE CopyMem(src, dst: ADDRESS; nBytes: CARDINAL);
VAR i: CARDINAL; s, d: BytePtr;
BEGIN
  FOR i := 0 TO nBytes - 1 DO
    s := BytePtr(LONGCARD(src) + LONGCARD(i));
    d := BytePtr(LONGCARD(dst) + LONGCARD(i));
    d^ := s^
  END
END CopyMem;

PROCEDURE ZeroMem(dst: ADDRESS; nBytes: CARDINAL);
VAR i: CARDINAL; d: BytePtr;
BEGIN
  FOR i := 0 TO nBytes - 1 DO
    d := BytePtr(LONGCARD(dst) + LONGCARD(i));
    d^ := CHR(0)
  END
END ZeroMem;

(* ── LCG pseudo-random number generator ─────────────── *)

VAR
  lcgState: LONGCARD;

PROCEDURE LcgSeed(s: LONGCARD);
BEGIN
  lcgState := s
END LcgSeed;

PROCEDURE LcgNext(): LONGCARD;
BEGIN
  lcgState := lcgState * 6364136223846793005 + 1442695040888963407;
  RETURN lcgState
END LcgNext;

PROCEDURE RandIndex(n: CARDINAL; exclude: CARDINAL): CARDINAL;
VAR j: CARDINAL;
BEGIN
  IF n <= 1 THEN RETURN 0 END;
  REPEAT
    j := CARDINAL(LcgNext() MOD LONGCARD(n))
  UNTIL j # exclude;
  RETURN j
END RandIndex;

(* ── Kernel functions ────────────────────────────────── *)

PROCEDURE DotProduct(a, b: ADDRESS; n: CARDINAL): LONGREAL;
VAR i: CARDINAL; s: LONGREAL; pa, pb: RealPtr;
BEGIN
  s := 0.0;
  FOR i := 0 TO n - 1 DO
    pa := ElemR(a, i);
    pb := ElemR(b, i);
    s := s + pa^ * pb^
  END;
  RETURN s
END DotProduct;

PROCEDURE SqDist(a, b: ADDRESS; n: CARDINAL): LONGREAL;
VAR i: CARDINAL; s, diff: LONGREAL; pa, pb: RealPtr;
BEGIN
  s := 0.0;
  FOR i := 0 TO n - 1 DO
    pa := ElemR(a, i);
    pb := ElemR(b, i);
    diff := pa^ - pb^;
    s := s + diff * diff
  END;
  RETURN s
END SqDist;

PROCEDURE Kernel(VAR m: SVMModel; a, b: ADDRESS): LONGREAL;
VAR d: LONGREAL;
BEGIN
  IF m.kernel = Linear THEN
    RETURN DotProduct(a, b, m.numFeatures)
  ELSE
    (* RBF *)
    d := SqDist(a, b, m.numFeatures);
    RETURN LFLOAT(exp(FLOAT(-m.gamma * d)))
  END
END Kernel;

(* ── Row access ──────────────────────────────────────── *)

PROCEDURE RowAddr(base: ADDRESS; row, nCols: CARDINAL): ADDRESS;
BEGIN
  RETURN ADDRESS(LONGCARD(base) + LONGCARD(row * nCols * TSIZE(LONGREAL)))
END RowAddr;

(* ── Decision function f(x) ─────────────────────────── *)

PROCEDURE Decision(VAR m: SVMModel; sample: ADDRESS): LONGREAL;
VAR i: CARDINAL; s, ai, yi: LONGREAL; pa, pl: RealPtr; xi: ADDRESS;
BEGIN
  s := 0.0;
  FOR i := 0 TO m.numTrain - 1 DO
    pa := ElemR(m.alphas, i);
    ai := pa^;
    IF ai > Eps THEN
      pl := ElemR(m.trainLabels, i);
      yi := pl^;
      xi := RowAddr(m.trainData, i, m.numFeatures);
      s := s + ai * yi * Kernel(m, xi, sample)
    END
  END;
  RETURN s + m.bias
END Decision;

(* ── Public procedures ───────────────────────────────── *)

PROCEDURE Init(VAR m: SVMModel; nFeatures: CARDINAL;
               C: LONGREAL; kern: KernelType; gamma: LONGREAL);
BEGIN
  m.alphas := NIL;
  m.trainData := NIL;
  m.trainLabels := NIL;
  m.bias := 0.0;
  m.numTrain := 0;
  m.numFeatures := nFeatures;
  m.C := C;
  m.kernel := kern;
  m.gamma := gamma;
  m.trained := FALSE
END Init;

PROCEDURE Train(VAR m: SVMModel; data: ADDRESS; labels: ADDRESS;
                numSamples, numFeatures: CARDINAL);
VAR
  iter, numChanged: CARDINAL;
  i, j: CARDINAL;
  ei, ej: LONGREAL;
  yi, yj: LONGREAL;
  aiOld, ajOld, aiNew, ajNew: LONGREAL;
  lo, hi, eta: LONGREAL;
  kii, kjj, kij: LONGREAL;
  b1, b2: LONGREAL;
  dataSize, labelSize, alphaSize: CARDINAL;
  pli, plj, pai, paj: RealPtr;
  xi, xj: ADDRESS;
  converged: BOOLEAN;
BEGIN
  m.numTrain := numSamples;
  m.numFeatures := numFeatures;

  (* Copy training data *)
  dataSize := numSamples * numFeatures * TSIZE(LONGREAL);
  ALLOCATE(m.trainData, dataSize);
  CopyMem(data, m.trainData, dataSize);

  (* Copy labels *)
  labelSize := numSamples * TSIZE(LONGREAL);
  ALLOCATE(m.trainLabels, labelSize);
  CopyMem(labels, m.trainLabels, labelSize);

  (* Allocate and zero alphas *)
  alphaSize := numSamples * TSIZE(LONGREAL);
  ALLOCATE(m.alphas, alphaSize);
  ZeroMem(m.alphas, alphaSize);

  m.bias := 0.0;
  converged := FALSE;

  LcgSeed(42);

  (* Simplified SMO *)
  iter := 0;
  WHILE (iter < MaxIter) AND (NOT converged) DO
    INC(iter);
    numChanged := 0;
    FOR i := 0 TO numSamples - 1 DO
      pli := ElemR(m.trainLabels, i);
      yi := pli^;
      xi := RowAddr(m.trainData, i, numFeatures);
      ei := Decision(m, xi) - yi;

      pai := ElemR(m.alphas, i);
      aiOld := pai^;

      IF ((yi * ei < -Tol) AND (aiOld < m.C)) OR
         ((yi * ei > Tol) AND (aiOld > 0.0)) THEN

        j := RandIndex(numSamples, i);
        plj := ElemR(m.trainLabels, j);
        yj := plj^;
        xj := RowAddr(m.trainData, j, numFeatures);
        ej := Decision(m, xj) - yj;

        paj := ElemR(m.alphas, j);
        ajOld := paj^;

        (* Compute bounds L, H *)
        IF yi # yj THEN
          lo := ajOld - aiOld;
          IF lo < 0.0 THEN lo := 0.0 END;
          hi := m.C + ajOld - aiOld;
          IF hi > m.C THEN hi := m.C END
        ELSE
          lo := aiOld + ajOld - m.C;
          IF lo < 0.0 THEN lo := 0.0 END;
          hi := aiOld + ajOld;
          IF hi > m.C THEN hi := m.C END
        END;

        IF (hi - lo) < Eps THEN
          (* L == H, skip *)
        ELSE
          kii := Kernel(m, xi, xi);
          kjj := Kernel(m, xj, xj);
          kij := Kernel(m, xi, xj);
          eta := 2.0 * kij - kii - kjj;

          IF eta >= 0.0 THEN
            (* skip *)
          ELSE
            (* Update alpha_j *)
            ajNew := ajOld - yj * (ei - ej) / eta;
            (* Clip *)
            IF ajNew > hi THEN ajNew := hi END;
            IF ajNew < lo THEN ajNew := lo END;

            (* Update alpha_i *)
            aiNew := aiOld + yi * yj * (ajOld - ajNew);

            (* Update bias *)
            b1 := m.bias - ei
                  - yi * (aiNew - aiOld) * kii
                  - yj * (ajNew - ajOld) * kij;
            b2 := m.bias - ej
                  - yi * (aiNew - aiOld) * kij
                  - yj * (ajNew - ajOld) * kjj;

            IF (aiNew > 0.0) AND (aiNew < m.C) THEN
              m.bias := b1
            ELSIF (ajNew > 0.0) AND (ajNew < m.C) THEN
              m.bias := b2
            ELSE
              m.bias := (b1 + b2) / 2.0
            END;

            (* Store new alphas *)
            pai := ElemR(m.alphas, i);
            pai^ := aiNew;
            paj := ElemR(m.alphas, j);
            paj^ := ajNew;

            INC(numChanged)
          END
        END
      END
    END;
    IF numChanged = 0 THEN
      converged := TRUE
    END
  END;

  m.trained := TRUE
END Train;

PROCEDURE Predict(VAR m: SVMModel; sample: ADDRESS): LONGREAL;
BEGIN
  RETURN Decision(m, sample)
END Predict;

PROCEDURE Free(VAR m: SVMModel);
BEGIN
  IF m.alphas # NIL THEN
    DEALLOCATE(m.alphas, m.numTrain * TSIZE(LONGREAL));
    m.alphas := NIL
  END;
  IF m.trainData # NIL THEN
    DEALLOCATE(m.trainData, m.numTrain * m.numFeatures * TSIZE(LONGREAL));
    m.trainData := NIL
  END;
  IF m.trainLabels # NIL THEN
    DEALLOCATE(m.trainLabels, m.numTrain * TSIZE(LONGREAL));
    m.trainLabels := NIL
  END;
  m.numTrain := 0;
  m.trained := FALSE
END Free;

(* ── Multi-class (one-vs-rest) ───────────────────────── *)

PROCEDURE InitMulti(VAR m: MultiSVM; nClasses, nFeatures: CARDINAL;
                    C: LONGREAL; kern: KernelType; gamma: LONGREAL);
VAR c: CARDINAL;
BEGIN
  m.numClasses := nClasses;
  m.numFeatures := nFeatures;
  FOR c := 0 TO nClasses - 1 DO
    Init(m.models[c], nFeatures, C, kern, gamma)
  END
END InitMulti;

PROCEDURE TrainMulti(VAR m: MultiSVM; data: ADDRESS; labels: ADDRESS;
                     numSamples, numFeatures: CARDINAL);
VAR
  c, i: CARDINAL;
  binLabels: ADDRESS;
  labSize: CARDINAL;
  pl: IntPtr;
  pb: RealPtr;
  classIdx: INTEGER;
BEGIN
  m.numFeatures := numFeatures;
  labSize := numSamples * TSIZE(LONGREAL);

  FOR c := 0 TO m.numClasses - 1 DO
    ALLOCATE(binLabels, labSize);

    (* Create +1/-1 labels for class c *)
    FOR i := 0 TO numSamples - 1 DO
      pl := ElemI(labels, i);
      classIdx := pl^;
      pb := ElemR(binLabels, i);
      IF CARDINAL(classIdx) = c THEN
        pb^ := 1.0
      ELSE
        pb^ := -1.0
      END
    END;

    Train(m.models[c], data, binLabels, numSamples, numFeatures);

    DEALLOCATE(binLabels, labSize)
  END
END TrainMulti;

PROCEDURE PredictMulti(VAR m: MultiSVM; sample: ADDRESS): INTEGER;
VAR
  c: CARDINAL;
  best: INTEGER;
  bestScore, score: LONGREAL;
BEGIN
  best := 0;
  bestScore := Predict(m.models[0], sample);
  FOR c := 1 TO m.numClasses - 1 DO
    score := Predict(m.models[c], sample);
    IF score > bestScore THEN
      bestScore := score;
      best := INTEGER(c)
    END
  END;
  RETURN best
END PredictMulti;

PROCEDURE PredictMultiProba(VAR m: MultiSVM; sample: ADDRESS;
                            VAR scores: ARRAY OF LONGREAL): INTEGER;
VAR
  c: CARDINAL;
  best: INTEGER;
  bestScore, score: LONGREAL;
BEGIN
  best := 0;
  bestScore := Predict(m.models[0], sample);
  scores[0] := bestScore;
  FOR c := 1 TO m.numClasses - 1 DO
    score := Predict(m.models[c], sample);
    scores[c] := score;
    IF score > bestScore THEN
      bestScore := score;
      best := INTEGER(c)
    END
  END;
  RETURN best
END PredictMultiProba;

PROCEDURE FreeMulti(VAR m: MultiSVM);
VAR c: CARDINAL;
BEGIN
  FOR c := 0 TO m.numClasses - 1 DO
    Free(m.models[c])
  END
END FreeMulti;

END SVM.
