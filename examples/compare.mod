MODULE Compare;
(* Compare the audio features of two WAV files using Euclidean distance.
   Extracts mid-term features and computes a similarity score.

   Demonstrates: full pipeline — m2wav, m2audio, m2stats, m2fft, m2dct, m2math

   Usage: compare samples/file_example_WAV_1MG.wav samples/file_example_WAV_5MG.wav *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Args IMPORT ArgCount, GetArg;
FROM MathLib IMPORT sqrt;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, Extract, FreeFeatures;
FROM Stats IMPORT Mean, StdDev;
IMPORT MidFeats;

CONST
  WinSize    = 0.050;
  WinStep    = 0.025;
  MidWinSec  = 1.0;
  MidStepSec = 1.0;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE PrintReal(x: LONGREAL);
VAR
  intPart: LONGINT;
  fracPart: CARDINAL;
  neg: BOOLEAN;
  ax: LONGREAL;
BEGIN
  neg := x < 0.0;
  IF neg THEN ax := -x ELSE ax := x END;
  intPart := VAL(LONGINT, TRUNC(ax));
  fracPart := TRUNC((ax - LFLOAT(intPart)) * 10000.0);
  IF neg THEN WriteString("-") END;
  WriteInt(INTEGER(intPart), 0);
  WriteString(".");
  IF fracPart < 1000 THEN WriteString("0") END;
  IF fracPart < 100 THEN WriteString("0") END;
  IF fracPart < 10 THEN WriteString("0") END;
  WriteCard(fracPart, 0)
END PrintReal;

(* Extract a single feature vector for a file:
   mean of all mid-term means (first half of mid-feat columns).
   Result is a fixed array of NumFeatures LONGREALs. *)
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
BEGIN
  ok := FALSE;

  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN RETURN END;

  Extract(signal, numSamples, sampleRate,
          WinSize, WinStep,
          shortFeats, numShortFrames, ok);

  IF NOT ok THEN
    FreeSignal(signal, numSamples);
    RETURN
  END;

  midWinFrames := TRUNC(MidWinSec / WinStep);
  midStepFrames := TRUNC(MidStepSec / WinStep);

  MidFeats.Extract(shortFeats, numShortFrames, NumFeatures,
                   midWinFrames, midStepFrames,
                   midFeats, numMidFrames, ok);

  IF NOT ok THEN
    FreeFeatures(shortFeats, numShortFrames);
    FreeSignal(signal, numSamples);
    RETURN
  END;

  outCols := 2 * NumFeatures;

  (* Average the mean columns across all mid-term frames *)
  FOR f := 0 TO NumFeatures - 1 DO
    sum := 0.0;
    FOR m := 0 TO numMidFrames - 1 DO
      p := Elem(midFeats, m * outCols + f);
      sum := sum + p^
    END;
    vec[f] := sum / LFLOAT(numMidFrames)
  END;

  MidFeats.FreeMidFeatures(midFeats, numMidFrames, NumFeatures);
  FreeFeatures(shortFeats, numShortFrames);
  FreeSignal(signal, numSamples);
  ok := TRUE
END ExtractFileVector;

VAR
  path1, path2: ARRAY [0..255] OF CHAR;
  vec1, vec2: ARRAY [0..33] OF LONGREAL;
  ok1, ok2: BOOLEAN;
  dist, diff: LONGREAL;
  i: CARDINAL;

BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: compare <file1.wav> <file2.wav>"); WriteLn;
    HALT
  END;

  GetArg(1, path1);
  GetArg(2, path2);

  WriteString("File 1: "); WriteString(path1); WriteLn;
  ExtractFileVector(path1, vec1, ok1);
  IF NOT ok1 THEN
    WriteString("Error reading file 1"); WriteLn;
    HALT
  END;
  WriteString("  -> extracted feature vector"); WriteLn;

  WriteString("File 2: "); WriteString(path2); WriteLn;
  ExtractFileVector(path2, vec2, ok2);
  IF NOT ok2 THEN
    WriteString("Error reading file 2"); WriteLn;
    HALT
  END;
  WriteString("  -> extracted feature vector"); WriteLn;
  WriteLn;

  (* Compute Euclidean distance *)
  dist := 0.0;
  FOR i := 0 TO NumFeatures - 1 DO
    diff := vec1[i] - vec2[i];
    dist := dist + diff * diff
  END;
  dist := LFLOAT(sqrt(FLOAT(dist)));

  WriteString("Euclidean distance: ");
  PrintReal(dist);
  WriteLn;

  IF dist < 1.0 THEN
    WriteString("-> Very similar audio content")
  ELSIF dist < 5.0 THEN
    WriteString("-> Moderately similar")
  ELSIF dist < 20.0 THEN
    WriteString("-> Somewhat different")
  ELSE
    WriteString("-> Very different audio content")
  END;
  WriteLn
END Compare.
