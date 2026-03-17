IMPLEMENTATION MODULE Classify;

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM Strings IMPORT Length, Assign, Concat;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, Extract, FreeFeatures;
IMPORT MidFeats;
IMPORT KNN;
FROM Sys IMPORT m2sys_list_dir;

CONST
  WinSize    = 0.050;  (* 50ms short-term window *)
  WinStep    = 0.025;  (* 25ms step *)
  MidWinSec  = 1.0;    (* 1s mid-term window *)
  MidStepSec = 1.0;    (* 1s mid-term step *)
  MaxFilesPerDir = 200;
  MaxTotalFiles  = 1000;
  DirBufSize     = 32768;

TYPE
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;
  CharPtr = POINTER TO CHAR;
  AddrPtr = POINTER TO ADDRESS;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END ElemR;

PROCEDURE ElemI(base: ADDRESS; i: CARDINAL): IntPtr;
BEGIN
  RETURN IntPtr(LONGCARD(base) + LONGCARD(i * TSIZE(INTEGER)))
END ElemI;

(* ── Feature vector extraction ─────────────────────── *)

PROCEDURE ExtractFileVector(path: ARRAY OF CHAR;
                            VAR vec: ARRAY OF LONGREAL;
                            VAR ok: BOOLEAN);
VAR
  signal, shortFeats, midFeats: ADDRESS;
  numSamples, sampleRate: CARDINAL;
  numShortFrames, numMidFrames: CARDINAL;
  midWinFrames, midStepFrames: CARDINAL;
  outCols, f, m: CARDINAL;
  sum: LONGREAL;
  p: RealPtr;
  featsOk: BOOLEAN;
BEGIN
  ok := FALSE;

  ReadAudio(path, signal, numSamples, sampleRate, featsOk);
  IF NOT featsOk THEN RETURN END;

  Extract(signal, numSamples, sampleRate,
          WinSize, WinStep,
          shortFeats, numShortFrames, featsOk);

  IF NOT featsOk THEN
    FreeSignal(signal);
    RETURN
  END;

  midWinFrames := TRUNC(MidWinSec / WinStep);
  midStepFrames := TRUNC(MidStepSec / WinStep);

  MidFeats.Extract(shortFeats, numShortFrames, NumFeatures,
                   midWinFrames, midStepFrames,
                   midFeats, numMidFrames, featsOk);

  IF (NOT featsOk) OR (numMidFrames = 0) THEN
    FreeFeatures(shortFeats);
    FreeSignal(signal);
    RETURN
  END;

  outCols := 2 * NumFeatures;

  (* Average the mean columns across all mid-term frames *)
  FOR f := 0 TO NumFeatures - 1 DO
    sum := 0.0;
    FOR m := 0 TO numMidFrames - 1 DO
      p := ElemR(midFeats, m * outCols + f);
      sum := sum + p^
    END;
    vec[f] := sum / LFLOAT(numMidFrames)
  END;

  MidFeats.FreeMidFeatures(midFeats);
  FreeFeatures(shortFeats);
  FreeSignal(signal);
  ok := TRUE
END ExtractFileVector;

(* ── Directory scanning helpers ────────────────────── *)

(* Check if filename ends with ".wav" or ".WAV" *)
PROCEDURE IsWavFile(name: ARRAY OF CHAR): BOOLEAN;
VAR len: INTEGER;
BEGIN
  len := Length(name);
  IF len < 4 THEN RETURN FALSE END;
  IF (name[len - 4] = '.') AND
     ((name[len - 3] = 'w') OR (name[len - 3] = 'W')) AND
     ((name[len - 2] = 'a') OR (name[len - 2] = 'A')) AND
     ((name[len - 1] = 'v') OR (name[len - 1] = 'V')) THEN
    RETURN TRUE
  END;
  RETURN FALSE
END IsWavFile;

(* Build full path: dir/filename *)
PROCEDURE JoinPath(dir, name: ARRAY OF CHAR;
                   VAR out: ARRAY OF CHAR);
VAR dirLen: INTEGER; slash: ARRAY [0..1] OF CHAR;
BEGIN
  Assign(dir, out);
  dirLen := Length(out);
  IF (dirLen > 0) AND (out[dirLen - 1] # '/') THEN
    slash[0] := '/'; slash[1] := 0C;
    Concat(out, slash, out)
  END;
  Concat(out, name, out)
END JoinPath;

(* ── Training from directories ─────────────────────── *)

PROCEDURE TrainFromDirs(VAR m: Model;
                        dirs: ADDRESS;
                        numDirs: CARDINAL;
                        kNeighbors: CARDINAL;
                        VAR ok: BOOLEAN);
VAR
  d, i, j, fileCount, totalFiles, pos, nameStart: CARDINAL;
  dirPath: ARRAY [0..255] OF CHAR;
  filePath: ARRAY [0..511] OF CHAR;
  fileName: ARRAY [0..255] OF CHAR;
  dirBuf: ARRAY [0..32767] OF CHAR;
  listLen: INTEGER;
  vec: ARRAY [0..33] OF LONGREAL;
  vecOk: BOOLEAN;
  pDir: RealPtr;  (* actually an ADDRESS pointer *)
  dirAddr: ADDRESS;

  (* Accumulate all feature vectors *)
  allData: ADDRESS;
  allLabels: ADDRESS;
  pLabel: IntPtr;
  pFeat: RealPtr;

  ch: CHAR;
  bp: CharPtr;
BEGIN
  ok := FALSE;

  (* First pass: count total WAV files across all dirs *)
  totalFiles := 0;
  FOR d := 0 TO numDirs - 1 DO
    (* Dereference dirs[d] to get the ADDRESS of the path string *)
    dirAddr := AddrPtr(LONGCARD(dirs) + LONGCARD(d * TSIZE(ADDRESS)))^;

    (* Copy path from the char array at dirAddr *)
    FOR i := 0 TO 255 DO
      bp := CharPtr(LONGCARD(dirAddr) + LONGCARD(i));
      dirPath[i] := bp^;
      IF bp^ = 0C THEN i := 255 END
    END;

    listLen := m2sys_list_dir(ADR(dirPath), ADR(dirBuf), DirBufSize);
    IF listLen > 0 THEN
      pos := 0;
      WHILE pos < CARDINAL(listLen) DO
        nameStart := pos;
        WHILE (pos < CARDINAL(listLen)) AND (dirBuf[pos] # 12C) DO
          INC(pos)
        END;
        IF pos > nameStart THEN
          FOR i := 0 TO pos - nameStart - 1 DO
            fileName[i] := dirBuf[nameStart + i]
          END;
          fileName[pos - nameStart] := 0C;
          IF IsWavFile(fileName) THEN
            INC(totalFiles)
          END
        END;
        INC(pos)
      END
    END
  END;

  IF totalFiles = 0 THEN
    WriteString("  No WAV files found"); WriteLn;
    RETURN
  END;

  WriteString("  Found "); WriteCard(totalFiles, 0);
  WriteString(" WAV files across "); WriteCard(numDirs, 0);
  WriteString(" classes"); WriteLn;

  (* Allocate feature matrix and label array *)
  ALLOCATE(allData, totalFiles * VectorLen * TSIZE(LONGREAL));
  ALLOCATE(allLabels, totalFiles * TSIZE(INTEGER));

  (* Second pass: extract features *)
  fileCount := 0;
  FOR d := 0 TO numDirs - 1 DO
    dirAddr := AddrPtr(LONGCARD(dirs) + LONGCARD(d * TSIZE(ADDRESS)))^;
    FOR i := 0 TO 255 DO
      bp := CharPtr(LONGCARD(dirAddr) + LONGCARD(i));
      dirPath[i] := bp^;
      IF bp^ = 0C THEN i := 255 END
    END;

    WriteString("  Class "); WriteCard(d, 0);
    WriteString(": "); WriteString(dirPath); WriteLn;

    listLen := m2sys_list_dir(ADR(dirPath), ADR(dirBuf), DirBufSize);
    IF listLen > 0 THEN
      pos := 0;
      WHILE pos < CARDINAL(listLen) DO
        nameStart := pos;
        WHILE (pos < CARDINAL(listLen)) AND (dirBuf[pos] # 12C) DO
          INC(pos)
        END;
        FOR i := 0 TO pos - nameStart - 1 DO
          fileName[i] := dirBuf[nameStart + i]
        END;
        fileName[pos - nameStart] := 0C;

        IF IsWavFile(fileName) THEN
          JoinPath(dirPath, fileName, filePath);
          WriteString("    "); WriteString(fileName);

          ExtractFileVector(filePath, vec, vecOk);

          IF vecOk THEN
            (* Copy vector into allData *)
            FOR j := 0 TO VectorLen - 1 DO
              pFeat := ElemR(allData, fileCount * VectorLen + j);
              pFeat^ := vec[j]
            END;
            pLabel := ElemI(allLabels, fileCount);
            pLabel^ := INTEGER(d);
            INC(fileCount);
            WriteString(" OK"); WriteLn
          ELSE
            WriteString(" SKIP (extraction failed)"); WriteLn
          END
        END;
        INC(pos)
      END
    END
  END;

  IF fileCount = 0 THEN
    WriteString("  No features extracted"); WriteLn;
    DEALLOCATE(allData, 0);
    DEALLOCATE(allLabels, 0);
    RETURN
  END;

  WriteString("  Training k-NN (k="); WriteCard(kNeighbors, 0);
  WriteString(", "); WriteCard(fileCount, 0);
  WriteString(" samples, "); WriteCard(VectorLen, 0);
  WriteString(" features)..."); WriteLn;

  (* Train the model *)
  KNN.Init(m, kNeighbors, VectorLen, numDirs, KNN.Euclidean, TRUE);
  KNN.Train(m, allData, allLabels, fileCount, TRUE);

  (* Note: KNN.Train stores references to allData/allLabels.
     We do NOT free them here — they stay alive in the model.
     They'll be freed when FreeModel is called, or when SaveModel
     serializes them and the caller frees manually. *)

  ok := TRUE
END TrainFromDirs;

(* ── Prediction ────────────────────────────────────── *)

PROCEDURE PredictFile(VAR m: Model;
                      path: ARRAY OF CHAR;
                      VAR proba: ARRAY OF LONGREAL): INTEGER;
VAR
  vec: ARRAY [0..33] OF LONGREAL;
  vecOk: BOOLEAN;
BEGIN
  ExtractFileVector(path, vec, vecOk);
  IF NOT vecOk THEN RETURN -1 END;
  RETURN KNN.PredictProba(m, ADR(vec), proba)
END PredictFile;

END Classify.
