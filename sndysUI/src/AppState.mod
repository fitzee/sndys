IMPLEMENTATION MODULE AppState;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Strings IMPORT Assign;
FROM AudioIO IMPORT ReadAudio, FreeSignal;
FROM AudioStats IMPORT Analyze;
FROM KeyDetect IMPORT DetectKey;
FROM ShortFeats IMPORT NumFeatures, ExtractFast, FreeFeatures;
FROM Beat IMPORT BeatExtract;
FROM Rhythm IMPORT BeatStrength;
FROM Spectro IMPORT ComputeSpectrogram, ComputeChromagram, FreeSpectro;
FROM PitchTrack IMPORT TrackPitch, FreePitch;
FROM Onset IMPORT DetectOnsets;
FROM Chords IMPORT DetectChordSequence, FreeChords;
FROM NoteTranscribe IMPORT Transcribe, FreeNotes;
FROM Harmonic IMPORT ComputeHarmonicF0;
FROM VoiceFeats IMPORT ComputeFormants, ComputeJitter, ComputeShimmer,
                       ComputeHNR;

CONST
  WinSize = 0.050;
  WinStep = 0.025;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

PROCEDURE Reset;
BEGIN
  fileLoaded := FALSE;
  signal := NIL;
  numSamples := 0;
  sampleRate := 0;
  selStart := 0;
  selEnd := 0;
  hasSelection := FALSE;
  statsValid := FALSE;
  keyValid := FALSE;
  bpmValid := FALSE;
  beatStrValid := FALSE;
  spectroValid := FALSE;
  spectroData := NIL;
  spectroFrames := 0;
  spectroBins := 0;
  chromaValid := FALSE;
  chromaData := NIL;
  chromaFrames := 0;
  featsValid := FALSE;
  featsData := NIL;
  featsFrames := 0;
  pitchValid := FALSE;
  pitchData := NIL;
  pitchTimes := NIL;
  pitchFrames := 0;
  onsetsValid := FALSE;
  numOnsets := 0;
  chordsValid := FALSE;
  chordsData := NIL;
  numChords := 0;
  notesValid := FALSE;
  notesData := NIL;
  numNotes := 0;
  harmonicValid := FALSE;
  voiceValid := FALSE;
  activeTab := 0;
  isPlaying := FALSE;
  needsRedraw := TRUE;
  onProgress := NIL;
  Assign("Ready", statusMsg)
END Reset;

PROCEDURE FreeAll;
BEGIN
  IF signal # NIL THEN FreeSignal(signal, numSamples); signal := NIL END;
  IF spectroData # NIL THEN
    FreeSpectro(spectroData, spectroFrames * spectroBins);
    spectroData := NIL
  END;
  IF chromaData # NIL THEN
    FreeSpectro(chromaData, chromaFrames * 12);
    chromaData := NIL
  END;
  IF featsData # NIL THEN
    FreeFeatures(featsData, featsFrames);
    featsData := NIL
  END;
  IF pitchData # NIL THEN
    FreePitch(pitchData, pitchTimes, pitchFrames);
    pitchData := NIL; pitchTimes := NIL
  END;
  IF chordsData # NIL THEN
    FreeChords(chordsData, numChords);
    chordsData := NIL
  END;
  IF notesData # NIL THEN
    FreeNotes(notesData, numNotes);
    notesData := NIL
  END;
  Reset
END FreeAll;

PROCEDURE LoadFile(path: ARRAY OF CHAR): BOOLEAN;
VAR ok: BOOLEAN;
BEGIN
  FreeAll;
  ReadAudio(path, signal, numSamples, sampleRate, ok);
  IF NOT ok THEN
    Assign("Error loading file", statusMsg);
    RETURN FALSE
  END;
  Assign(path, filePath);
  fileLoaded := TRUE;
  selStart := 0;
  selEnd := numSamples;
  hasSelection := FALSE;
  needsRedraw := TRUE;
  Assign("File loaded", statusMsg);
  RETURN TRUE
END LoadFile;

PROCEDURE SelectionStart(): CARDINAL;
BEGIN
  IF hasSelection THEN RETURN selStart END;
  RETURN 0
END SelectionStart;

PROCEDURE SelectionEnd(): CARDINAL;
BEGIN
  IF hasSelection THEN RETURN selEnd END;
  RETURN numSamples
END SelectionEnd;

PROCEDURE SelectionSamples(): CARDINAL;
BEGIN
  RETURN SelectionEnd() - SelectionStart()
END SelectionSamples;

PROCEDURE SelectionSignal(): ADDRESS;
BEGIN
  RETURN ADDRESS(LONGCARD(signal)
         + LONGCARD(SelectionStart()) * LONGCARD(TSIZE(LONGREAL)))
END SelectionSignal;

(* ── Analysis runners ──────────────────────────────── *)

PROCEDURE Step(msg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Assign(msg, statusMsg);
  IF onProgress # NIL THEN
    RETURN onProgress(msg)
  END;
  RETURN TRUE
END Step;

PROCEDURE RunOverviewAnalyses;
VAR
  feats: ADDRESS;
  nf: CARDINAL;
  ok: BOOLEAN;
  sig: ADDRESS;
  ns: CARDINAL;
BEGIN
  IF NOT fileLoaded THEN RETURN END;
  sig := SelectionSignal();
  ns := SelectionSamples();
  IF ns = 0 THEN RETURN END;

  IF NOT Step("Computing stats...") THEN RETURN END;
  Analyze(sig, ns, sampleRate, stats);
  statsValid := TRUE;

  IF NOT Step("Detecting key...") THEN RETURN END;
  DetectKey(sig, ns, sampleRate, keyName, keyConf);
  keyValid := TRUE;

  IF NOT Step("Estimating BPM...") THEN RETURN END;
  ExtractFast(sig, ns, sampleRate, WinSize, WinStep, feats, nf, ok);
  IF ok AND (nf > 4) THEN
    BeatExtract(feats, nf, NumFeatures, WinStep, bpmValue, bpmConf);
    bpmValid := TRUE;
    FreeFeatures(feats, nf)
  END;

  IF NOT Step("Computing beat strength...") THEN RETURN END;
  beatStrValue := BeatStrength(sig, ns, sampleRate);
  beatStrValid := TRUE;

  Assign("Analysis complete", statusMsg);
  needsRedraw := TRUE
END RunOverviewAnalyses;

PROCEDURE RunSpectralAnalyses;
VAR sig: ADDRESS; ns: CARDINAL; ok: BOOLEAN;
BEGIN
  IF NOT fileLoaded THEN RETURN END;
  sig := SelectionSignal();
  ns := SelectionSamples();
  IF ns = 0 THEN RETURN END;

  (* Free previous *)
  IF spectroData # NIL THEN
    FreeSpectro(spectroData, spectroFrames * spectroBins);
    spectroData := NIL
  END;
  IF chromaData # NIL THEN
    FreeSpectro(chromaData, chromaFrames * 12);
    chromaData := NIL
  END;
  IF featsData # NIL THEN
    FreeFeatures(featsData, featsFrames);
    featsData := NIL
  END;

  IF NOT Step("Computing spectrogram...") THEN RETURN END;
  ComputeSpectrogram(sig, ns, sampleRate, WinSize, WinStep,
                     spectroData, spectroFrames, spectroBins);
  spectroValid := spectroFrames > 0;

  IF NOT Step("Computing chromagram...") THEN RETURN END;
  ComputeChromagram(sig, ns, sampleRate, WinSize, WinStep,
                    chromaData, chromaFrames);
  chromaValid := chromaFrames > 0;

  IF NOT Step("Extracting features...") THEN RETURN END;
  ExtractFast(sig, ns, sampleRate, WinSize, WinStep,
              featsData, featsFrames, ok);
  featsValid := ok AND (featsFrames > 0);

  Assign("Spectral analysis complete", statusMsg);
  needsRedraw := TRUE
END RunSpectralAnalyses;

PROCEDURE RunTempoAnalyses;
VAR
  sig: ADDRESS; ns: CARDINAL;
  feats: ADDRESS; nf: CARDINAL;
  ok: BOOLEAN;
BEGIN
  IF NOT fileLoaded THEN RETURN END;
  sig := SelectionSignal();
  ns := SelectionSamples();
  IF ns = 0 THEN RETURN END;

  IF NOT bpmValid THEN
    IF NOT Step("Estimating BPM...") THEN RETURN END;
    ExtractFast(sig, ns, sampleRate, WinSize, WinStep, feats, nf, ok);
    IF ok AND (nf > 4) THEN
      BeatExtract(feats, nf, NumFeatures, WinStep, bpmValue, bpmConf);
      bpmValid := TRUE;
      FreeFeatures(feats, nf)
    END
  END;

  IF NOT beatStrValid THEN
    IF NOT Step("Computing beat strength...") THEN RETURN END;
    beatStrValue := BeatStrength(sig, ns, sampleRate);
    beatStrValid := TRUE
  END;

  IF NOT onsetsValid THEN
    IF NOT Step("Detecting onsets...") THEN RETURN END;
    DetectOnsets(sig, ns, sampleRate, 1.5, onsetTimes, numOnsets);
    onsetsValid := TRUE
  END;

  Assign("Tempo analysis complete", statusMsg);
  needsRedraw := TRUE
END RunTempoAnalyses;

PROCEDURE RunHarmonicAnalyses;
VAR
  sig: ADDRESS; ns: CARDINAL;
  winSamp: CARDINAL;
BEGIN
  IF NOT fileLoaded THEN RETURN END;
  sig := SelectionSignal();
  ns := SelectionSamples();
  IF ns = 0 THEN RETURN END;

  IF NOT pitchValid THEN
    IF NOT Step("Tracking pitch...") THEN RETURN END;
    TrackPitch(sig, ns, sampleRate, 5, pitchData, pitchTimes, pitchFrames);
    pitchValid := pitchFrames > 0
  END;

  IF NOT chordsValid THEN
    IF chromaData = NIL THEN
      IF NOT Step("Computing chromagram...") THEN RETURN END;
      ComputeChromagram(sig, ns, sampleRate, WinSize, WinStep,
                        chromaData, chromaFrames);
      chromaValid := chromaFrames > 0
    END;
    IF chromaValid THEN
      IF NOT Step("Detecting chords...") THEN RETURN END;
      DetectChordSequence(chromaData, chromaFrames, chordsData, numChords);
      chordsValid := numChords > 0
    END
  END;

  IF NOT notesValid THEN
    IF NOT Step("Transcribing notes...") THEN RETURN END;
    Transcribe(sig, ns, sampleRate, notesData, numNotes);
    notesValid := numNotes > 0
  END;

  IF NOT harmonicValid THEN
    IF NOT Step("Computing harmonic ratio...") THEN RETURN END;
    winSamp := TRUNC(WinSize * LFLOAT(sampleRate));
    IF ns >= winSamp THEN
      ComputeHarmonicF0(sig, winSamp, sampleRate,
                         harmonicRatio, harmonicF0);
      harmonicValid := TRUE
    END
  END;

  IF NOT voiceValid THEN
    IF NOT Step("Analyzing voice features...") THEN RETURN END;
    winSamp := TRUNC(WinSize * LFLOAT(sampleRate));
    IF ns >= winSamp THEN
      ComputeFormants(sig, winSamp, sampleRate,
                       voiceF1, voiceF2, voiceF3);
      IF pitchValid THEN
        voiceJitter := ComputeJitter(pitchData, pitchFrames);
        voiceShimmer := ComputeShimmer(sig, ns, sampleRate,
                                        pitchData, pitchFrames)
      ELSE
        voiceJitter := 0.0;
        voiceShimmer := 0.0
      END;
      voiceHNR := ComputeHNR(sig, ns, sampleRate);
      voiceValid := TRUE
    END
  END;

  Assign("Harmonic analysis complete", statusMsg);
  needsRedraw := TRUE
END RunHarmonicAnalyses;

PROCEDURE RunAllAnalyses;
BEGIN
  RunOverviewAnalyses;
  RunSpectralAnalyses;
  RunTempoAnalyses;
  RunHarmonicAnalyses
END RunAllAnalyses;

BEGIN
  Reset
END AppState.
