MODULE Features;
(* Extract and print all 34 short-term audio features for a WAV file.
   Prints per-frame features as CSV to stdout.

   Demonstrates: m2wav, m2audio (AudioIO, ShortFeats), m2fft, m2dct,
                 m2stats, m2math — the full Phase 1 stack.

   Usage: features samples/file_example_WAV_1MG.wav *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Args IMPORT ArgCount, GetArg;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, Extract, FreeFeatures, FeatureName;

CONST
  WinSize = 0.050;  (* 50 ms window *)
  WinStep = 0.025;  (* 25 ms step — 50% overlap *)

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

(* Print a LONGREAL with 6 decimal places *)
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
  fracPart := TRUNC((ax - LFLOAT(intPart)) * 1000000.0);

  IF neg THEN WriteString("-") END;
  WriteInt(INTEGER(intPart), 0);
  WriteString(".");
  IF fracPart < 100000 THEN WriteString("0") END;
  IF fracPart < 10000 THEN WriteString("0") END;
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
  featureMatrix: ADDRESS;
  numFrames: CARDINAL;
  i, j: CARDINAL;
  name: ARRAY [0..31] OF CHAR;
  p: RealPtr;
  durSec: CARDINAL;

BEGIN
  IF ArgCount() < 2 THEN
    WriteString("Usage: features <file.wav>"); WriteLn;
    HALT
  END;

  GetArg(1, path);
  WriteString("Reading: "); WriteString(path); WriteLn;

  (* Read audio (auto stereo-to-mono) *)
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read audio file"); WriteLn;
    HALT
  END;

  durSec := numSamples DIV sampleRate;
  WriteString("  Samples: "); WriteCard(numSamples, 0);
  WriteString("  Rate: "); WriteCard(sampleRate, 0);
  WriteString(" Hz  Duration: ~"); WriteCard(durSec, 0);
  WriteString("s"); WriteLn;

  (* Extract features *)
  WriteString("Extracting features (");
  WriteCard(TRUNC(WinSize * 1000.0), 0);
  WriteString("ms window, ");
  WriteCard(TRUNC(WinStep * 1000.0), 0);
  WriteString("ms step)..."); WriteLn;

  Extract(signal, numSamples, sampleRate,
          WinSize, WinStep,
          featureMatrix, numFrames, ok);

  IF NOT ok THEN
    WriteString("Error: feature extraction failed"); WriteLn;
    FreeSignal(signal);
    HALT
  END;

  WriteString("  Frames: "); WriteCard(numFrames, 0);
  WriteString("  Features/frame: "); WriteCard(NumFeatures, 0);
  WriteLn; WriteLn;

  (* Print CSV header *)
  WriteString("frame");
  FOR j := 0 TO NumFeatures - 1 DO
    WriteString(",");
    FeatureName(j, name);
    WriteString(name)
  END;
  WriteLn;

  (* Print first 10 frames as CSV (or all if fewer) *)
  i := 0;
  WHILE i < numFrames DO
    WriteCard(i, 0);
    FOR j := 0 TO NumFeatures - 1 DO
      WriteString(",");
      p := Elem(featureMatrix, i * NumFeatures + j);
      PrintReal(p^)
    END;
    WriteLn;
    INC(i)
  END;

  (* Cleanup *)
  FreeFeatures(featureMatrix);
  FreeSignal(signal)
END Features.
