MODULE MidStats;
(* Compute mid-term feature statistics from a WAV file and print
   a summary of the mean and standard deviation of each feature
   across the entire file.

   This is the representation used for audio classification —
   one feature vector per file.

   Demonstrates: m2wav, m2audio (AudioIO, ShortFeats, MidFeats),
                 m2stats, m2fft, m2dct, m2math

   Usage: midstats samples/file_example_WAV_1MG.wav *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Args IMPORT ArgCount, GetArg;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, Extract, FreeFeatures, FeatureName;
IMPORT MidFeats;

CONST
  WinSize   = 0.050;  (* 50 ms short-term window *)
  WinStep   = 0.025;  (* 25 ms short-term step *)
  MidWinSec = 1.0;    (* 1 second mid-term window *)
  MidStepSec = 0.5;   (* 500 ms mid-term step *)

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

VAR
  path: ARRAY [0..255] OF CHAR;
  signal: ADDRESS;
  numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
  shortFeats, midFeats: ADDRESS;
  numShortFrames, numMidFrames: CARDINAL;
  midWinFrames, midStepFrames: CARDINAL;
  outCols, i: CARDINAL;
  name: ARRAY [0..31] OF CHAR;
  p: RealPtr;

BEGIN
  IF ArgCount() < 2 THEN
    WriteString("Usage: midstats <file.wav>"); WriteLn;
    HALT
  END;

  GetArg(1, path);
  WriteString("File: "); WriteString(path); WriteLn;

  (* Read audio *)
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read audio file"); WriteLn;
    HALT
  END;

  WriteString("  Samples: "); WriteCard(numSamples, 0);
  WriteString("  Rate: "); WriteCard(sampleRate, 0);
  WriteString(" Hz"); WriteLn;

  (* Short-term feature extraction *)
  Extract(signal, numSamples, sampleRate,
          WinSize, WinStep,
          shortFeats, numShortFrames, ok);

  IF NOT ok THEN
    WriteString("Error: short-term extraction failed"); WriteLn;
    FreeSignal(signal);
    HALT
  END;

  WriteString("  Short-term frames: "); WriteCard(numShortFrames, 0);
  WriteLn;

  (* Mid-term feature extraction *)
  midWinFrames := TRUNC(MidWinSec / WinStep);
  midStepFrames := TRUNC(MidStepSec / WinStep);

  MidFeats.Extract(shortFeats, numShortFrames, NumFeatures,
                   midWinFrames, midStepFrames,
                   midFeats, numMidFrames, ok);

  IF NOT ok THEN
    WriteString("Error: mid-term extraction failed"); WriteLn;
    FreeFeatures(shortFeats);
    FreeSignal(signal);
    HALT
  END;

  WriteString("  Mid-term frames: "); WriteCard(numMidFrames, 0);
  WriteString(" ("); WriteCard(midWinFrames, 0);
  WriteString("-frame window, "); WriteCard(midStepFrames, 0);
  WriteString("-frame step)"); WriteLn;
  WriteLn;

  outCols := 2 * NumFeatures;

  (* Print summary: first mid-term frame as the "file descriptor" *)
  WriteString("Feature summary (first mid-term window):"); WriteLn;
  WriteString("  Feature                    Mean         StdDev"); WriteLn;
  WriteString("  -------                    ----         ------"); WriteLn;

  FOR i := 0 TO NumFeatures - 1 DO
    FeatureName(i, name);
    WriteString("  ");
    WriteString(name);

    (* Pad name to 25 chars *)
    IF i <= 2 THEN
      WriteString("         ")
    ELSIF i <= 7 THEN
      WriteString("      ")
    ELSIF i <= 20 THEN
      WriteString("              ")
    ELSIF i <= 32 THEN
      WriteString("            ")
    ELSE
      WriteString("        ")
    END;

    (* Mean *)
    p := Elem(midFeats, 0 * outCols + i);
    PrintReal(p^);

    WriteString("     ");

    (* StdDev *)
    p := Elem(midFeats, 0 * outCols + NumFeatures + i);
    PrintReal(p^);
    WriteLn
  END;

  (* Cleanup *)
  MidFeats.FreeMidFeatures(midFeats);
  FreeFeatures(shortFeats);
  FreeSignal(signal)
END MidStats.
