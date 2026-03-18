IMPLEMENTATION MODULE KNN;

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;
FROM Scaler IMPORT Init, Fit, Transform, FitTransform;
FROM Sys IMPORT m2sys_fopen, m2sys_fclose,
                m2sys_fread_bytes, m2sys_fwrite_bytes;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

CONST
  Eps = 1.0D-10;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(INTEGER)))
END ElemI;

(* ── Distance functions ──────────────────────────────── *)

PROCEDURE EuclideanDist(a, b: ADDRESS; n: CARDINAL): LONGREAL;
VAR i: CARDINAL; d, diff: LONGREAL; pa, pb: RealPtr;
BEGIN
  d := 0.0;
  FOR i := 0 TO n - 1 DO
    pa := ElemR(a, i);
    pb := ElemR(b, i);
    diff := pa^ - pb^;
    d := d + diff * diff
  END;
  RETURN LFLOAT(sqrt(FLOAT(d)))
END EuclideanDist;

PROCEDURE ManhattanDist(a, b: ADDRESS; n: CARDINAL): LONGREAL;
VAR i: CARDINAL; d, diff: LONGREAL; pa, pb: RealPtr;
BEGIN
  d := 0.0;
  FOR i := 0 TO n - 1 DO
    pa := ElemR(a, i);
    pb := ElemR(b, i);
    diff := pa^ - pb^;
    IF diff < 0.0 THEN diff := -diff END;
    d := d + diff
  END;
  RETURN d
END ManhattanDist;

PROCEDURE CosineDist(a, b: ADDRESS; n: CARDINAL): LONGREAL;
VAR i: CARDINAL; dot, normA, normB, sim: LONGREAL; pa, pb: RealPtr;
BEGIN
  dot := 0.0;
  normA := 0.0;
  normB := 0.0;
  FOR i := 0 TO n - 1 DO
    pa := ElemR(a, i);
    pb := ElemR(b, i);
    dot := dot + pa^ * pb^;
    normA := normA + pa^ * pa^;
    normB := normB + pb^ * pb^
  END;
  normA := LFLOAT(sqrt(FLOAT(normA)));
  normB := LFLOAT(sqrt(FLOAT(normB)));
  IF (normA < Eps) OR (normB < Eps) THEN
    RETURN 1.0
  END;
  sim := dot / (normA * normB);
  IF sim > 1.0 THEN sim := 1.0 END;
  IF sim < -1.0 THEN sim := -1.0 END;
  RETURN 1.0 - sim
END CosineDist;

PROCEDURE Distance(VAR m: Model; a, b: ADDRESS): LONGREAL;
BEGIN
  CASE m.metric OF
    Euclidean: RETURN EuclideanDist(a, b, m.numFeatures) |
    Manhattan: RETURN ManhattanDist(a, b, m.numFeatures) |
    Cosine:    RETURN CosineDist(a, b, m.numFeatures)
  END;
  RETURN 0.0
END Distance;

(* ── Public API ──────────────────────────────────────── *)

PROCEDURE Init(VAR m: Model; k, numFeatures, numClasses: CARDINAL;
               metric: DistMetric; weighted: BOOLEAN);
BEGIN
  m.trainData := NIL;
  m.trainLabels := NIL;
  m.numTrain := 0;
  IF numFeatures > 128 THEN m.numFeatures := 128
  ELSE m.numFeatures := numFeatures END;
  IF numClasses > MaxClasses THEN m.numClasses := MaxClasses
  ELSE m.numClasses := numClasses END;
  IF k > MaxK THEN m.k := MaxK ELSE m.k := k END;
  IF m.k = 0 THEN m.k := 1 END;
  m.metric := metric;
  m.weighted := weighted;
  m.hasScaler := FALSE;
  Scaler.Init(m.scaler, m.numFeatures)
END Init;

PROCEDURE Train(VAR m: Model;
                data: ADDRESS; labels: ADDRESS;
                numSamples: CARDINAL; scale: BOOLEAN);
BEGIN
  m.trainData := data;
  m.trainLabels := labels;
  m.numTrain := numSamples;

  IF scale AND (numSamples > 0) THEN
    FitTransform(m.scaler, data, numSamples, m.numFeatures);
    m.hasScaler := TRUE
  ELSE
    m.hasScaler := FALSE
  END
END Train;

PROCEDURE PredictProba(VAR m: Model; sample: ADDRESS;
                       VAR proba: ARRAY OF LONGREAL): INTEGER;
VAR
  i, j, c: CARDINAL;
  dist, weight, totalWeight, maxVote: LONGREAL;
  trainRow: ADDRESS;
  label, bestLabel: INTEGER;
  pLabel: IntPtr;

  (* Parallel arrays for k-nearest neighbors *)
  kDist:  ARRAY [0..50] OF LONGREAL;
  kLabel: ARRAY [0..50] OF INTEGER;
  kCount: CARDINAL;
  maxDist: LONGREAL;
  maxIdx: CARDINAL;

  (* Scaled sample buffer *)
  scaledBuf: ARRAY [0..127] OF LONGREAL;
  sampleAddr: ADDRESS;
  pSrc: RealPtr;

  (* Vote accumulation *)
  votes: ARRAY [0..31] OF LONGREAL;
BEGIN
  IF (m.numTrain = 0) OR (m.trainData = NIL) OR (m.numClasses = 0) THEN
    FOR c := 0 TO HIGH(proba) DO proba[c] := 0.0 END;
    RETURN 0
  END;

  (* Scale sample if model has scaler *)
  IF m.hasScaler THEN
    FOR i := 0 TO m.numFeatures - 1 DO
      pSrc := ElemR(sample, i);
      IF m.scaler.stds[i] > 0.0 THEN
        scaledBuf[i] := (pSrc^ - m.scaler.means[i]) / m.scaler.stds[i]
      ELSE
        scaledBuf[i] := 0.0
      END
    END;
    sampleAddr := ADR(scaledBuf)
  ELSE
    sampleAddr := sample
  END;

  (* Initialize k-nearest with first k training samples *)
  kCount := 0;
  FOR i := 0 TO m.numTrain - 1 DO
    trainRow := ADDRESS(LONGCARD(m.trainData)
                + LONGCARD(i) * LONGCARD(m.numFeatures) * LONGCARD(TSIZE(LONGREAL)));
    dist := Distance(m, sampleAddr, trainRow);

    IF kCount < m.k THEN
      kDist[kCount] := dist;
      pLabel := ElemI(m.trainLabels, i);
      kLabel[kCount] := pLabel^;
      INC(kCount)
    ELSE
      (* Find the farthest among current k neighbors *)
      maxDist := kDist[0];
      maxIdx := 0;
      FOR j := 1 TO kCount - 1 DO
        IF kDist[j] > maxDist THEN
          maxDist := kDist[j];
          maxIdx := j
        END
      END;
      (* Replace if this sample is closer *)
      IF dist < maxDist THEN
        kDist[maxIdx] := dist;
        pLabel := ElemI(m.trainLabels, i);
        kLabel[maxIdx] := pLabel^
      END
    END
  END;

  (* Vote among k neighbors *)
  FOR c := 0 TO m.numClasses - 1 DO
    votes[c] := 0.0
  END;

  FOR i := 0 TO kCount - 1 DO
    label := kLabel[i];
    IF (label >= 0) AND (CARDINAL(label) < m.numClasses) THEN
      IF m.weighted THEN
        weight := 1.0 / (kDist[i] + Eps)
      ELSE
        weight := 1.0
      END;
      votes[label] := votes[label] + weight
    END
  END;

  (* Normalize votes to probabilities *)
  totalWeight := 0.0;
  FOR c := 0 TO m.numClasses - 1 DO
    totalWeight := totalWeight + votes[c]
  END;

  bestLabel := 0;
  maxVote := 0.0;
  FOR c := 0 TO m.numClasses - 1 DO
    IF totalWeight > 0.0 THEN
      proba[c] := votes[c] / totalWeight
    ELSE
      proba[c] := 0.0
    END;
    IF votes[c] > maxVote THEN
      maxVote := votes[c];
      bestLabel := INTEGER(c)
    END
  END;

  RETURN bestLabel
END PredictProba;

PROCEDURE Predict(VAR m: Model; sample: ADDRESS): INTEGER;
VAR proba: ARRAY [0..31] OF LONGREAL;
BEGIN
  RETURN PredictProba(m, sample, proba)
END Predict;

PROCEDURE PredictBatch(VAR m: Model;
                       data: ADDRESS; numSamples: CARDINAL;
                       predictions: ADDRESS);
VAR
  i: CARDINAL;
  row: ADDRESS;
  pPred: IntPtr;
BEGIN
  IF (numSamples = 0) OR (m.numTrain = 0) OR (m.trainData = NIL) THEN RETURN END;
  FOR i := 0 TO numSamples - 1 DO
    row := ADDRESS(LONGCARD(data)
           + LONGCARD(i) * LONGCARD(m.numFeatures) * LONGCARD(TSIZE(LONGREAL)));
    pPred := ElemI(predictions, i);
    pPred^ := Predict(m, row)
  END
END PredictBatch;

(* ── Model I/O ──────────────────────────────────────── *)
(* Binary format:
   4 bytes: magic "KNN1"
   4 bytes: numTrain (CARDINAL)
   4 bytes: numFeatures (CARDINAL)
   4 bytes: numClasses (CARDINAL)
   4 bytes: k (CARDINAL)
   4 bytes: metric (CARDINAL: 0=Euclidean, 1=Manhattan, 2=Cosine)
   4 bytes: weighted (CARDINAL: 0 or 1)
   4 bytes: hasScaler (CARDINAL: 0 or 1)
   if hasScaler:
     numFeatures * 8 bytes: means (LONGREALs)
     numFeatures * 8 bytes: stds (LONGREALs)
   numTrain * numFeatures * 8 bytes: training data (LONGREALs)
   numTrain * 4 bytes: training labels (INTEGERs) *)

PROCEDURE WriteCard(f: INTEGER; val: CARDINAL): BOOLEAN;
VAR buf: ARRAY [0..3] OF CHAR; n: INTEGER;
BEGIN
  buf[0] := CHR(val MOD 256);
  buf[1] := CHR((val DIV 256) MOD 256);
  buf[2] := CHR((val DIV 65536) MOD 256);
  buf[3] := CHR((val DIV 16777216) MOD 256);
  n := m2sys_fwrite_bytes(f, ADR(buf), 4);
  RETURN n = 4
END WriteCard;

PROCEDURE ReadCard(f: INTEGER; VAR val: CARDINAL): BOOLEAN;
VAR buf: ARRAY [0..3] OF CHAR; n: INTEGER;
BEGIN
  n := m2sys_fread_bytes(f, ADR(buf), 4);
  IF n # 4 THEN RETURN FALSE END;
  val := ORD(buf[0])
       + ORD(buf[1]) * 256
       + ORD(buf[2]) * 65536
       + ORD(buf[3]) * 16777216;
  RETURN TRUE
END ReadCard;

PROCEDURE SaveModel(VAR m: Model; path: ARRAY OF CHAR;
                    VAR ok: BOOLEAN);
VAR
  f, n, dummy: INTEGER;
  modeWb: ARRAY [0..2] OF CHAR;
  magic: ARRAY [0..3] OF CHAR;
  dataBytes, labelBytes, scalerBytes: CARDINAL;
  metricVal, weightedVal, scalerVal: CARDINAL;
BEGIN
  ok := FALSE;
  modeWb[0] := 'w'; modeWb[1] := 'b'; modeWb[2] := 0C;
  f := m2sys_fopen(ADR(path), ADR(modeWb));
  IF f < 0 THEN RETURN END;

  (* Magic *)
  magic[0] := 'K'; magic[1] := 'N'; magic[2] := 'N'; magic[3] := '1';
  n := m2sys_fwrite_bytes(f, ADR(magic), 4);
  IF n # 4 THEN dummy := m2sys_fclose(f); RETURN END;

  (* Header *)
  IF NOT WriteCard(f, m.numTrain) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT WriteCard(f, m.numFeatures) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT WriteCard(f, m.numClasses) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT WriteCard(f, m.k) THEN dummy := m2sys_fclose(f); RETURN END;

  CASE m.metric OF
    Euclidean: metricVal := 0 |
    Manhattan: metricVal := 1 |
    Cosine:    metricVal := 2
  END;
  IF NOT WriteCard(f, metricVal) THEN dummy := m2sys_fclose(f); RETURN END;

  IF m.weighted THEN weightedVal := 1 ELSE weightedVal := 0 END;
  IF NOT WriteCard(f, weightedVal) THEN dummy := m2sys_fclose(f); RETURN END;

  IF m.hasScaler THEN scalerVal := 1 ELSE scalerVal := 0 END;
  IF NOT WriteCard(f, scalerVal) THEN dummy := m2sys_fclose(f); RETURN END;

  (* Scaler state *)
  IF m.hasScaler THEN
    scalerBytes := m.numFeatures * TSIZE(LONGREAL);
    n := m2sys_fwrite_bytes(f, ADR(m.scaler.means), INTEGER(scalerBytes));
    IF n # INTEGER(scalerBytes) THEN dummy := m2sys_fclose(f); RETURN END;
    n := m2sys_fwrite_bytes(f, ADR(m.scaler.stds), INTEGER(scalerBytes));
    IF n # INTEGER(scalerBytes) THEN dummy := m2sys_fclose(f); RETURN END
  END;

  (* Training data *)
  dataBytes := m.numTrain * m.numFeatures * TSIZE(LONGREAL);
  n := m2sys_fwrite_bytes(f, m.trainData, INTEGER(dataBytes));
  IF n # INTEGER(dataBytes) THEN dummy := m2sys_fclose(f); RETURN END;

  (* Labels *)
  labelBytes := m.numTrain * TSIZE(INTEGER);
  n := m2sys_fwrite_bytes(f, m.trainLabels, INTEGER(labelBytes));
  IF n # INTEGER(labelBytes) THEN dummy := m2sys_fclose(f); RETURN END;

  dummy := m2sys_fclose(f);
  ok := TRUE
END SaveModel;

PROCEDURE LoadModel(VAR m: Model; path: ARRAY OF CHAR;
                    VAR ok: BOOLEAN);
VAR
  f, n, dummy: INTEGER;
  modeRb: ARRAY [0..2] OF CHAR;
  magic: ARRAY [0..3] OF CHAR;
  dataBytes, labelBytes, scalerBytes: CARDINAL;
  metricVal, weightedVal, scalerVal: CARDINAL;
BEGIN
  ok := FALSE;
  modeRb[0] := 'r'; modeRb[1] := 'b'; modeRb[2] := 0C;
  f := m2sys_fopen(ADR(path), ADR(modeRb));
  IF f < 0 THEN RETURN END;

  (* Magic *)
  n := m2sys_fread_bytes(f, ADR(magic), 4);
  IF (n # 4) OR (magic[0] # 'K') OR (magic[1] # 'N') OR
     (magic[2] # 'N') OR (magic[3] # '1') THEN
    dummy := m2sys_fclose(f);
    RETURN
  END;

  (* Header *)
  (* Free any existing owned buffers before loading *)
  FreeModel(m);

  IF NOT ReadCard(f, m.numTrain) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT ReadCard(f, m.numFeatures) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT ReadCard(f, m.numClasses) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT ReadCard(f, m.k) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT ReadCard(f, metricVal) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT ReadCard(f, weightedVal) THEN dummy := m2sys_fclose(f); RETURN END;
  IF NOT ReadCard(f, scalerVal) THEN dummy := m2sys_fclose(f); RETURN END;

  (* Clamp loaded dimensions to local array limits *)
  IF m.numFeatures > 128 THEN m.numFeatures := 128 END;
  IF m.numClasses > MaxClasses THEN m.numClasses := MaxClasses END;
  IF m.k > MaxK THEN m.k := MaxK END;
  IF m.k = 0 THEN m.k := 1 END;

  CASE metricVal OF
    0: m.metric := Euclidean |
    1: m.metric := Manhattan |
    2: m.metric := Cosine
  ELSE
    m.metric := Euclidean
  END;
  m.weighted := weightedVal = 1;
  m.hasScaler := scalerVal = 1;

  (* Scaler state *)
  IF m.hasScaler THEN
    Scaler.Init(m.scaler, m.numFeatures);
    scalerBytes := m.numFeatures * TSIZE(LONGREAL);
    n := m2sys_fread_bytes(f, ADR(m.scaler.means), INTEGER(scalerBytes));
    IF n # INTEGER(scalerBytes) THEN dummy := m2sys_fclose(f); RETURN END;
    n := m2sys_fread_bytes(f, ADR(m.scaler.stds), INTEGER(scalerBytes));
    IF n # INTEGER(scalerBytes) THEN dummy := m2sys_fclose(f); RETURN END;
    m.scaler.fitted := TRUE
  END;

  (* Allocate and read training data *)
  dataBytes := m.numTrain * m.numFeatures * TSIZE(LONGREAL);
  ALLOCATE(m.trainData, dataBytes);
  n := m2sys_fread_bytes(f, m.trainData, INTEGER(dataBytes));
  IF n # INTEGER(dataBytes) THEN
    DEALLOCATE(m.trainData, dataBytes);
    m.trainData := NIL;
    dummy := m2sys_fclose(f);
    RETURN
  END;

  (* Allocate and read labels *)
  labelBytes := m.numTrain * TSIZE(INTEGER);
  ALLOCATE(m.trainLabels, labelBytes);
  n := m2sys_fread_bytes(f, m.trainLabels, INTEGER(labelBytes));
  IF n # INTEGER(labelBytes) THEN
    DEALLOCATE(m.trainData, dataBytes);
    DEALLOCATE(m.trainLabels, labelBytes);
    m.trainData := NIL;
    m.trainLabels := NIL;
    dummy := m2sys_fclose(f);
    RETURN
  END;

  dummy := m2sys_fclose(f);
  ok := TRUE
END LoadModel;

PROCEDURE FreeModel(VAR m: Model);
BEGIN
  IF m.trainData # NIL THEN
    DEALLOCATE(m.trainData, m.numTrain * m.numFeatures * TSIZE(LONGREAL));
    m.trainData := NIL
  END;
  IF m.trainLabels # NIL THEN
    DEALLOCATE(m.trainLabels, m.numTrain * TSIZE(INTEGER));
    m.trainLabels := NIL
  END;
  m.numTrain := 0
END FreeModel;

END KNN.
