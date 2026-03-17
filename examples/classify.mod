MODULE ClassifyTool;
(* Audio classification CLI tool.

   Train:   classify train <dir1> <dir2> [...] -o model.bin
   Predict: classify predict model.bin file.wav

   Each training directory is a class (class 0 = first dir, etc.).

   Example:
     classify train music/ speech/ -o mymodel.bin
     classify predict mymodel.bin unknown.wav *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Args IMPORT ArgCount, GetArg;
FROM KNN IMPORT Model;
IMPORT KNN;
FROM Classify IMPORT VectorLen, TrainFromDirs, PredictFile;

CONST
  MaxDirs = 16;
  DefaultK = 5;

TYPE
  PathBuf = ARRAY [0..255] OF CHAR;

VAR
  mode: PathBuf;
  modelPath: PathBuf;
  dirPaths: ARRAY [0..15] OF PathBuf;
  dirAddrs: ARRAY [0..15] OF ADDRESS;
  numDirs, i, argIdx: CARDINAL;
  m: Model;
  ok: BOOLEAN;
  predPath: PathBuf;
  proba: ARRAY [0..31] OF LONGREAL;
  pred: INTEGER;
  bestProba: LONGREAL;

PROCEDURE PrintUsage;
BEGIN
  WriteString("Usage:"); WriteLn;
  WriteString("  classify train <dir1> <dir2> [...] -o <model.bin>"); WriteLn;
  WriteString("  classify predict <model.bin> <file.wav>"); WriteLn;
  WriteLn;
  WriteString("Training directories are class labels (0, 1, 2, ...)."); WriteLn;
  WriteString("Each directory should contain WAV files for that class."); WriteLn
END PrintUsage;

PROCEDURE PrintReal4(x: LONGREAL);
VAR intP: LONGINT; fracP: CARDINAL; neg: BOOLEAN; ax: LONGREAL;
BEGIN
  neg := x < 0.0;
  IF neg THEN ax := -x ELSE ax := x END;
  intP := VAL(LONGINT, TRUNC(ax));
  fracP := TRUNC((ax - LFLOAT(intP)) * 10000.0);
  IF neg THEN WriteString("-") END;
  WriteInt(INTEGER(intP), 0);
  WriteString(".");
  IF fracP < 1000 THEN WriteString("0") END;
  IF fracP < 100 THEN WriteString("0") END;
  IF fracP < 10 THEN WriteString("0") END;
  WriteCard(fracP, 0)
END PrintReal4;

BEGIN
  IF ArgCount() < 3 THEN
    PrintUsage;
    HALT
  END;

  GetArg(1, mode);

  IF (mode[0] = 't') AND (mode[1] = 'r') AND (mode[2] = 'a') AND
     (mode[3] = 'i') AND (mode[4] = 'n') AND (mode[5] = 0C) THEN

    (* Parse: classify train dir1 dir2 ... -o model.bin *)
    numDirs := 0;
    argIdx := 2;
    modelPath[0] := 0C;

    WHILE argIdx < CARDINAL(ArgCount()) DO
      GetArg(INTEGER(argIdx), predPath);  (* temp buffer for peeking *)
      IF (predPath[0] = '-') AND (predPath[1] = 'o') AND
         (predPath[2] = 0C) THEN
        (* Next arg is model path *)
        INC(argIdx);
        IF argIdx < CARDINAL(ArgCount()) THEN
          GetArg(INTEGER(argIdx), modelPath)
        END;
        INC(argIdx)
      ELSE
        IF numDirs < MaxDirs THEN
          GetArg(INTEGER(argIdx), dirPaths[numDirs]);
          dirAddrs[numDirs] := ADR(dirPaths[numDirs]);
          INC(numDirs)
        END;
        INC(argIdx)
      END
    END;

    IF numDirs < 2 THEN
      WriteString("Error: need at least 2 class directories"); WriteLn;
      HALT
    END;

    IF modelPath[0] = 0C THEN
      WriteString("Error: specify output model with -o <path>"); WriteLn;
      HALT
    END;

    WriteString("Training audio classifier"); WriteLn;
    WriteString("  Classes: "); WriteCard(numDirs, 0); WriteLn;
    WriteString("  k: "); WriteCard(DefaultK, 0); WriteLn;
    WriteLn;

    TrainFromDirs(m, ADR(dirAddrs), numDirs, DefaultK, ok);

    IF NOT ok THEN
      WriteString("Training failed"); WriteLn;
      HALT
    END;

    WriteLn;
    WriteString("Saving model to: "); WriteString(modelPath); WriteLn;
    KNN.SaveModel(m, modelPath, ok);
    IF ok THEN
      WriteString("Model saved successfully"); WriteLn
    ELSE
      WriteString("Error saving model"); WriteLn
    END

  ELSIF (mode[0] = 'p') AND (mode[1] = 'r') AND (mode[2] = 'e') AND
        (mode[3] = 'd') AND (mode[4] = 'i') AND (mode[5] = 'c') AND
        (mode[6] = 't') AND (mode[7] = 0C) THEN

    (* Parse: classify predict model.bin file.wav *)
    IF ArgCount() < 4 THEN
      PrintUsage;
      HALT
    END;

    GetArg(2, modelPath);
    GetArg(3, predPath);

    WriteString("Loading model: "); WriteString(modelPath); WriteLn;
    KNN.LoadModel(m, modelPath, ok);
    IF NOT ok THEN
      WriteString("Error: could not load model"); WriteLn;
      HALT
    END;

    WriteString("  k="); WriteCard(m.k, 0);
    WriteString(", "); WriteCard(m.numTrain, 0);
    WriteString(" training samples, ");
    WriteCard(m.numClasses, 0); WriteString(" classes"); WriteLn;
    WriteLn;

    WriteString("Classifying: "); WriteString(predPath); WriteLn;
    pred := PredictFile(m, predPath, proba);

    IF pred < 0 THEN
      WriteString("Error: could not extract features from file"); WriteLn;
      KNN.FreeModel(m);
      HALT
    END;

    WriteLn;
    WriteString("Predicted class: "); WriteInt(pred, 0); WriteLn;
    WriteString("Probabilities:"); WriteLn;
    FOR i := 0 TO m.numClasses - 1 DO
      WriteString("  Class "); WriteCard(i, 0);
      WriteString(": "); PrintReal4(proba[i]);
      IF INTEGER(i) = pred THEN WriteString("  <--") END;
      WriteLn
    END;

    KNN.FreeModel(m)

  ELSE
    PrintUsage
  END
END ClassifyTool.
