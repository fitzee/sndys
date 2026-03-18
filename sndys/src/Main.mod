MODULE Sndys;
(* sndys — unified audio analysis CLI.

   Usage: sndys <command> [args...]

   Commands:
     info      <file.wav>                          WAV file metadata
     spectrum  <file.wav>                          FFT frequency analysis
     features  <file.wav>                          Extract 34 features (CSV)
     beats     <file.wav>                          Estimate BPM
     silence   <file.wav> [threshold] [min_dur]    Detect non-silent regions
     midstats  <file.wav>                          Mid-term feature summary
     compare   <file1.wav> <file2.wav>             Audio similarity
     train     <dir1> <dir2> [...] -o <model>      Train classifier
     predict   <model> <file.wav>                  Classify audio
     segment   <model> <file.wav> [--hmm]          Segment audio by class
     downsample <in.wav> <out.wav> <rate>           Resample (stereo->mono)
     mono       <in.wav> <out.wav>                  Stereo to mono
     spectrogram <file.wav>                         Spectrogram CSV
     chromagram  <file.wav>                         Chromagram CSV
     thumbnail   <file.wav> [duration_sec]          Most representative segment
     diarize     <file.wav> [num_speakers]          Speaker diarization
     harmonic    <file.wav>                         Harmonic ratio + F0 *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Args IMPORT ArgCount, GetArg;
FROM MathLib IMPORT sqrt, sin;
FROM Strings IMPORT Assign, Length, Concat;
FROM Wav IMPORT WavInfo, ReadWav, FreeWav, WriteWav, GetDuration,
                StereoToMono, FreeMono, Downsample;
FROM FFT IMPORT Forward, Magnitude;
FROM MathUtil IMPORT TwoPi, NextPow2, FAbs;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM ShortFeats IMPORT NumFeatures, Extract, ExtractFast, FreeFeatures,
                       FeatureName;
IMPORT MidFeats;
FROM Beat IMPORT BeatExtract;
FROM Segment IMPORT SegmentList, RemoveSilence, SegmentSupervised, Diarize;
FROM Spectro IMPORT ComputeSpectrogram, ComputeChromagram, FreeSpectro;
FROM Thumbnail IMPORT FindThumbnail;
FROM Harmonic IMPORT ComputeHarmonicF0;
FROM KeyDetect IMPORT DetectKey;
FROM Onset IMPORT DetectOnsets;
FROM AudioProc IMPORT Trim, Mix, Normalize, FadeIn, FadeOut,
                      Reverse, GenerateSine, GenerateChirp,
                      GenerateNoise, GenerateClick, FreeProc;
FROM PitchTrack IMPORT TrackPitch, FreePitch;
FROM TempoCurve IMPORT ComputeTempoCurve, FreeTempoCurve;
IMPORT AudioConcat;
FROM Filter IMPORT Lowpass, Highpass, Bandpass;
FROM AudioStats IMPORT StatsResult, Analyze;
FROM Waveform IMPORT DrawWaveform;
FROM Convert IMPORT ConvertToWav, NeedsConversion, IsWavFile;
FROM Sys IMPORT m2sys_list_dir;
FROM Chords IMPORT ChordResult, DetectChordSequence, FreeChords;
FROM NoteTranscribe IMPORT NoteEvent, Transcribe, FreeNotes;
FROM VoiceFeats IMPORT ComputeHNR;
FROM Rhythm IMPORT TempoStability, BeatStrength;
FROM SpectralExtra IMPORT SpectralFlatness, SpectralBandwidth, SpectralSlope,
                          SpectralContrast;
FROM Tonnetz IMPORT ComputeTonnetz;
FROM VoiceFeats IMPORT ComputeFormants, ComputeJitter, ComputeShimmer,
                       ComputeHNR;
FROM Classify IMPORT VectorLen, ExtractFileVector, TrainFromDirs, PredictFile;
FROM Playback IMPORT InitAudio, QuitAudio, OpenDevice, CloseDevice,
                     ResumeDevice, PauseDevice, QueueSamples,
                     GetQueuedBytes, ClearQueued, GetObtainedSpec,
                     Delay, RawMode, RestoreMode, KeyPressed,
                     DeviceID, AudioSpec, FormatF32;
FROM Stats IMPORT Mean, StdDev;
FROM KNN IMPORT Model;
IMPORT KNN;

CONST
  WinSize  = 0.050;
  WinStep  = 0.025;
  MaxDirs  = 16;
  DefaultK = 5;

TYPE
  PathBuf = ARRAY [0..255] OF CHAR;
  RealPtr = POINTER TO LONGREAL;
  IntPtr  = POINTER TO INTEGER;

VAR
  cmd: PathBuf;

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE PrintReal(x: LONGREAL; decimals: CARDINAL);
VAR
  intP: LONGINT;
  fracP, mult, d: CARDINAL;
  neg: BOOLEAN;
  ax: LONGREAL;
BEGIN
  neg := x < 0.0;
  IF neg THEN ax := -x ELSE ax := x END;
  intP := VAL(LONGINT, TRUNC(ax));
  mult := 1;
  FOR d := 1 TO decimals DO mult := mult * 10 END;
  fracP := TRUNC((ax - LFLOAT(intP)) * LFLOAT(mult));
  IF neg THEN WriteString("-") END;
  WriteInt(INTEGER(intP), 0);
  WriteString(".");
  d := mult DIV 10;
  WHILE d > 0 DO
    IF fracP < d THEN WriteString("0") END;
    d := d DIV 10
  END;
  WriteCard(fracP, 0)
END PrintReal;

PROCEDURE ParseReal(s: ARRAY OF CHAR): LONGREAL;
VAR
  i: CARDINAL; intPart, fracPart, fracDiv: LONGREAL; inFrac: BOOLEAN;
BEGIN
  intPart := 0.0; fracPart := 0.0; inFrac := FALSE; fracDiv := 10.0;
  i := 0;
  WHILE (i <= HIGH(s)) AND (s[i] # 0C) DO
    IF s[i] = '.' THEN inFrac := TRUE
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

PROCEDURE StrEq(a, b: ARRAY OF CHAR): BOOLEAN;
VAR i: CARDINAL;
BEGIN
  i := 0;
  WHILE (i <= HIGH(a)) AND (i <= HIGH(b)) DO
    IF a[i] # b[i] THEN RETURN FALSE END;
    IF a[i] = 0C THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN TRUE
END StrEq;

(* ════════════════════════════════════════════════════ *)

PROCEDURE PrintUsage;
BEGIN
  WriteString("sndys — audio analysis toolkit (Modula-2)"); WriteLn;
  WriteLn;
  WriteString("Usage: sndys <command> [args...]"); WriteLn;
  WriteLn;
  WriteString("Info:"); WriteLn;
  WriteString("  info        <file.wav>                      File metadata"); WriteLn;
  WriteString("  spectrum    <file.wav>                      Top 20 FFT bins"); WriteLn;
  WriteString("  spectrogram <file.wav>                      Spectrogram (CSV)"); WriteLn;
  WriteString("  chromagram  <file.wav>                      Chromagram (CSV)"); WriteLn;
  WriteLn;
  WriteString("Analysis:"); WriteLn;
  WriteString("  features    <file.wav>                      34 features (CSV)"); WriteLn;
  WriteString("  midstats    <file.wav>                      Per-feature mean/std"); WriteLn;
  WriteString("  beats       <file.wav>                      Estimate BPM"); WriteLn;
  WriteString("  tempocurve  <file.wav> [win] [hop]          BPM over time"); WriteLn;
  WriteString("  key         <file.wav>                      Detect musical key"); WriteLn;
  WriteString("  pitch       <file.wav>                      Pitch contour (CSV)"); WriteLn;
  WriteString("  harmonic    <file.wav>                      Harmonic ratio + F0"); WriteLn;
  WriteString("  onsets      <file.wav> [sensitivity]        Note onset times"); WriteLn;
  WriteString("  silence     <file.wav> [thresh] [min_dur]   Non-silent regions"); WriteLn;
  WriteString("  compare     <file1.wav> <file2.wav>         Similarity score"); WriteLn;
  WriteString("  thumbnail   <in> <out> [duration_sec]       Most representative segment"); WriteLn;
  WriteLn;
  WriteString("Classification:"); WriteLn;
  WriteString("  train       <dir1> <dir2> [...] -o <model>  Train k-NN classifier"); WriteLn;
  WriteString("  predict     <model> <file.wav>              Classify a file"); WriteLn;
  WriteString("  segment     <model> <file.wav> [--hmm]      Segment by class"); WriteLn;
  WriteString("  diarize     <file.wav> [num_speakers]       Speaker diarization"); WriteLn;
  WriteLn;
  WriteString("Processing:"); WriteLn;
  WriteString("  trim        <in> <out> <start> <end>        Extract time region"); WriteLn;
  WriteString("  concat      <a.wav> <b.wav> <out> [xfade]   Join files"); WriteLn;
  WriteString("  mix         <a.wav> <b.wav> <out> [ratio]   Mix two files"); WriteLn;
  WriteString("  normalize   <in> <out> [peak]               Peak normalization"); WriteLn;
  WriteString("  fade        <in> <out> <in_sec> <out_sec>   Apply fades"); WriteLn;
  WriteString("  reverse     <in> <out>                      Reverse audio"); WriteLn;
  WriteString("  mono        <in> <out>                      Stereo to mono"); WriteLn;
  WriteString("  downsample  <in> <out> <rate>               Resample to mono"); WriteLn;
  WriteString("  lowpass     <in> <out> <freq_hz>            Low-pass filter"); WriteLn;
  WriteString("  highpass    <in> <out> <freq_hz>            High-pass filter"); WriteLn;
  WriteString("  bandpass    <in> <out> <lo_hz> <hi_hz>      Band-pass filter"); WriteLn;
  WriteLn;
  WriteString("Playback:"); WriteLn;
  WriteString("  play        <file.wav>                      Play audio (key to stop)"); WriteLn;
  WriteLn;
  WriteString("Generation:"); WriteLn;
  WriteString("  generate    sine  <out> <freq> <dur> [amp]"); WriteLn;
  WriteString("  generate    chirp <out> <startHz> <endHz> <dur>"); WriteLn;
  WriteString("  generate    noise <out> <dur> [amp]"); WriteLn;
  WriteString("  generate    click <out> <bpm> <dur>"); WriteLn;
  WriteLn;
  WriteString("Music Intelligence:"); WriteLn;
  WriteString("  chords      <file.wav>                      Chord sequence"); WriteLn;
  WriteString("  notes       <file.wav>                      Note transcription"); WriteLn;
  WriteString("  tonnetz     <file.wav>                      Tonal centroid (CSV)"); WriteLn;
  WriteString("  voice       <file.wav>                      Formants, jitter, shimmer, HNR"); WriteLn;
  WriteString("  flatness    <file.wav>                      Spectral flatness (CSV)"); WriteLn;
  WriteString("  stability   <file.wav>                      Tempo stability score"); WriteLn;
  WriteLn;
  WriteString("Utilities:"); WriteLn;
  WriteString("  stats       <file.wav>                      RMS, peak, crest, DC"); WriteLn;
  WriteString("  waveform    <file.wav>                      ASCII waveform display"); WriteLn;
  WriteString("  convert     <input> <output.wav> [rate]     Convert via ffmpeg"); WriteLn;
  WriteString("  analyze     <file.wav>                      Full analysis report"); WriteLn;
  WriteString("  batch       <command> <dir>                  Run on all WAVs in dir"); WriteLn;
  WriteString("  version                                      Show version"); WriteLn
END PrintUsage;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdInfo;
VAR
  path: PathBuf; info: WavInfo; samples: ADDRESS; ok: BOOLEAN;
  dur: LONGREAL; durSec, durMs: CARDINAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys info <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadWav(path, info, samples, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  WriteString("File: "); WriteString(path); WriteLn;
  WriteString("  Sample rate:    "); WriteCard(info.sampleRate, 0);
  WriteString(" Hz"); WriteLn;
  WriteString("  Channels:       "); WriteCard(info.numChannels, 0);
  IF info.numChannels = 1 THEN WriteString(" (mono)")
  ELSIF info.numChannels = 2 THEN WriteString(" (stereo)") END;
  WriteLn;
  WriteString("  Bits/sample:    "); WriteCard(info.bitsPerSample, 0); WriteLn;
  WriteString("  Samples:        "); WriteCard(info.numSamples, 0); WriteLn;
  WriteString("  Data size:      "); WriteCard(info.dataSize, 0);
  WriteString(" bytes"); WriteLn;
  dur := GetDuration(info);
  durSec := TRUNC(dur);
  durMs := TRUNC((dur - LFLOAT(durSec)) * 1000.0);
  WriteString("  Duration:       "); WriteCard(durSec, 0); WriteString(".");
  IF durMs < 100 THEN WriteString("0") END;
  IF durMs < 10 THEN WriteString("0") END;
  WriteCard(durMs, 0); WriteString("s"); WriteLn;
  FreeWav(samples, info.numSamples * info.numChannels)
END CmdInfo;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdSpectrum;
VAR
  path: PathBuf; info: WavInfo; rawSamples, mono: ADDRESS; ok: BOOLEAN;
  frameSamples, fftSize, fftHalf, i, printed, maxIdx: CARDINAL;
  complexBuf, magBuf: ADDRESS;
  p, pMax: RealPtr;
  maxVal, freqHz: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys spectrum <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadWav(path, info, rawSamples, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  IF info.numChannels = 2 THEN
    StereoToMono(rawSamples, info.numSamples, mono);
    FreeWav(rawSamples, info.numSamples * info.numChannels)
  ELSE mono := rawSamples END;

  frameSamples := info.sampleRate * 50 DIV 1000;
  IF frameSamples > info.numSamples THEN frameSamples := info.numSamples END;
  fftSize := NextPow2(frameSamples);
  fftHalf := fftSize DIV 2 + 1;

  ALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  ALLOCATE(magBuf, fftSize * TSIZE(LONGREAL));

  FOR i := 0 TO fftSize - 1 DO
    p := ElemR(complexBuf, 2 * i);
    IF i < frameSamples THEN pMax := ElemR(mono, i); p^ := pMax^
    ELSE p^ := 0.0 END;
    p := ElemR(complexBuf, 2 * i + 1); p^ := 0.0
  END;

  Forward(complexBuf, fftSize);
  Magnitude(complexBuf, fftSize, magBuf);

  WriteString("FFT of first 50ms ("); WriteCard(frameSamples, 0);
  WriteString(" samples, padded to "); WriteCard(fftSize, 0);
  WriteString(")"); WriteLn; WriteLn;
  WriteString("  Bin    Freq (Hz)    Magnitude"); WriteLn;
  WriteString("  ---    ---------    ---------"); WriteLn;

  printed := 0;
  WHILE printed < 20 DO
    maxVal := -1.0; maxIdx := 0;
    FOR i := 0 TO fftHalf - 1 DO
      p := ElemR(magBuf, i);
      IF p^ > maxVal THEN maxVal := p^; maxIdx := i END
    END;
    IF maxVal <= 0.0 THEN EXIT END;
    freqHz := LFLOAT(maxIdx) * LFLOAT(info.sampleRate) / LFLOAT(fftSize);
    WriteString("  "); WriteCard(maxIdx, 5); WriteString("    ");
    WriteCard(TRUNC(freqHz), 6); WriteString(" Hz    ");
    WriteCard(TRUNC(maxVal * 1000.0), 8); WriteString(" (x1000)"); WriteLn;
    p := ElemR(magBuf, maxIdx); p^ := 0.0;
    INC(printed)
  END;

  DEALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  DEALLOCATE(magBuf, fftSize * TSIZE(LONGREAL));
  IF info.numChannels = 2 THEN FreeMono(mono, info.numSamples)
  ELSE FreeWav(mono, info.numSamples) END
END CmdSpectrum;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdFeatures;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate, i, j: CARDINAL;
  ok: BOOLEAN; feats: ADDRESS; numFrames: CARDINAL;
  name: ARRAY [0..31] OF CHAR; p: RealPtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys features <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  ExtractFast(signal, numSamples, sampleRate, WinSize, WinStep,
              feats, numFrames, ok);
  IF NOT ok THEN
    WriteString("Error: feature extraction failed"); WriteLn;
    FreeSignal(signal, numSamples); HALT
  END;
  (* CSV header *)
  WriteString("frame");
  FOR j := 0 TO NumFeatures - 1 DO
    WriteString(","); FeatureName(j, name); WriteString(name)
  END;
  WriteLn;
  (* CSV rows *)
  FOR i := 0 TO numFrames - 1 DO
    WriteCard(i, 0);
    FOR j := 0 TO NumFeatures - 1 DO
      WriteString(",");
      p := ElemR(feats, i * NumFeatures + j);
      PrintReal(p^, 6)
    END;
    WriteLn
  END;
  FreeFeatures(feats, numFrames); FreeSignal(signal, numSamples)
END CmdFeatures;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdBeats;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; feats: ADDRESS; numFrames: CARDINAL;
  bpm, ratio: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys beats <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  WriteString("Analyzing: "); WriteString(path); WriteLn;
  WriteString("  Duration: ~"); WriteCard(numSamples DIV sampleRate, 0);
  WriteString("s ("); WriteCard(sampleRate, 0); WriteString(" Hz)"); WriteLn;

  ExtractFast(signal, numSamples, sampleRate, WinSize, WinStep,
              feats, numFrames, ok);
  IF NOT ok THEN
    WriteString("Error: feature extraction failed"); WriteLn;
    FreeSignal(signal, numSamples); HALT
  END;
  BeatExtract(feats, numFrames, NumFeatures, WinStep, bpm, ratio);

  WriteString("  BPM: "); PrintReal(bpm, 1); WriteLn;
  WriteString("  Confidence: "); WriteCard(TRUNC(ratio * 100.0), 0);
  WriteString("%"); WriteLn;
  FreeFeatures(feats, numFrames); FreeSignal(signal, numSamples)
END CmdBeats;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdSilence;
VAR
  path, arg: PathBuf; signal: ADDRESS; numSamples, sampleRate, i: CARDINAL;
  ok: BOOLEAN; segs: SegmentList; threshold, minDur: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys silence <file.wav> [threshold] [min_dur]"); WriteLn; HALT
  END;
  GetArg(2, path);
  threshold := 0.05; minDur := 0.3;
  IF ArgCount() >= 4 THEN GetArg(3, arg); threshold := ParseReal(arg) END;
  IF ArgCount() >= 5 THEN GetArg(4, arg); minDur := ParseReal(arg) END;

  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  RemoveSilence(signal, numSamples, sampleRate, threshold, minDur, segs);

  WriteString("Non-silent segments: "); WriteCard(segs.numSegments, 0); WriteLn;
  FOR i := 0 TO segs.numSegments - 1 DO
    WriteString("  "); WriteCard(i, 3); WriteString("  ");
    PrintReal(segs.starts[i], 2); WriteString("s - ");
    PrintReal(segs.ends[i], 2); WriteString("s"); WriteLn
  END;
  FreeSignal(signal, numSamples)
END CmdSilence;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdMidstats;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; shortFeats, midFeats: ADDRESS;
  numShortFrames, numMidFrames: CARDINAL;
  midWinFrames, midStepFrames, outCols, i: CARDINAL;
  name: ARRAY [0..31] OF CHAR; p: RealPtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys midstats <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  ExtractFast(signal, numSamples, sampleRate, WinSize, WinStep,
              shortFeats, numShortFrames, ok);
  IF NOT ok THEN
    WriteString("Error: feature extraction failed"); WriteLn;
    FreeSignal(signal, numSamples); HALT
  END;
  midWinFrames := TRUNC(1.0 / WinStep);
  midStepFrames := TRUNC(0.5 / WinStep);
  MidFeats.Extract(shortFeats, numShortFrames, NumFeatures,
                   midWinFrames, midStepFrames,
                   midFeats, numMidFrames, ok);
  IF NOT ok THEN
    WriteString("Error: mid-term extraction failed"); WriteLn;
    FreeFeatures(shortFeats, numShortFrames); FreeSignal(signal, numSamples); HALT
  END;
  outCols := 2 * NumFeatures;

  WriteString("File: "); WriteString(path); WriteLn;
  WriteString("  Mid-term frames: "); WriteCard(numMidFrames, 0); WriteLn;
  WriteLn;
  WriteString("Feature                      Mean       StdDev"); WriteLn;
  WriteString("-------                      ----       ------"); WriteLn;

  FOR i := 0 TO NumFeatures - 1 DO
    FeatureName(i, name);
    WriteString(name);
    (* Pad to 30 chars *)
    IF Length(name) < 25 THEN
      WriteString("                         ");
    END;

    p := ElemR(midFeats, 0 * outCols + i);
    PrintReal(p^, 4);
    WriteString("   ");
    p := ElemR(midFeats, 0 * outCols + NumFeatures + i);
    PrintReal(p^, 4);
    WriteLn
  END;

  MidFeats.FreeMidFeatures(midFeats, numMidFrames, NumFeatures);
  FreeFeatures(shortFeats, numShortFrames); FreeSignal(signal, numSamples)
END CmdMidstats;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdCompare;
VAR
  path1, path2: PathBuf;
  vec1, vec2: ARRAY [0..33] OF LONGREAL;
  ok1, ok2: BOOLEAN;
  dist, diff: LONGREAL;
  i: CARDINAL;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys compare <file1.wav> <file2.wav>"); WriteLn; HALT
  END;
  GetArg(2, path1); GetArg(3, path2);

  WriteString("File 1: "); WriteString(path1); WriteLn;
  ExtractFileVector(path1, vec1, ok1);
  IF NOT ok1 THEN
    WriteString("Error reading file 1"); WriteLn; HALT
  END;

  WriteString("File 2: "); WriteString(path2); WriteLn;
  ExtractFileVector(path2, vec2, ok2);
  IF NOT ok2 THEN
    WriteString("Error reading file 2"); WriteLn; HALT
  END;

  dist := 0.0;
  FOR i := 0 TO VectorLen - 1 DO
    diff := vec1[i] - vec2[i];
    dist := dist + diff * diff
  END;
  dist := LFLOAT(sqrt(FLOAT(dist)));

  WriteLn;
  WriteString("Euclidean distance: "); PrintReal(dist, 4); WriteLn;
  IF dist < 1.0 THEN WriteString("  -> Very similar")
  ELSIF dist < 5.0 THEN WriteString("  -> Moderately similar")
  ELSIF dist < 20.0 THEN WriteString("  -> Somewhat different")
  ELSE WriteString("  -> Very different")
  END;
  WriteLn
END CmdCompare;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdTrain;
VAR
  dirPaths: ARRAY [0..15] OF PathBuf;
  dirAddrs: ARRAY [0..15] OF ADDRESS;
  modelPath, tmpArg: PathBuf;
  numDirs, argIdx: CARDINAL;
  m: Model;
  ok: BOOLEAN;
BEGIN
  numDirs := 0; argIdx := 2; modelPath[0] := 0C;

  WHILE argIdx < CARDINAL(ArgCount()) DO
    GetArg(INTEGER(argIdx), tmpArg);
    IF (tmpArg[0] = '-') AND (tmpArg[1] = 'o') AND (tmpArg[2] = 0C) THEN
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
    WriteString("Error: need at least 2 class directories"); WriteLn; HALT
  END;
  IF modelPath[0] = 0C THEN
    WriteString("Error: specify output model with -o <path>"); WriteLn; HALT
  END;

  WriteString("Training classifier ("); WriteCard(numDirs, 0);
  WriteString(" classes, k="); WriteCard(DefaultK, 0);
  WriteString(")"); WriteLn;

  TrainFromDirs(m, ADR(dirAddrs), numDirs, DefaultK, ok);
  IF NOT ok THEN
    WriteString("Training failed"); WriteLn; HALT
  END;

  KNN.SaveModel(m, modelPath, ok);
  IF ok THEN
    WriteString("Model saved: "); WriteString(modelPath); WriteLn
  ELSE
    WriteString("Error saving model"); WriteLn
  END
END CmdTrain;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdPredict;
VAR
  modelPath, filePath: PathBuf;
  m: Model; ok: BOOLEAN;
  proba: ARRAY [0..31] OF LONGREAL;
  pred: INTEGER; i: CARDINAL;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys predict <model> <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, modelPath); GetArg(3, filePath);

  KNN.LoadModel(m, modelPath, ok);
  IF NOT ok THEN
    WriteString("Error: could not load model"); WriteLn; HALT
  END;

  WriteString("Classifying: "); WriteString(filePath); WriteLn;
  pred := PredictFile(m, filePath, proba);
  IF pred < 0 THEN
    WriteString("Error: feature extraction failed"); WriteLn;
    KNN.FreeModel(m); HALT
  END;

  WriteLn;
  WriteString("Predicted class: "); WriteInt(pred, 0); WriteLn;
  FOR i := 0 TO m.numClasses - 1 DO
    WriteString("  Class "); WriteCard(i, 0); WriteString(": ");
    PrintReal(proba[i], 4);
    IF INTEGER(i) = pred THEN WriteString("  <--") END;
    WriteLn
  END;
  KNN.FreeModel(m)
END CmdPredict;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdSegment;
VAR
  modelPath, filePath, arg: PathBuf;
  m: Model; ok: BOOLEAN;
  signal: ADDRESS; numSamples, sampleRate, i: CARDINAL;
  segs: SegmentList;
  useHMM: BOOLEAN;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys segment <model> <file.wav> [--hmm]"); WriteLn; HALT
  END;
  GetArg(2, modelPath); GetArg(3, filePath);
  useHMM := FALSE;
  IF ArgCount() >= 5 THEN
    GetArg(4, arg);
    IF (arg[0] = '-') AND (arg[1] = '-') AND
       (arg[2] = 'h') AND (arg[3] = 'm') AND (arg[4] = 'm') THEN
      useHMM := TRUE
    END
  END;

  KNN.LoadModel(m, modelPath, ok);
  IF NOT ok THEN
    WriteString("Error: could not load model"); WriteLn; HALT
  END;

  ReadAudio(filePath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(filePath); WriteLn;
    KNN.FreeModel(m); HALT
  END;

  WriteString("Segmenting: "); WriteString(filePath);
  IF useHMM THEN WriteString(" (HMM smoothing)") END;
  WriteLn;

  SegmentSupervised(signal, numSamples, sampleRate, m, useHMM, segs);

  WriteLn;
  WriteString("Segments: "); WriteCard(segs.numSegments, 0); WriteLn;
  FOR i := 0 TO segs.numSegments - 1 DO
    WriteString("  "); WriteCard(i, 3); WriteString("  ");
    PrintReal(segs.starts[i], 2); WriteString("s - ");
    PrintReal(segs.ends[i], 2); WriteString("s  class ");
    WriteInt(segs.labels[i], 0); WriteLn
  END;

  FreeSignal(signal, numSamples); KNN.FreeModel(m)
END CmdSegment;

(* ════════════════════════════════════════════════════ *)

PROCEDURE ParseInt(s: ARRAY OF CHAR): INTEGER;
VAR i, result: INTEGER;
BEGIN
  result := 0; i := 0;
  WHILE (i <= HIGH(s)) AND (s[i] # 0C) AND
        (s[i] >= '0') AND (s[i] <= '9') DO
    result := result * 10 + (ORD(s[i]) - ORD('0'));
    INC(i)
  END;
  RETURN result
END ParseInt;

PROCEDURE CmdDownsample;
VAR
  inPath, outPath, rateArg: PathBuf;
  info: WavInfo;
  raw, down: ADDRESS;
  ok: BOOLEAN;
  targetRate, outN: CARDINAL;
BEGIN
  IF ArgCount() < 5 THEN
    WriteString("Usage: sndys downsample <input.wav> <output.wav> <rate_hz>"); WriteLn;
    HALT
  END;
  GetArg(2, inPath);
  GetArg(3, outPath);
  GetArg(4, rateArg);
  targetRate := CARDINAL(ParseInt(rateArg));

  IF targetRate = 0 THEN
    WriteString("Error: target rate must be > 0"); WriteLn; HALT
  END;

  ReadWav(inPath, info, raw, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(inPath); WriteLn; HALT
  END;

  WriteString("Input:  "); WriteCard(info.sampleRate, 0);
  WriteString(" Hz, "); WriteCard(info.numChannels, 0);
  WriteString(" ch, "); WriteCard(info.bitsPerSample, 0);
  WriteString("-bit, "); WriteCard(info.numSamples, 0);
  WriteString(" samples"); WriteLn;

  Downsample(raw, info.numSamples, info.numChannels,
             info.sampleRate, targetRate, down, outN);
  FreeWav(raw, info.numSamples * info.numChannels);

  WriteString("Output: "); WriteCard(targetRate, 0);
  WriteString(" Hz, 1 ch, 16-bit, ");
  WriteCard(outN, 0); WriteString(" samples"); WriteLn;

  WriteWav(outPath, down, outN, targetRate, 1, 16, ok);
  FreeMono(down, outN);

  IF ok THEN
    WriteString("Wrote "); WriteString(outPath); WriteLn
  ELSE
    WriteString("Error writing "); WriteString(outPath); WriteLn
  END
END CmdDownsample;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdMono;
VAR
  inPath, outPath: PathBuf;
  info: WavInfo;
  raw, mono: ADDRESS;
  ok: BOOLEAN;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys mono <input.wav> <output.wav>"); WriteLn; HALT
  END;
  GetArg(2, inPath);
  GetArg(3, outPath);

  ReadWav(inPath, info, raw, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(inPath); WriteLn; HALT
  END;

  WriteString("Input:  "); WriteCard(info.sampleRate, 0);
  WriteString(" Hz, "); WriteCard(info.numChannels, 0);
  WriteString(" ch, "); WriteCard(info.bitsPerSample, 0);
  WriteString("-bit, "); WriteCard(info.numSamples, 0);
  WriteString(" samples"); WriteLn;

  IF info.numChannels = 1 THEN
    WriteString("Already mono — copying"); WriteLn;
    WriteWav(outPath, raw, info.numSamples, info.sampleRate, 1, 16, ok);
    FreeWav(raw, info.numSamples)
  ELSE
    StereoToMono(raw, info.numSamples, mono);
    FreeWav(raw, info.numSamples * info.numChannels);
    WriteString("Output: "); WriteCard(info.sampleRate, 0);
    WriteString(" Hz, 1 ch, 16-bit, ");
    WriteCard(info.numSamples, 0); WriteString(" samples"); WriteLn;
    WriteWav(outPath, mono, info.numSamples, info.sampleRate, 1, 16, ok);
    FreeMono(mono, info.numSamples)
  END;

  IF ok THEN
    WriteString("Wrote "); WriteString(outPath); WriteLn
  ELSE
    WriteString("Error writing "); WriteString(outPath); WriteLn
  END
END CmdMono;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdSpectrogram;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; spectro: ADDRESS; numFrames, numBins, t, b: CARDINAL;
  p: RealPtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys spectrogram <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  ComputeSpectrogram(signal, numSamples, sampleRate, WinSize, WinStep,
                      spectro, numFrames, numBins);
  FreeSignal(signal, numSamples);
  IF numFrames = 0 THEN
    WriteString("Error: spectrogram failed"); WriteLn; HALT
  END;

  (* CSV header: frame, bin0, bin1, ... *)
  WriteString("frame");
  FOR b := 0 TO numBins - 1 DO
    WriteString(","); WriteCard(b, 0)
  END;
  WriteLn;

  FOR t := 0 TO numFrames - 1 DO
    WriteCard(t, 0);
    FOR b := 0 TO numBins - 1 DO
      WriteString(",");
      p := ElemR(spectro, t * numBins + b);
      PrintReal(p^, 4)
    END;
    WriteLn
  END;
  FreeSpectro(spectro, numFrames * numBins)
END CmdSpectrogram;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdChromagram;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; chroma: ADDRESS; numFrames, t, c: CARDINAL;
  p: RealPtr;
  names: ARRAY [0..11] OF ARRAY [0..2] OF CHAR;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys chromagram <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  ComputeChromagram(signal, numSamples, sampleRate, WinSize, WinStep,
                     chroma, numFrames);
  FreeSignal(signal, numSamples);
  IF numFrames = 0 THEN
    WriteString("Error: chromagram failed"); WriteLn; HALT
  END;

  WriteString("frame,A,A#,B,C,C#,D,D#,E,F,F#,G,G#"); WriteLn;
  FOR t := 0 TO numFrames - 1 DO
    WriteCard(t, 0);
    FOR c := 0 TO 11 DO
      WriteString(",");
      p := ElemR(chroma, t * 12 + c);
      PrintReal(p^, 6)
    END;
    WriteLn
  END;
  FreeSpectro(chroma, numFrames * 12)
END CmdChromagram;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdThumbnail;
VAR
  path, durArg, outPath: PathBuf;
  signal, trimmed: ADDRESS;
  numSamples, sampleRate, outN: CARDINAL;
  ok: BOOLEAN; feats: ADDRESS; numFrames: CARDINAL;
  thumbDurSec: LONGREAL;
  thumbDurFrames, startFrame: CARDINAL;
  score, startSec, endSec: LONGREAL;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys thumbnail <file.wav> <out.wav> [duration_sec]"); WriteLn; HALT
  END;
  GetArg(2, path);
  GetArg(3, outPath);
  thumbDurSec := 10.0;
  IF ArgCount() >= 5 THEN
    GetArg(4, durArg);
    thumbDurSec := ParseReal(durArg)
  END;

  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;

  ExtractFast(signal, numSamples, sampleRate, WinSize, WinStep,
              feats, numFrames, ok);
  IF NOT ok THEN
    WriteString("Error: feature extraction failed"); WriteLn;
    FreeSignal(signal, numSamples); HALT
  END;

  thumbDurFrames := TRUNC(thumbDurSec / WinStep);
  IF thumbDurFrames >= numFrames THEN
    thumbDurFrames := numFrames DIV 2
  END;

  WriteString("Finding most representative ");
  PrintReal(thumbDurSec, 1);
  WriteString("s segment..."); WriteLn;

  FindThumbnail(feats, numFrames, NumFeatures, thumbDurFrames,
                startFrame, score);
  FreeFeatures(feats, numFrames);

  startSec := LFLOAT(startFrame) * WinStep;
  endSec := LFLOAT(startFrame + thumbDurFrames) * WinStep;

  WriteString("Thumbnail: ");
  PrintReal(startSec, 2); WriteString("s - ");
  PrintReal(endSec, 2); WriteString("s (score: ");
  PrintReal(score, 4); WriteString(")"); WriteLn;

  (* Extract and write the thumbnail audio *)
  Trim(signal, numSamples, sampleRate, startSec, endSec, trimmed, outN);
  FreeSignal(signal, numSamples);
  WriteWav(outPath, trimmed, outN, sampleRate, 1, 16, ok);
  FreeProc(trimmed, outN);
  IF ok THEN
    WriteString("Wrote "); WriteString(outPath); WriteLn
  ELSE
    WriteString("Error writing output"); WriteLn
  END
END CmdThumbnail;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdDiarize;
VAR
  path, numSpkArg: PathBuf;
  signal: ADDRESS; numSamples, sampleRate, i: CARDINAL;
  ok: BOOLEAN;
  numSpeakers: CARDINAL;
  segs: SegmentList;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys diarize <file.wav> [num_speakers]"); WriteLn; HALT
  END;
  GetArg(2, path);
  numSpeakers := 0;  (* auto-detect *)
  IF ArgCount() >= 4 THEN
    GetArg(3, numSpkArg);
    numSpeakers := CARDINAL(ParseInt(numSpkArg))
  END;

  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;

  WriteString("Speaker diarization: "); WriteString(path); WriteLn;
  IF numSpeakers > 0 THEN
    WriteString("  Speakers: "); WriteCard(numSpeakers, 0); WriteLn
  ELSE
    WriteString("  Speakers: auto-detect (2-8)"); WriteLn
  END;

  Diarize(signal, numSamples, sampleRate, numSpeakers, segs);
  FreeSignal(signal, numSamples);

  WriteLn;
  WriteString("Segments: "); WriteCard(segs.numSegments, 0); WriteLn;
  FOR i := 0 TO segs.numSegments - 1 DO
    WriteString("  "); WriteCard(i, 3); WriteString("  ");
    PrintReal(segs.starts[i], 2); WriteString("s - ");
    PrintReal(segs.ends[i], 2); WriteString("s  speaker ");
    WriteInt(segs.labels[i], 0); WriteLn
  END
END CmdDiarize;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdHarmonic;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
  winSamp, stepSamp, numFrames, i, frameStart: CARDINAL;
  hr, f0: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys harmonic <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;

  winSamp := TRUNC(WinSize * LFLOAT(sampleRate));
  stepSamp := TRUNC(WinStep * LFLOAT(sampleRate));
  IF numSamples < winSamp THEN
    WriteString("File too short"); WriteLn; FreeSignal(signal, numSamples); HALT
  END;
  numFrames := (numSamples - winSamp) DIV stepSamp + 1;

  WriteString("frame,harmonic_ratio,f0_hz"); WriteLn;
  FOR i := 0 TO numFrames - 1 DO
    frameStart := i * stepSamp;
    ComputeHarmonicF0(
      ADDRESS(LONGCARD(signal) + LONGCARD(frameStart) * LONGCARD(TSIZE(LONGREAL))),
      winSamp, sampleRate, hr, f0);
    WriteCard(i, 0); WriteString(",");
    PrintReal(hr, 6); WriteString(",");
    PrintReal(f0, 2); WriteLn
  END;

  FreeSignal(signal, numSamples)
END CmdHarmonic;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdKey;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; keyName: ARRAY [0..31] OF CHAR; confidence: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys key <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  DetectKey(signal, numSamples, sampleRate, keyName, confidence);
  FreeSignal(signal, numSamples);
  WriteString("Key: "); WriteString(keyName); WriteLn;
  WriteString("Confidence: "); PrintReal(confidence, 4); WriteLn
END CmdKey;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdOnsets;
VAR
  path, sensArg: PathBuf; signal: ADDRESS; numSamples, sampleRate, i: CARDINAL;
  ok: BOOLEAN; onsets: ARRAY [0..4095] OF LONGREAL;
  numOnsets: CARDINAL; sensitivity: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys onsets <file.wav> [sensitivity]"); WriteLn; HALT
  END;
  GetArg(2, path);
  sensitivity := 1.5;
  IF ArgCount() >= 4 THEN
    GetArg(3, sensArg); sensitivity := ParseReal(sensArg)
  END;
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  DetectOnsets(signal, numSamples, sampleRate, sensitivity,
               onsets, numOnsets);
  FreeSignal(signal, numSamples);
  WriteString("Onsets: "); WriteCard(numOnsets, 0); WriteLn;
  FOR i := 0 TO numOnsets - 1 DO
    WriteString("  "); PrintReal(onsets[i], 3); WriteString("s"); WriteLn
  END
END CmdOnsets;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdTrim;
VAR
  inPath, outPath, startArg, endArg: PathBuf;
  signal, trimmed: ADDRESS;
  numSamples, sampleRate, outN: CARDINAL;
  ok: BOOLEAN; startSec, endSec: LONGREAL;
BEGIN
  IF ArgCount() < 6 THEN
    WriteString("Usage: sndys trim <in> <out> <start_sec> <end_sec>"); WriteLn; HALT
  END;
  GetArg(2, inPath); GetArg(3, outPath);
  GetArg(4, startArg); GetArg(5, endArg);
  startSec := ParseReal(startArg); endSec := ParseReal(endArg);
  ReadAudio(inPath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading input"); WriteLn; HALT END;
  Trim(signal, numSamples, sampleRate, startSec, endSec, trimmed, outN);
  FreeSignal(signal, numSamples);
  WriteWav(outPath, trimmed, outN, sampleRate, 1, 16, ok);
  FreeProc(trimmed, outN);
  IF ok THEN
    WriteString("Trimmed "); PrintReal(startSec, 2);
    WriteString("s-"); PrintReal(endSec, 2);
    WriteString("s -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdTrim;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdMix;
VAR
  pathA, pathB, outPath, ratioArg: PathBuf;
  sigA, sigB, mixed: ADDRESS;
  nA, nB, srA, srB, outN: CARDINAL;
  ok1, ok2, ok: BOOLEAN; ratio: LONGREAL;
BEGIN
  IF ArgCount() < 5 THEN
    WriteString("Usage: sndys mix <a.wav> <b.wav> <out.wav> [ratio]"); WriteLn; HALT
  END;
  GetArg(2, pathA); GetArg(3, pathB); GetArg(4, outPath);
  ratio := 0.5;
  IF ArgCount() >= 6 THEN GetArg(5, ratioArg); ratio := ParseReal(ratioArg) END;
  ReadAudio(pathA, sigA, nA, srA, ok1);
  ReadAudio(pathB, sigB, nB, srB, ok2);
  IF (NOT ok1) OR (NOT ok2) THEN WriteString("Error reading inputs"); WriteLn; HALT END;
  Mix(sigA, nA, sigB, nB, ratio, mixed, outN);
  FreeSignal(sigA, nA); FreeSignal(sigB, nB);
  WriteWav(outPath, mixed, outN, srA, 1, 16, ok);
  FreeProc(mixed, outN);
  IF ok THEN WriteString("Mixed -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdMix;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdNormalize;
VAR
  inPath, outPath, peakArg: PathBuf;
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; peak: LONGREAL;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys normalize <in> <out> [peak]"); WriteLn; HALT
  END;
  GetArg(2, inPath); GetArg(3, outPath);
  peak := 0.95;
  IF ArgCount() >= 5 THEN GetArg(4, peakArg); peak := ParseReal(peakArg) END;
  ReadAudio(inPath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading input"); WriteLn; HALT END;
  Normalize(signal, numSamples, peak);
  WriteWav(outPath, signal, numSamples, sampleRate, 1, 16, ok);
  FreeSignal(signal, numSamples);
  IF ok THEN WriteString("Normalized -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdNormalize;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdFade;
VAR
  inPath, outPath, fadeInArg, fadeOutArg: PathBuf;
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; fadeInSec, fadeOutSec: LONGREAL;
BEGIN
  IF ArgCount() < 6 THEN
    WriteString("Usage: sndys fade <in> <out> <fadein_sec> <fadeout_sec>"); WriteLn; HALT
  END;
  GetArg(2, inPath); GetArg(3, outPath);
  GetArg(4, fadeInArg); GetArg(5, fadeOutArg);
  fadeInSec := ParseReal(fadeInArg); fadeOutSec := ParseReal(fadeOutArg);
  ReadAudio(inPath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading input"); WriteLn; HALT END;
  FadeIn(signal, numSamples, sampleRate, fadeInSec);
  FadeOut(signal, numSamples, sampleRate, fadeOutSec);
  WriteWav(outPath, signal, numSamples, sampleRate, 1, 16, ok);
  FreeSignal(signal, numSamples);
  IF ok THEN
    WriteString("Fades applied -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdFade;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdReverse;
VAR
  inPath, outPath: PathBuf;
  signal: ADDRESS; numSamples, sampleRate: CARDINAL; ok: BOOLEAN;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys reverse <in> <out>"); WriteLn; HALT
  END;
  GetArg(2, inPath); GetArg(3, outPath);
  ReadAudio(inPath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading input"); WriteLn; HALT END;
  Reverse(signal, numSamples);
  WriteWav(outPath, signal, numSamples, sampleRate, 1, 16, ok);
  FreeSignal(signal, numSamples);
  IF ok THEN WriteString("Reversed -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdReverse;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdGenerate;
VAR
  genType, outPath, arg3, arg4: PathBuf;
  output: ADDRESS; outN, sr: CARDINAL; ok: BOOLEAN;
  freq, dur, amp, freq2, bpm: LONGREAL;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage:"); WriteLn;
    WriteString("  sndys generate sine  <out> <freq> <dur> [amp]"); WriteLn;
    WriteString("  sndys generate chirp <out> <startHz> <endHz> <dur> [amp]"); WriteLn;
    WriteString("  sndys generate noise <out> <dur> [amp]"); WriteLn;
    WriteString("  sndys generate click <out> <bpm> <dur>"); WriteLn;
    HALT
  END;
  GetArg(2, genType); GetArg(3, outPath);
  sr := 44100; amp := 0.8;

  IF StrEq(genType, "sine") THEN
    IF ArgCount() < 6 THEN
      WriteString("Usage: sndys generate sine <out> <freq> <dur> [amp]"); WriteLn; HALT
    END;
    GetArg(4, arg3); freq := ParseReal(arg3);
    GetArg(5, arg4); dur := ParseReal(arg4);
    IF ArgCount() >= 7 THEN GetArg(6, arg3); amp := ParseReal(arg3) END;
    GenerateSine(freq, dur, sr, amp, output, outN);
    WriteWav(outPath, output, outN, sr, 1, 16, ok);
    FreeProc(output, outN);
    IF ok THEN
      PrintReal(freq, 1); WriteString("Hz sine, ");
      PrintReal(dur, 1); WriteString("s -> "); WriteString(outPath); WriteLn
    END

  ELSIF StrEq(genType, "chirp") THEN
    IF ArgCount() < 7 THEN
      WriteString("Usage: sndys generate chirp <out> <startHz> <endHz> <dur>"); WriteLn; HALT
    END;
    GetArg(4, arg3); freq := ParseReal(arg3);
    GetArg(5, arg4); freq2 := ParseReal(arg4);
    GetArg(6, arg3); dur := ParseReal(arg3);
    GenerateChirp(freq, freq2, dur, sr, amp, output, outN);
    WriteWav(outPath, output, outN, sr, 1, 16, ok);
    FreeProc(output, outN);
    IF ok THEN
      PrintReal(freq, 0); WriteString("-"); PrintReal(freq2, 0);
      WriteString("Hz chirp -> "); WriteString(outPath); WriteLn
    END

  ELSIF StrEq(genType, "noise") THEN
    IF ArgCount() < 5 THEN
      WriteString("Usage: sndys generate noise <out> <dur>"); WriteLn; HALT
    END;
    GetArg(4, arg3); dur := ParseReal(arg3);
    GenerateNoise(dur, sr, amp, output, outN);
    WriteWav(outPath, output, outN, sr, 1, 16, ok);
    FreeProc(output, outN);
    IF ok THEN
      PrintReal(dur, 1); WriteString("s noise -> "); WriteString(outPath); WriteLn
    END

  ELSIF StrEq(genType, "click") THEN
    IF ArgCount() < 6 THEN
      WriteString("Usage: sndys generate click <out> <bpm> <dur>"); WriteLn; HALT
    END;
    GetArg(4, arg3); bpm := ParseReal(arg3);
    GetArg(5, arg4); dur := ParseReal(arg4);
    GenerateClick(bpm, dur, sr, output, outN);
    WriteWav(outPath, output, outN, sr, 1, 16, ok);
    FreeProc(output, outN);
    IF ok THEN
      PrintReal(bpm, 0); WriteString(" BPM click track -> ");
      WriteString(outPath); WriteLn
    END

  ELSE
    WriteString("Unknown signal type: "); WriteString(genType); WriteLn
  END
END CmdGenerate;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdPitch;
VAR
  path: PathBuf; signal, pitches, ptimes: ADDRESS;
  numSamples, sampleRate, numFrames, i: CARDINAL;
  ok: BOOLEAN; pP, pT: RealPtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys pitch <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;
  TrackPitch(signal, numSamples, sampleRate, 5, pitches, ptimes, numFrames);
  FreeSignal(signal, numSamples);
  WriteString("time_sec,f0_hz"); WriteLn;
  FOR i := 0 TO numFrames - 1 DO
    pT := ElemR(ptimes, i);
    pP := ElemR(pitches, i);
    PrintReal(pT^, 3); WriteString(","); PrintReal(pP^, 2); WriteLn
  END;
  FreePitch(pitches, ptimes, numFrames)
END CmdPitch;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdTempoCurve;
VAR
  path, winArg, hopArg: PathBuf;
  signal, bpms, ttimes: ADDRESS;
  numSamples, sampleRate, numPoints, i: CARDINAL;
  ok: BOOLEAN; winSec, hopSec: LONGREAL;
  pB, pT: RealPtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys tempocurve <file.wav> [win_sec] [hop_sec]"); WriteLn; HALT
  END;
  GetArg(2, path);
  winSec := 10.0; hopSec := 5.0;
  IF ArgCount() >= 4 THEN GetArg(3, winArg); winSec := ParseReal(winArg) END;
  IF ArgCount() >= 5 THEN GetArg(4, hopArg); hopSec := ParseReal(hopArg) END;
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;
  ComputeTempoCurve(signal, numSamples, sampleRate, winSec, hopSec,
                     bpms, ttimes, numPoints);
  FreeSignal(signal, numSamples);
  WriteString("time_sec,bpm"); WriteLn;
  FOR i := 0 TO numPoints - 1 DO
    pT := ElemR(ttimes, i);
    pB := ElemR(bpms, i);
    PrintReal(pT^, 2); WriteString(","); PrintReal(pB^, 1); WriteLn
  END;
  FreeTempoCurve(bpms, ttimes, numPoints)
END CmdTempoCurve;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdConcat;
VAR
  pathA, pathB, outPath, xfArg: PathBuf;
  sigA, sigB, result: ADDRESS;
  nA, nB, srA, srB, outN: CARDINAL;
  ok1, ok2, ok: BOOLEAN; xfade: LONGREAL;
BEGIN
  IF ArgCount() < 5 THEN
    WriteString("Usage: sndys concat <a.wav> <b.wav> <out.wav> [crossfade_sec]"); WriteLn; HALT
  END;
  GetArg(2, pathA); GetArg(3, pathB); GetArg(4, outPath);
  xfade := 0.0;
  IF ArgCount() >= 6 THEN GetArg(5, xfArg); xfade := ParseReal(xfArg) END;
  ReadAudio(pathA, sigA, nA, srA, ok1);
  ReadAudio(pathB, sigB, nB, srB, ok2);
  IF (NOT ok1) OR (NOT ok2) THEN WriteString("Error reading inputs"); WriteLn; HALT END;
  AudioConcat.Concat(sigA, nA, sigB, nB, srA, xfade, result, outN);
  FreeSignal(sigA, nA); FreeSignal(sigB, nB);
  WriteWav(outPath, result, outN, srA, 1, 16, ok);
  AudioConcat.FreeConcat(result, outN);
  IF ok THEN
    WriteString("Concatenated -> "); WriteString(outPath);
    IF xfade > 0.0 THEN
      WriteString(" ("); PrintReal(xfade, 1); WriteString("s crossfade)")
    END;
    WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdConcat;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdLowpass;
VAR
  inPath, outPath, freqArg: PathBuf;
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; freq: LONGREAL;
BEGIN
  IF ArgCount() < 5 THEN
    WriteString("Usage: sndys lowpass <in> <out> <cutoff_hz>"); WriteLn; HALT
  END;
  GetArg(2, inPath); GetArg(3, outPath); GetArg(4, freqArg);
  freq := ParseReal(freqArg);
  ReadAudio(inPath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading input"); WriteLn; HALT END;
  Lowpass(signal, numSamples, sampleRate, freq);
  WriteWav(outPath, signal, numSamples, sampleRate, 1, 16, ok);
  FreeSignal(signal, numSamples);
  IF ok THEN
    WriteString("Lowpass "); PrintReal(freq, 0);
    WriteString("Hz -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdLowpass;

PROCEDURE CmdHighpass;
VAR
  inPath, outPath, freqArg: PathBuf;
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; freq: LONGREAL;
BEGIN
  IF ArgCount() < 5 THEN
    WriteString("Usage: sndys highpass <in> <out> <cutoff_hz>"); WriteLn; HALT
  END;
  GetArg(2, inPath); GetArg(3, outPath); GetArg(4, freqArg);
  freq := ParseReal(freqArg);
  ReadAudio(inPath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading input"); WriteLn; HALT END;
  Highpass(signal, numSamples, sampleRate, freq);
  WriteWav(outPath, signal, numSamples, sampleRate, 1, 16, ok);
  FreeSignal(signal, numSamples);
  IF ok THEN
    WriteString("Highpass "); PrintReal(freq, 0);
    WriteString("Hz -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdHighpass;

PROCEDURE CmdBandpass;
VAR
  inPath, outPath, loArg, hiArg: PathBuf;
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; loHz, hiHz: LONGREAL;
BEGIN
  IF ArgCount() < 6 THEN
    WriteString("Usage: sndys bandpass <in> <out> <lo_hz> <hi_hz>"); WriteLn; HALT
  END;
  GetArg(2, inPath); GetArg(3, outPath);
  GetArg(4, loArg); GetArg(5, hiArg);
  loHz := ParseReal(loArg); hiHz := ParseReal(hiArg);
  ReadAudio(inPath, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading input"); WriteLn; HALT END;
  Bandpass(signal, numSamples, sampleRate, loHz, hiHz);
  WriteWav(outPath, signal, numSamples, sampleRate, 1, 16, ok);
  FreeSignal(signal, numSamples);
  IF ok THEN
    WriteString("Bandpass "); PrintReal(loHz, 0);
    WriteString("-"); PrintReal(hiHz, 0);
    WriteString("Hz -> "); WriteString(outPath); WriteLn
  ELSE WriteString("Error writing output"); WriteLn END
END CmdBandpass;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdStats;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; st: StatsResult;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys stats <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  Analyze(signal, numSamples, sampleRate, st);
  FreeSignal(signal, numSamples);

  WriteString("File: "); WriteString(path); WriteLn;
  WriteString("  Duration:     "); PrintReal(st.duration, 2);
  WriteString("s"); WriteLn;
  WriteString("  Samples:      "); WriteCard(st.numSamples, 0); WriteLn;
  WriteString("  RMS level:    "); PrintReal(st.rmsLevel, 6); WriteLn;
  WriteString("  RMS (dBFS):   "); PrintReal(st.rmsDB, 2);
  WriteString(" dB"); WriteLn;
  WriteString("  Peak level:   "); PrintReal(st.peakLevel, 6); WriteLn;
  WriteString("  Peak (dBFS):  "); PrintReal(st.peakDB, 2);
  WriteString(" dB"); WriteLn;
  WriteString("  Crest factor: "); PrintReal(st.crestFactor, 2);
  WriteString(" dB"); WriteLn;
  WriteString("  DC offset:    "); PrintReal(st.dcOffset, 6); WriteLn;
  IF st.numClipped > 0 THEN
    WriteString("  Clipped:      "); WriteCard(st.numClipped, 0);
    WriteString(" samples (WARNING)"); WriteLn
  ELSE
    WriteString("  Clipped:      none"); WriteLn
  END
END CmdStats;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdWaveform;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys waveform <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error: could not read "); WriteString(path); WriteLn; HALT
  END;
  WriteString(path); WriteLn;
  DrawWaveform(signal, numSamples, 80, 20);
  FreeSignal(signal, numSamples)
END CmdWaveform;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdConvert;
VAR
  inPath, outPath, rateArg: PathBuf;
  ok: BOOLEAN;
  rate: CARDINAL;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys convert <input> <output.wav> [sample_rate]"); WriteLn;
    WriteString("  Converts MP3, OGG, FLAC, AAC, AIFF, etc. to WAV via ffmpeg."); WriteLn;
    HALT
  END;
  GetArg(2, inPath);
  GetArg(3, outPath);
  rate := 44100;
  IF ArgCount() >= 5 THEN
    GetArg(4, rateArg);
    rate := CARDINAL(ParseInt(rateArg))
  END;

  WriteString("Converting: "); WriteString(inPath); WriteLn;
  WriteString("  Output: "); WriteString(outPath);
  WriteString(" ("); WriteCard(rate, 0); WriteString(" Hz, mono, 16-bit)"); WriteLn;

  ConvertToWav(inPath, outPath, rate, ok);
  IF ok THEN
    WriteString("  Done"); WriteLn
  ELSE
    WriteString("  Error: conversion failed (is ffmpeg installed?)"); WriteLn
  END
END CmdConvert;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdChords;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate, i: CARDINAL;
  ok: BOOLEAN; chroma: ADDRESS; numFrames: CARDINAL;
  chords: ADDRESS; numChords: CARDINAL;
  prevName: ARRAY [0..15] OF CHAR;
  segStart: CARDINAL;
TYPE
  ChordPtr = POINTER TO ChordResult;
VAR
  cp: ChordPtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys chords <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;

  (* Detect per-frame chords from chromagram *)
  ComputeChromagram(signal, numSamples, sampleRate, 0.050, 0.025,
                     chroma, numFrames);
  FreeSignal(signal, numSamples);
  IF numFrames = 0 THEN WriteString("No frames"); WriteLn; HALT END;

  DetectChordSequence(chroma, numFrames, chords, numChords);
  FreeSpectro(chroma, numFrames * 12);

  WriteString("Chord sequence ("); WriteCard(numChords, 0);
  WriteString(" segments):"); WriteLn;

  FOR i := 0 TO numChords - 1 DO
    cp := ChordPtr(LONGCARD(chords) + LONGCARD(i) * LONGCARD(TSIZE(ChordResult)));
    WriteString("  "); WriteString(cp^.name);
    WriteString("  ("); PrintReal(cp^.confidence, 2); WriteString(")");
    WriteLn
  END;

  FreeChords(chords, numChords)
END CmdChords;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdNotes;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate, i: CARDINAL;
  ok: BOOLEAN; notes: ADDRESS; numNotes: CARDINAL;
TYPE
  NotePtr = POINTER TO NoteEvent;
VAR
  np: NotePtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys notes <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;

  Transcribe(signal, numSamples, sampleRate, notes, numNotes);
  FreeSignal(signal, numSamples);

  WriteString("Notes: "); WriteCard(numNotes, 0); WriteLn;
  WriteString("  Start     End      Note   MIDI  Hz"); WriteLn;

  FOR i := 0 TO numNotes - 1 DO
    np := NotePtr(LONGCARD(notes) + LONGCARD(i) * LONGCARD(TSIZE(NoteEvent)));
    WriteString("  ");
    PrintReal(np^.startSec, 3); WriteString("s  ");
    PrintReal(np^.endSec, 3); WriteString("s  ");
    WriteString(np^.noteName);
    WriteString("    "); WriteInt(np^.midiNote, 3);
    WriteString("   "); PrintReal(np^.pitchHz, 1);
    WriteLn
  END;

  FreeNotes(notes, numNotes)
END CmdNotes;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdTonnetz;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate, t, c: CARDINAL;
  ok: BOOLEAN; chroma: ADDRESS; numFrames: CARDINAL;
  chromaVec: ARRAY [0..11] OF LONGREAL;
  tonnetzVec: ARRAY [0..5] OF LONGREAL;
  p: RealPtr;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys tonnetz <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;
  ComputeChromagram(signal, numSamples, sampleRate, 0.050, 0.025,
                     chroma, numFrames);
  FreeSignal(signal, numSamples);
  IF numFrames = 0 THEN WriteString("No frames"); WriteLn; HALT END;

  WriteString("frame,fifths_y,fifths_x,min3_y,min3_x,maj3_y,maj3_x"); WriteLn;
  FOR t := 0 TO numFrames - 1 DO
    FOR c := 0 TO 11 DO
      p := ElemR(chroma, t * 12 + c);
      chromaVec[c] := p^
    END;
    ComputeTonnetz(chromaVec, tonnetzVec);
    WriteCard(t, 0);
    FOR c := 0 TO 5 DO
      WriteString(","); PrintReal(tonnetzVec[c], 6)
    END;
    WriteLn
  END;
  FreeSpectro(chroma, numFrames * 12)
END CmdTonnetz;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdVoice;
VAR
  path: PathBuf; signal, pitches, ptimes: ADDRESS;
  numSamples, sampleRate, numFrames: CARDINAL;
  ok: BOOLEAN;
  f1, f2, f3, jit, shim, hnr: LONGREAL;
  winSamp: CARDINAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys voice <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;

  WriteString("Voice analysis: "); WriteString(path); WriteLn;
  WriteLn;

  (* Formants from first voiced frame *)
  winSamp := TRUNC(0.030 * LFLOAT(sampleRate));
  IF winSamp > numSamples THEN winSamp := numSamples END;
  ComputeFormants(signal, winSamp, sampleRate, f1, f2, f3);
  WriteString("  Formants (first frame):"); WriteLn;
  WriteString("    F1: "); PrintReal(f1, 1); WriteString(" Hz"); WriteLn;
  WriteString("    F2: "); PrintReal(f2, 1); WriteString(" Hz"); WriteLn;
  WriteString("    F3: "); PrintReal(f3, 1); WriteString(" Hz"); WriteLn;
  WriteLn;

  (* HNR *)
  hnr := ComputeHNR(signal, numSamples, sampleRate);
  WriteString("  HNR: "); PrintReal(hnr, 2); WriteString(" dB"); WriteLn;
  WriteLn;

  (* Jitter and shimmer need pitch track *)
  TrackPitch(signal, numSamples, sampleRate, 5, pitches, ptimes, numFrames);

  jit := ComputeJitter(pitches, numFrames);
  WriteString("  Jitter: "); PrintReal(jit * 100.0, 4);
  WriteString("%"); WriteLn;

  shim := ComputeShimmer(signal, numSamples, sampleRate, pitches, numFrames);
  WriteString("  Shimmer: "); PrintReal(shim * 100.0, 4);
  WriteString("%"); WriteLn;

  FreePitch(pitches, ptimes, numFrames);
  FreeSignal(signal, numSamples)
END CmdVoice;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdFlatness;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; spectro: ADDRESS; numFrames, numBins, t: CARDINAL;
  flat: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys flatness <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;
  ComputeSpectrogram(signal, numSamples, sampleRate, 0.050, 0.025,
                      spectro, numFrames, numBins);
  FreeSignal(signal, numSamples);
  IF numFrames = 0 THEN WriteString("No frames"); WriteLn; HALT END;

  WriteString("frame,flatness"); WriteLn;
  FOR t := 0 TO numFrames - 1 DO
    flat := SpectralFlatness(
      ADDRESS(LONGCARD(spectro) + LONGCARD(t) * LONGCARD(numBins) * LONGCARD(TSIZE(LONGREAL))),
      numBins);
    WriteCard(t, 0); WriteString(","); PrintReal(flat, 6); WriteLn
  END;
  FreeSpectro(spectro, numFrames * numBins)
END CmdFlatness;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdStability;
VAR
  path: PathBuf; signal, bpms, ttimes: ADDRESS;
  numSamples, sampleRate, numPoints: CARDINAL;
  ok: BOOLEAN; stab: LONGREAL;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys stability <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;

  ComputeTempoCurve(signal, numSamples, sampleRate, 10.0, 5.0,
                     bpms, ttimes, numPoints);
  FreeSignal(signal, numSamples);

  stab := TempoStability(bpms, numPoints);
  FreeTempoCurve(bpms, ttimes, numPoints);

  WriteString("Tempo stability: "); PrintReal(stab, 4); WriteLn;
  IF stab < 0.05 THEN
    WriteString("  -> Very steady tempo (metronome-like)")
  ELSIF stab < 0.15 THEN
    WriteString("  -> Stable tempo (typical studio recording)")
  ELSIF stab < 0.30 THEN
    WriteString("  -> Moderate variation (live performance)")
  ELSE
    WriteString("  -> Unstable tempo (rubato, free time)")
  END;
  WriteLn
END CmdStability;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdAnalyze;
VAR
  path: PathBuf; signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
  info: WavInfo; rawSamples: ADDRESS;
  st: StatsResult;
  bpm, ratio, confidence: LONGREAL;
  feats: ADDRESS; numFrames: CARDINAL;
  keyName: ARRAY [0..31] OF CHAR;
  segs: SegmentList;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys analyze <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);

  (* Info *)
  WriteString("=== "); WriteString(path); WriteString(" ==="); WriteLn;
  WriteLn;
  ReadWav(path, info, rawSamples, ok);
  IF NOT ok THEN WriteString("Error reading file"); WriteLn; HALT END;
  WriteString("Format:     "); WriteCard(info.sampleRate, 0);
  WriteString(" Hz, "); WriteCard(info.numChannels, 0);
  WriteString(" ch, "); WriteCard(info.bitsPerSample, 0);
  WriteString("-bit"); WriteLn;
  WriteString("Duration:   "); PrintReal(GetDuration(info), 2);
  WriteString("s ("); WriteCard(info.numSamples, 0);
  WriteString(" samples)"); WriteLn;
  FreeWav(rawSamples, info.numSamples * info.numChannels);
  WriteLn;

  (* Stats *)
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("Error reading audio"); WriteLn; HALT END;

  Analyze(signal, numSamples, sampleRate, st);
  WriteString("RMS:        "); PrintReal(st.rmsDB, 2);
  WriteString(" dBFS"); WriteLn;
  WriteString("Peak:       "); PrintReal(st.peakDB, 2);
  WriteString(" dBFS"); WriteLn;
  WriteString("Crest:      "); PrintReal(st.crestFactor, 2);
  WriteString(" dB"); WriteLn;
  WriteString("DC offset:  "); PrintReal(st.dcOffset, 6); WriteLn;
  IF st.numClipped > 0 THEN
    WriteString("Clipping:   "); WriteCard(st.numClipped, 0);
    WriteString(" samples"); WriteLn
  END;
  WriteLn;

  (* Key *)
  DetectKey(signal, numSamples, sampleRate, keyName, confidence);
  WriteString("Key:        "); WriteString(keyName);
  WriteString(" ("); PrintReal(confidence, 2); WriteString(")"); WriteLn;

  (* BPM *)
  ExtractFast(signal, numSamples, sampleRate, WinSize, WinStep,
              feats, numFrames, ok);
  IF ok THEN
    BeatExtract(feats, numFrames, NumFeatures, WinStep, bpm, ratio);
    WriteString("BPM:        "); PrintReal(bpm, 1);
    WriteString(" ("); WriteCard(TRUNC(ratio * 100.0), 0);
    WriteString("% confidence)"); WriteLn;
    FreeFeatures(feats, numFrames)
  END;

  (* Silence *)
  RemoveSilence(signal, numSamples, sampleRate, 0.05, 0.3, segs);
  WriteString("Activity:   "); WriteCard(segs.numSegments, 0);
  WriteString(" non-silent segments"); WriteLn;

  FreeSignal(signal, numSamples)
END CmdAnalyze;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdBatch;
VAR
  subCmd, dirPath, filePath, fileName: PathBuf;
  dirBuf: ARRAY [0..32767] OF CHAR;
  listLen: INTEGER;
  pos, nameStart, i, fileCount: CARDINAL;
  slash: ARRAY [0..1] OF CHAR;
  dirLen: INTEGER;
BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: sndys batch <command> <directory>"); WriteLn;
    WriteString("  Runs the given command on every WAV file in the directory."); WriteLn;
    WriteString("  Example: sndys batch beats music/"); WriteLn;
    HALT
  END;
  GetArg(2, subCmd);
  GetArg(3, dirPath);

  listLen := m2sys_list_dir(ADR(dirPath), ADR(dirBuf), 32768);
  IF listLen <= 0 THEN
    WriteString("No files found in "); WriteString(dirPath); WriteLn;
    HALT
  END;

  fileCount := 0;
  pos := 0;
  WHILE pos < CARDINAL(listLen) DO
    nameStart := pos;
    WHILE (pos < CARDINAL(listLen)) AND (dirBuf[pos] # 12C) DO
      INC(pos)
    END;

    IF pos > nameStart THEN
      (* Extract filename *)
      FOR i := 0 TO pos - nameStart - 1 DO
        fileName[i] := dirBuf[nameStart + i]
      END;
      fileName[pos - nameStart] := 0C;

      (* Check if .wav *)
      IF IsWavFile(fileName) THEN
        (* Build full path: dirPath + "/" + fileName *)
        Assign(dirPath, filePath);
        dirLen := Length(filePath);
        IF (dirLen > 0) AND (filePath[dirLen - 1] # '/') THEN
          slash[0] := '/'; slash[1] := 0C;
          Concat(filePath, slash, filePath)
        END;
        Concat(filePath, fileName, filePath);

        (* Print separator *)
        IF fileCount > 0 THEN WriteLn END;
        WriteString("--- "); WriteString(fileName); WriteString(" ---"); WriteLn;

        (* Re-invoke ourselves by simulating the command.
           We can't actually recurse into the dispatch, so we
           just handle the common analysis commands inline. *)
        IF StrEq(subCmd, "beats") THEN
          (* Inline beats *)
          CmdBeatsFile(filePath)
        ELSIF StrEq(subCmd, "key") THEN
          CmdKeyFile(filePath)
        ELSIF StrEq(subCmd, "stats") THEN
          CmdStatsFile(filePath)
        ELSIF StrEq(subCmd, "analyze") THEN
          CmdAnalyzeFile(filePath)
        ELSE
          WriteString("  (batch not supported for '");
          WriteString(subCmd); WriteString("')"); WriteLn
        END;

        INC(fileCount)
      END
    END;
    INC(pos)
  END;

  WriteLn;
  WriteString("Processed "); WriteCard(fileCount, 0);
  WriteString(" files"); WriteLn
END CmdBatch;

(* Batch helper procedures — take a path directly *)

PROCEDURE CmdBeatsFile(path: ARRAY OF CHAR);
VAR
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; feats: ADDRESS; numFrames: CARDINAL;
  bpm, ratio: LONGREAL;
BEGIN
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("  Error reading file"); WriteLn; RETURN END;
  ExtractFast(signal, numSamples, sampleRate, WinSize, WinStep,
              feats, numFrames, ok);
  IF ok THEN
    BeatExtract(feats, numFrames, NumFeatures, WinStep, bpm, ratio);
    WriteString("  BPM: "); PrintReal(bpm, 1);
    WriteString("  ("); WriteCard(TRUNC(ratio * 100.0), 0);
    WriteString("%)"); WriteLn;
    FreeFeatures(feats, numFrames)
  END;
  FreeSignal(signal, numSamples)
END CmdBeatsFile;

PROCEDURE CmdKeyFile(path: ARRAY OF CHAR);
VAR
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; keyName: ARRAY [0..31] OF CHAR; confidence: LONGREAL;
BEGIN
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("  Error reading file"); WriteLn; RETURN END;
  DetectKey(signal, numSamples, sampleRate, keyName, confidence);
  WriteString("  Key: "); WriteString(keyName);
  WriteString("  ("); PrintReal(confidence, 2); WriteString(")"); WriteLn;
  FreeSignal(signal, numSamples)
END CmdKeyFile;

PROCEDURE CmdStatsFile(path: ARRAY OF CHAR);
VAR
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; st: StatsResult;
BEGIN
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("  Error reading file"); WriteLn; RETURN END;
  Analyze(signal, numSamples, sampleRate, st);
  WriteString("  RMS: "); PrintReal(st.rmsDB, 2);
  WriteString(" dBFS  Peak: "); PrintReal(st.peakDB, 2);
  WriteString(" dBFS  Crest: "); PrintReal(st.crestFactor, 2);
  WriteString(" dB"); WriteLn;
  FreeSignal(signal, numSamples)
END CmdStatsFile;

PROCEDURE CmdAnalyzeFile(path: ARRAY OF CHAR);
VAR
  signal: ADDRESS; numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN; st: StatsResult;
  bpm, ratio, confidence: LONGREAL;
  feats: ADDRESS; numFrames: CARDINAL;
  keyName: ARRAY [0..31] OF CHAR;
BEGIN
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN WriteString("  Error reading file"); WriteLn; RETURN END;
  Analyze(signal, numSamples, sampleRate, st);
  WriteString("  RMS: "); PrintReal(st.rmsDB, 2); WriteString(" dBFS");
  WriteString("  Peak: "); PrintReal(st.peakDB, 2); WriteString(" dBFS"); WriteLn;
  DetectKey(signal, numSamples, sampleRate, keyName, confidence);
  WriteString("  Key: "); WriteString(keyName); WriteLn;
  ExtractFast(signal, numSamples, sampleRate, WinSize, WinStep,
              feats, numFrames, ok);
  IF ok THEN
    BeatExtract(feats, numFrames, NumFeatures, WinStep, bpm, ratio);
    WriteString("  BPM: "); PrintReal(bpm, 1); WriteLn;
    FreeFeatures(feats, numFrames)
  END;
  FreeSignal(signal, numSamples)
END CmdAnalyzeFile;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdVersion;
BEGIN
  WriteString("sndys 0.1.0"); WriteLn;
  WriteString("Audio analysis toolkit — pure Modula-2"); WriteLn;
  WriteString("Built with mx (https://github.com/fitzee/mx)"); WriteLn
END CmdVersion;

(* ════════════════════════════════════════════════════ *)

PROCEDURE CmdPlay;
CONST
  ChunkFrames = 4096;       (* feed 4K frames at a time *)
  MaxQueueBytes = 65536;    (* keep ~64KB queued ahead = ~0.3s at 48kHz F32 *)
VAR
  path: PathBuf;
  signal: ADDRESS;
  numSamples, sampleRate: CARDINAL;
  ok: BOOLEAN;
  dev: DeviceID;
  spec: AudioSpec;
  totalFrames, offset, chunk: CARDINAL;
  durSec: CARDINAL;
  stopped: BOOLEAN;
BEGIN
  IF ArgCount() < 3 THEN
    WriteString("Usage: sndys play <file.wav>"); WriteLn; HALT
  END;
  GetArg(2, path);

  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    WriteString("Error reading "); WriteString(path); WriteLn; HALT
  END;

  IF NOT InitAudio() THEN
    WriteString("Error: SDL audio init failed"); WriteLn;
    FreeSignal(signal, numSamples); HALT
  END;

  dev := OpenDevice(sampleRate, 1, FormatF32, 2048);
  IF dev = 0 THEN
    WriteString("Error: could not open audio device"); WriteLn;
    QuitAudio; FreeSignal(signal, numSamples); HALT
  END;

  GetObtainedSpec(spec);
  durSec := numSamples DIV sampleRate;

  WriteString("Playing: "); WriteString(path); WriteLn;
  WriteString("  "); WriteCard(sampleRate, 0); WriteString(" Hz, ");
  WriteCard(durSec, 0); WriteString("s  (press any key to stop)"); WriteLn;

  totalFrames := numSamples;
  offset := 0;
  stopped := FALSE;

  ResumeDevice(dev);
  RawMode;

  (* Stream: feed small chunks, check for keypress between them *)
  WHILE (offset < totalFrames) AND (NOT stopped) DO
    IF KeyPressed() THEN
      stopped := TRUE
    ELSIF GetQueuedBytes(dev) < MaxQueueBytes THEN
      chunk := totalFrames - offset;
      IF chunk > ChunkFrames THEN chunk := ChunkFrames END;
      ok := QueueSamples(dev, ADDRESS(LONGCARD(signal)
            + LONGCARD(offset) * LONGCARD(TSIZE(LONGREAL))),
            chunk, 1);
      offset := offset + chunk
    ELSE
      Delay(10)
    END
  END;

  (* If not stopped, wait for remaining queue to drain *)
  IF NOT stopped THEN
    WHILE GetQueuedBytes(dev) > 0 DO
      IF KeyPressed() THEN stopped := TRUE END;
      IF NOT stopped THEN Delay(10) END
    END;
    IF NOT stopped THEN Delay(50) END
  END;

  IF stopped THEN
    PauseDevice(dev);
    ClearQueued(dev);
    WriteLn; WriteString("Stopped."); WriteLn
  END;

  RestoreMode;
  CloseDevice(dev);
  QuitAudio;
  FreeSignal(signal, numSamples)
END CmdPlay;

BEGIN
  IF ArgCount() < 2 THEN
    PrintUsage; HALT
  END;

  GetArg(1, cmd);

  IF StrEq(cmd, "info") THEN CmdInfo
  ELSIF StrEq(cmd, "spectrum") THEN CmdSpectrum
  ELSIF StrEq(cmd, "features") THEN CmdFeatures
  ELSIF StrEq(cmd, "beats") THEN CmdBeats
  ELSIF StrEq(cmd, "silence") THEN CmdSilence
  ELSIF StrEq(cmd, "midstats") THEN CmdMidstats
  ELSIF StrEq(cmd, "compare") THEN CmdCompare
  ELSIF StrEq(cmd, "train") THEN CmdTrain
  ELSIF StrEq(cmd, "predict") THEN CmdPredict
  ELSIF StrEq(cmd, "segment") THEN CmdSegment
  ELSIF StrEq(cmd, "downsample") THEN CmdDownsample
  ELSIF StrEq(cmd, "mono") THEN CmdMono
  ELSIF StrEq(cmd, "spectrogram") THEN CmdSpectrogram
  ELSIF StrEq(cmd, "chromagram") THEN CmdChromagram
  ELSIF StrEq(cmd, "thumbnail") THEN CmdThumbnail
  ELSIF StrEq(cmd, "diarize") THEN CmdDiarize
  ELSIF StrEq(cmd, "harmonic") THEN CmdHarmonic
  ELSIF StrEq(cmd, "key") THEN CmdKey
  ELSIF StrEq(cmd, "onsets") THEN CmdOnsets
  ELSIF StrEq(cmd, "trim") THEN CmdTrim
  ELSIF StrEq(cmd, "mix") THEN CmdMix
  ELSIF StrEq(cmd, "normalize") THEN CmdNormalize
  ELSIF StrEq(cmd, "fade") THEN CmdFade
  ELSIF StrEq(cmd, "reverse") THEN CmdReverse
  ELSIF StrEq(cmd, "generate") THEN CmdGenerate
  ELSIF StrEq(cmd, "pitch") THEN CmdPitch
  ELSIF StrEq(cmd, "tempocurve") THEN CmdTempoCurve
  ELSIF StrEq(cmd, "concat") THEN CmdConcat
  ELSIF StrEq(cmd, "lowpass") THEN CmdLowpass
  ELSIF StrEq(cmd, "highpass") THEN CmdHighpass
  ELSIF StrEq(cmd, "bandpass") THEN CmdBandpass
  ELSIF StrEq(cmd, "stats") THEN CmdStats
  ELSIF StrEq(cmd, "waveform") THEN CmdWaveform
  ELSIF StrEq(cmd, "convert") THEN CmdConvert
  ELSIF StrEq(cmd, "chords") THEN CmdChords
  ELSIF StrEq(cmd, "notes") THEN CmdNotes
  ELSIF StrEq(cmd, "tonnetz") THEN CmdTonnetz
  ELSIF StrEq(cmd, "voice") THEN CmdVoice
  ELSIF StrEq(cmd, "flatness") THEN CmdFlatness
  ELSIF StrEq(cmd, "stability") THEN CmdStability
  ELSIF StrEq(cmd, "analyze") THEN CmdAnalyze
  ELSIF StrEq(cmd, "batch") THEN CmdBatch
  ELSIF StrEq(cmd, "play") THEN CmdPlay
  ELSIF StrEq(cmd, "version") THEN CmdVersion
  ELSE
    WriteString("Unknown command: "); WriteString(cmd); WriteLn;
    WriteLn;
    PrintUsage
  END
END Sndys.
