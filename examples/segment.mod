MODULE SegmentTool;
(* Audio segmentation CLI tool.

   Silence removal:
     segment silence input.wav [threshold] [min_duration]

   Supervised segmentation:
     segment classify model.bin input.wav [--hmm]

   Example:
     segment silence samples/file_example_WAV_1MG.wav
     segment silence samples/file_example_WAV_1MG.wav 0.05 0.3
     segment classify /tmp/audio_model.bin samples/file_example_WAV_1MG.wav --hmm *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Args IMPORT ArgCount, GetArg;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM Segment IMPORT SegmentList, RemoveSilence, SegmentSupervised;
FROM KNN IMPORT Model;
IMPORT KNN;

TYPE
  PathBuf = ARRAY [0..255] OF CHAR;

VAR
  mode, filePath, modelPath, arg4: PathBuf;
  signal: ADDRESS;
  numSamples, sampleRate, i: CARDINAL;
  ok: BOOLEAN;
  segs: SegmentList;
  threshold, minDur: LONGREAL;
  m: Model;
  useHMM: BOOLEAN;

PROCEDURE PrintReal2(x: LONGREAL);
VAR intP: LONGINT; fracP: CARDINAL; ax: LONGREAL;
BEGIN
  IF x < 0.0 THEN ax := -x; WriteString("-")
  ELSE ax := x END;
  intP := VAL(LONGINT, TRUNC(ax));
  fracP := TRUNC((ax - LFLOAT(intP)) * 100.0);
  WriteInt(INTEGER(intP), 0);
  WriteString(".");
  IF fracP < 10 THEN WriteString("0") END;
  WriteCard(fracP, 0)
END PrintReal2;

PROCEDURE ParseReal(s: ARRAY OF CHAR): LONGREAL;
VAR
  i: CARDINAL;
  intPart, fracPart: LONGREAL;
  inFrac: BOOLEAN;
  fracDiv: LONGREAL;
BEGIN
  intPart := 0.0;
  fracPart := 0.0;
  inFrac := FALSE;
  fracDiv := 10.0;
  i := 0;
  WHILE (i <= HIGH(s)) AND (s[i] # 0C) DO
    IF s[i] = '.' THEN
      inFrac := TRUE
    ELSIF (s[i] >= '0') AND (s[i] <= '9') THEN
      IF inFrac THEN
        fracPart := fracPart + LFLOAT(ORD(s[i]) - ORD('0')) / fracDiv;
        fracDiv := fracDiv * 10.0
      ELSE
        intPart := intPart * 10.0 + LFLOAT(ORD(s[i]) - ORD('0'))
      END
    END;
    INC(i)
  END;
  RETURN intPart + fracPart
END ParseReal;

PROCEDURE PrintUsage;
BEGIN
  WriteString("Usage:"); WriteLn;
  WriteString("  segment silence <file.wav> [threshold] [min_duration]"); WriteLn;
  WriteString("  segment classify <model.bin> <file.wav> [--hmm]"); WriteLn
END PrintUsage;

PROCEDURE PrintSegments(VAR segs: SegmentList);
VAR i: CARDINAL;
BEGIN
  WriteString("  Segments: "); WriteCard(segs.numSegments, 0); WriteLn;
  IF segs.numSegments = 0 THEN RETURN END;
  WriteLn;
  WriteString("  #     Start      End   Label"); WriteLn;
  WriteString("  ---   -----    -----   -----"); WriteLn;
  FOR i := 0 TO segs.numSegments - 1 DO
    WriteString("  ");
    WriteCard(i, 3);
    WriteString("   ");
    PrintReal2(segs.starts[i]);
    WriteString("s - ");
    PrintReal2(segs.ends[i]);
    WriteString("s   class ");
    WriteInt(segs.labels[i], 0);
    WriteLn
  END
END PrintSegments;

BEGIN
  IF ArgCount() < 3 THEN
    PrintUsage;
    HALT
  END;

  GetArg(1, mode);

  IF (mode[0] = 's') AND (mode[1] = 'i') AND (mode[2] = 'l') THEN
    (* Silence removal mode *)
    GetArg(2, filePath);

    threshold := 0.1;
    minDur := 0.2;
    IF ArgCount() >= 4 THEN
      GetArg(3, arg4);
      threshold := ParseReal(arg4)
    END;
    IF ArgCount() >= 5 THEN
      GetArg(4, arg4);
      minDur := ParseReal(arg4)
    END;

    WriteString("Silence removal: "); WriteString(filePath); WriteLn;
    WriteString("  Threshold: "); PrintReal2(threshold);
    WriteString("  Min duration: "); PrintReal2(minDur);
    WriteString("s"); WriteLn;

    ReadAudio(filePath, signal, numSamples, sampleRate, ok);
    IF NOT ok THEN
      WriteString("Error: could not read audio"); WriteLn;
      HALT
    END;

    RemoveSilence(signal, numSamples, sampleRate,
                  threshold, minDur, segs);

    WriteLn;
    PrintSegments(segs);
    FreeSignal(signal)

  ELSIF (mode[0] = 'c') AND (mode[1] = 'l') AND (mode[2] = 'a') THEN
    (* Supervised segmentation mode *)
    IF ArgCount() < 4 THEN
      PrintUsage;
      HALT
    END;

    GetArg(2, modelPath);
    GetArg(3, filePath);

    useHMM := FALSE;
    IF ArgCount() >= 5 THEN
      GetArg(4, arg4);
      IF (arg4[0] = '-') AND (arg4[1] = '-') AND
         (arg4[2] = 'h') AND (arg4[3] = 'm') AND (arg4[4] = 'm') THEN
        useHMM := TRUE
      END
    END;

    WriteString("Supervised segmentation: "); WriteString(filePath); WriteLn;
    WriteString("  Model: "); WriteString(modelPath); WriteLn;
    IF useHMM THEN
      WriteString("  HMM smoothing: enabled"); WriteLn
    ELSE
      WriteString("  HMM smoothing: disabled"); WriteLn
    END;

    KNN.LoadModel(m, modelPath, ok);
    IF NOT ok THEN
      WriteString("Error: could not load model"); WriteLn;
      HALT
    END;

    ReadAudio(filePath, signal, numSamples, sampleRate, ok);
    IF NOT ok THEN
      WriteString("Error: could not read audio"); WriteLn;
      KNN.FreeModel(m);
      HALT
    END;

    SegmentSupervised(signal, numSamples, sampleRate,
                      m, useHMM, segs);

    WriteLn;
    PrintSegments(segs);

    FreeSignal(signal);
    KNN.FreeModel(m)

  ELSE
    PrintUsage
  END
END SegmentTool.
