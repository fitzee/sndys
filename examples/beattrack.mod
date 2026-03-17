MODULE BeatTrack;
(* Estimate the BPM (beats per minute) of a WAV file.

   Usage: beattrack file.wav
   Example: beattrack samples/file_example_WAV_1MG.wav *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Args IMPORT ArgCount, GetArg;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, ExtractFast, FreeFeatures;
FROM Beat IMPORT BeatExtract;

CONST
  WinSize = 0.050;
  WinStep = 0.025;

VAR
  path: ARRAY [0..255] OF CHAR;
  signal: ADDRESS;
  numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
  featureMatrix: ADDRESS;
  numFrames: CARDINAL;
  bpm, ratio: LONGREAL;
  bpmInt, bpmFrac: CARDINAL;
  ratPct: CARDINAL;

BEGIN
  IF ArgCount() < 2 THEN
    WriteString("Usage: beattrack <file.wav>"); WriteLn;
    HALT
  END;

  GetArg(1, path);
  WriteString("Analyzing: "); WriteString(path); WriteLn;

  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read audio"); WriteLn;
    HALT
  END;

  WriteString("  Samples: "); WriteCard(numSamples, 0);
  WriteString("  Rate: "); WriteCard(sampleRate, 0);
  WriteString(" Hz  Duration: ~");
  WriteCard(numSamples DIV sampleRate, 0);
  WriteString("s"); WriteLn;

  WriteString("Extracting features (fast FFT)..."); WriteLn;
  ExtractFast(signal, numSamples, sampleRate,
              WinSize, WinStep,
              featureMatrix, numFrames, ok);

  IF NOT ok THEN
    WriteString("Error: feature extraction failed"); WriteLn;
    FreeSignal(signal);
    HALT
  END;

  WriteString("  Frames: "); WriteCard(numFrames, 0); WriteLn;

  WriteString("Detecting beats..."); WriteLn;
  BeatExtract(featureMatrix, numFrames, NumFeatures, WinStep, bpm, ratio);

  WriteLn;
  bpmInt := TRUNC(bpm);
  bpmFrac := TRUNC((bpm - LFLOAT(bpmInt)) * 10.0);
  ratPct := TRUNC(ratio * 100.0);

  WriteString("  BPM: "); WriteCard(bpmInt, 0);
  WriteString("."); WriteCard(bpmFrac, 0); WriteLn;

  WriteString("  Confidence: "); WriteCard(ratPct, 0);
  WriteString("%"); WriteLn;

  IF bpm < 40.0 THEN
    WriteString("  -> Very slow / ambient")
  ELSIF bpm < 80.0 THEN
    WriteString("  -> Slow tempo (ballad, adagio)")
  ELSIF bpm < 120.0 THEN
    WriteString("  -> Moderate tempo (pop, rock)")
  ELSIF bpm < 160.0 THEN
    WriteString("  -> Fast tempo (dance, allegro)")
  ELSE
    WriteString("  -> Very fast tempo")
  END;
  WriteLn;

  FreeFeatures(featureMatrix);
  FreeSignal(signal)
END BeatTrack.
