MODULE SndysUI;
(* sndysUI — Desktop audio analysis front-end for sndys.
   Built on m2gfx (SDL2), uses m2audio/m2wav for all DSP. *)

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Gfx IMPORT Init, InitFont, Quit, QuitFont,
                CreateWindow, DestroyWindow,
                CreateRenderer, DestroyRenderer, Present,
                GetWindowWidth, GetWindowHeight,
                Delay, UpdateLogicalSize,
                WIN_CENTERED, WIN_RESIZABLE, WIN_HIGHDPI,
                RENDER_ACCELERATED, RENDER_VSYNC;
FROM Canvas IMPORT SetColor, Clear, FillRect, DrawLine, DrawRect,
                   SetBlendMode, BLEND_ALPHA;
FROM Events IMPORT Poll, QUIT_EVENT, KEYDOWN, KEYUP, MOUSEDOWN, MOUSEUP,
                   MOUSEMOVE, WINDOW_EVENT, NONE,
                   KeyCode, MouseX, MouseY, MouseButton,
                   KEY_ESCAPE, KEY_SPACE, KEY_TAB,
                   BUTTON_LEFT, WEVT_RESIZED, WEVT_EXPOSED, WindowEvent;
FROM Font IMPORT TextWidth, Height;
FROM Strings IMPORT Assign, Length, Concat;
FROM Args IMPORT ArgCount, GetArg;
FROM MathUtil IMPORT FAbs;
FROM NoteTranscribe IMPORT NoteEvent;
FROM Chords IMPORT ChordResult;

IMPORT UI;
IMPORT WaveView;
IMPORT AppState;
IMPORT Playback;
FROM ShortFeats IMPORT FeatureName, NumFeatures;

CONST
  WinW     = 1200;
  WinH     = 800;
  ToolbarH = 36;
  TabBarH  = 30;
  StatusH  = 24;
  WaveH    = 180;
  Margin   = 8;
  BtnW     = 80;
  BtnH     = 28;
  NumTabs  = 5;

TYPE
  RealPtr = POINTER TO LONGREAL;
  NotePtr = POINTER TO NoteEvent;
  ChordPtr = POINTER TO ChordResult;

VAR
  win: ADDRESS;
  ren: ADDRESS;
  running: BOOLEAN;
  winW, winH: INTEGER;

  (* Mouse state *)
  mx, my: INTEGER;
  mouseDown: BOOLEAN;
  clicked: BOOLEAN;

  (* Waveform interaction *)
  dragging: BOOLEAN;
  dragStart: INTEGER;

  (* Tab labels *)
  tl0, tl1, tl2, tl3, tl4, tl5, tl6, tl7: ARRAY [0..15] OF CHAR;

  (* Playback *)
  playDev: Playback.DeviceID;

  (* Temp buffers for formatting *)
  buf: ARRAY [0..63] OF CHAR;
  buf2: ARRAY [0..63] OF CHAR;

  (* Progress modal state *)
  progressTick: CARDINAL;

(* ── Progress callback ─────────────────────────────────── *)
(* Called between analysis steps. Renders one frame showing the status
   message, polls for Escape to cancel. Returns TRUE to continue. *)

PROCEDURE RenderWithModal(msg: ARRAY OF CHAR);
(* Draw full UI frame with modal overlay on top, single Present.
   Pumps events twice and delays to force macOS compositor to display. *)
VAR dummy: INTEGER;
BEGIN
  winW := GetWindowWidth(win);
  winH := GetWindowHeight(win);
  UI.SetCol(ren, UI.colBg);
  Clear(ren);
  SetBlendMode(ren, BLEND_ALPHA);
  DrawToolbar;
  DrawWavePanel;
  UI.Panel(ren, 0, TabY(), winW, winH - TabY(), UI.colPanel);
  DrawStatusBar;
  INC(progressTick);
  UI.ModalOverlay(ren, winW, winH, msg, progressTick);
  Present(ren);
  (* macOS needs event pump + delay for compositor to actually show the frame *)
  dummy := Poll();
  dummy := Poll();
  Delay(16)
END RenderWithModal;

PROCEDURE OnProgress(msg: ARRAY OF CHAR): BOOLEAN;
VAR evType: INTEGER;
BEGIN
  Assign(msg, AppState.statusMsg);
  RenderWithModal(msg);

  (* Drain events, check for Escape *)
  LOOP
    evType := Poll();
    IF evType = NONE THEN EXIT END;
    IF evType = QUIT_EVENT THEN
      running := FALSE;
      RETURN FALSE
    END;
    IF (evType = KEYDOWN) AND (KeyCode() = KEY_ESCAPE) THEN
      Assign("Cancelled", AppState.statusMsg);
      RETURN FALSE
    END
  END;
  RETURN TRUE
END OnProgress;

(* ── Helpers ──────────────────────────────────────────── *)

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE NoteElem(base: ADDRESS; i: CARDINAL): NotePtr;
BEGIN
  RETURN NotePtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(NoteEvent)))
END NoteElem;

PROCEDURE ChordElem(base: ADDRESS; i: CARDINAL): ChordPtr;
BEGIN
  RETURN ChordPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(ChordResult)))
END ChordElem;

(* ── Layout coordinates ───────────────────────────────── *)

PROCEDURE WaveY(): INTEGER;
BEGIN RETURN ToolbarH END WaveY;

PROCEDURE TabY(): INTEGER;
BEGIN RETURN ToolbarH + WaveH END TabY;

PROCEDURE ContentY(): INTEGER;
BEGIN RETURN ToolbarH + WaveH + TabBarH END ContentY;

PROCEDURE ContentH(): INTEGER;
BEGIN RETURN winH - ContentY() - StatusH END ContentH;

PROCEDURE StatusY(): INTEGER;
BEGIN RETURN winH - StatusH END StatusY;

(* ── Playback control ─────────────────────────────────── *)

PROCEDURE StartPlayback;
VAR ok: BOOLEAN;
BEGIN
  IF NOT AppState.fileLoaded THEN RETURN END;
  IF AppState.isPlaying THEN RETURN END;

  IF NOT Playback.InitAudio() THEN RETURN END;
  playDev := Playback.OpenDevice(AppState.sampleRate, 1,
                                  Playback.FormatF32, 2048);
  IF playDev = 0 THEN
    Playback.QuitAudio;
    RETURN
  END;

  ok := Playback.QueueSamples(playDev,
          AppState.SelectionSignal(),
          AppState.SelectionSamples(), 1);
  Playback.ResumeDevice(playDev);
  AppState.isPlaying := TRUE;
  Assign("Playing...", AppState.statusMsg)
END StartPlayback;

PROCEDURE StopPlayback;
BEGIN
  IF NOT AppState.isPlaying THEN RETURN END;
  Playback.PauseDevice(playDev);
  Playback.ClearQueued(playDev);
  Playback.CloseDevice(playDev);
  Playback.QuitAudio;
  AppState.isPlaying := FALSE;
  Assign("Stopped", AppState.statusMsg)
END StopPlayback;

PROCEDURE UpdatePlayback;
BEGIN
  IF AppState.isPlaying THEN
    IF Playback.GetQueuedBytes(playDev) = 0 THEN
      StopPlayback;
      Assign("Playback complete", AppState.statusMsg)
    END
  END
END UpdatePlayback;

(* ── Draw Toolbar ─────────────────────────────────────── *)

PROCEDURE DrawToolbar;
VAR bx: INTEGER; label: ARRAY [0..15] OF CHAR;
BEGIN
  UI.Panel(ren, 0, 0, winW, ToolbarH, UI.colToolbar);

  bx := Margin;

  (* Open button *)
  IF UI.Button(ren, bx, 4, BtnW, BtnH, "Open", mx, my, clicked) THEN
    (* File dialog not available — use CLI arg or drag-drop *)
    Assign("Use: sndysUI <file.wav>", AppState.statusMsg)
  END;
  bx := bx + BtnW + 4;

  (* Play / Stop *)
  IF AppState.isPlaying THEN
    Assign("Stop", label)
  ELSE
    Assign("Play", label)
  END;
  IF UI.Button(ren, bx, 4, BtnW, BtnH, label, mx, my, clicked) THEN
    IF AppState.isPlaying THEN
      StopPlayback
    ELSE
      StartPlayback
    END
  END;
  bx := bx + BtnW + 4;

  (* Analyze *)
  IF UI.Button(ren, bx, 4, BtnW, BtnH, "Analyze", mx, my, clicked) THEN
    IF AppState.fileLoaded THEN
      AppState.RunAllAnalyses
    END
  END;
  bx := bx + BtnW + 4;

  (* Clear Selection *)
  IF AppState.hasSelection THEN
    IF UI.Button(ren, bx, 4, 100, BtnH, "Clear Sel", mx, my, clicked) THEN
      AppState.hasSelection := FALSE;
      AppState.selStart := 0;
      AppState.selEnd := AppState.numSamples;
      AppState.needsRedraw := TRUE
    END;
    bx := bx + 104
  END;

  (* File name on the right *)
  IF AppState.fileLoaded THEN
    UI.LabelSmall(ren, winW - TextWidth(UI.fontSmall, AppState.filePath) - Margin,
                  10, AppState.filePath, UI.colTextDim)
  END
END DrawToolbar;

(* ── Draw Waveform ────────────────────────────────────── *)

PROCEDURE DrawWavePanel;
VAR ss, se: CARDINAL;
BEGIN
  IF AppState.hasSelection THEN
    ss := AppState.selStart;
    se := AppState.selEnd
  ELSE
    ss := 0;
    se := 0
  END;

  IF AppState.fileLoaded THEN
    WaveView.Draw(ren, 0, WaveY(), winW, WaveH,
                  AppState.signal, AppState.numSamples, ss, se)
  ELSE
    UI.Panel(ren, 0, WaveY(), winW, WaveH, UI.colBg);
    UI.SetCol(ren, UI.colBorder);
    DrawRect(ren, 0, WaveY(), winW, WaveH);
    UI.Label(ren, winW DIV 2 - 80, WaveY() + WaveH DIV 2 - 8,
             "No audio loaded", UI.colTextDim)
  END
END DrawWavePanel;

(* ── Tab: Overview ────────────────────────────────────── *)

PROCEDURE DrawOverview;
VAR y, lh: INTEGER;
BEGIN
  y := ContentY() + Margin;
  lh := UI.lineH + 2;

  IF NOT AppState.fileLoaded THEN
    UI.Label(ren, Margin, y, "Load a file to begin analysis.", UI.colTextDim);
    RETURN
  END;

  UI.LabelBold(ren, Margin, y, "File Info", UI.colAccent);
  y := y + lh;

  Assign("  Samples: ", buf);
  UI.FmtCard(AppState.numSamples, buf2);
  Concat(buf, buf2, buf);
  UI.Label(ren, Margin, y, buf, UI.colText);
  y := y + lh;

  Assign("  Rate:    ", buf);
  UI.FmtCard(AppState.sampleRate, buf2);
  Concat(buf, buf2, buf);
  Concat(buf, " Hz", buf);
  UI.Label(ren, Margin, y, buf, UI.colText);
  y := y + lh;

  IF AppState.statsValid THEN
    Assign("  Duration: ", buf);
    UI.FmtReal(AppState.stats.duration, 2, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, "s", buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh;

    Assign("  RMS:  ", buf);
    UI.FmtReal(AppState.stats.rmsDB, 1, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " dBFS", buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh;

    Assign("  Peak: ", buf);
    UI.FmtReal(AppState.stats.peakDB, 1, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " dBFS", buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh;

    Assign("  Crest: ", buf);
    UI.FmtReal(AppState.stats.crestFactor, 1, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " dB", buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh + 4
  END;

  IF AppState.keyValid THEN
    UI.LabelBold(ren, Margin, y, "Key Detection", UI.colAccent);
    y := y + lh;
    Assign("  Key: ", buf);
    Concat(buf, AppState.keyName, buf);
    Assign(" (", buf2);
    Concat(buf, buf2, buf);
    UI.FmtReal(AppState.keyConf, 2, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, ")", buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh + 4
  END;

  IF AppState.bpmValid THEN
    UI.LabelBold(ren, Margin, y, "Tempo", UI.colAccent);
    y := y + lh;
    Assign("  BPM: ", buf);
    UI.FmtReal(AppState.bpmValue, 1, buf2);
    Concat(buf, buf2, buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh;

    Assign("  Confidence: ", buf);
    UI.FmtReal(AppState.bpmConf * 100.0, 0, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, "%", buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh
  END;

  IF AppState.beatStrValid THEN
    Assign("  Beat Strength: ", buf);
    UI.FmtReal(AppState.beatStrValue, 3, buf2);
    Concat(buf, buf2, buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh
  END;

  IF NOT AppState.statsValid THEN
    y := y + lh;
    UI.Label(ren, Margin, y, "Click [Analyze] to run analysis.", UI.colTextDim)
  END
END DrawOverview;

(* ── Tab: Spectrum ────────────────────────────────────── *)

PROCEDURE DrawSpectrumTab;
VAR vizH, vizY, chromaY: INTEGER;
BEGIN
  IF NOT AppState.fileLoaded THEN
    UI.Label(ren, Margin, ContentY() + Margin,
             "Load a file first.", UI.colTextDim);
    RETURN
  END;

  IF NOT AppState.spectroValid THEN
    IF UI.Button(ren, Margin, ContentY() + Margin, 140, BtnH,
                 "Compute Spectrum", mx, my, clicked) THEN
      AppState.RunSpectralAnalyses
    END;
    RETURN
  END;

  vizH := ContentH() DIV 2 - Margin;
  vizY := ContentY() + 4;

  UI.LabelSmall(ren, Margin, vizY, "Spectrogram", UI.colTextDim);
  WaveView.DrawSpectrogram(ren, Margin, vizY + UI.smallH,
                            winW - 2 * Margin, vizH - UI.smallH,
                            AppState.spectroData,
                            AppState.spectroFrames,
                            AppState.spectroBins);

  chromaY := vizY + vizH + 4;
  UI.LabelSmall(ren, Margin, chromaY, "Chromagram", UI.colTextDim);
  IF AppState.chromaValid THEN
    WaveView.DrawChromagram(ren, Margin, chromaY + UI.smallH,
                             winW - 2 * Margin, vizH - UI.smallH,
                             AppState.chromaData,
                             AppState.chromaFrames)
  END
END DrawSpectrumTab;

(* ── Tab: Tempo ───────────────────────────────────────── *)

PROCEDURE DrawTempoTab;
VAR y, lh, i: INTEGER;
BEGIN
  y := ContentY() + Margin;
  lh := UI.lineH + 2;

  IF NOT AppState.fileLoaded THEN
    UI.Label(ren, Margin, y, "Load a file first.", UI.colTextDim);
    RETURN
  END;

  IF NOT AppState.bpmValid THEN
    IF UI.Button(ren, Margin, y, 140, BtnH,
                 "Analyze Tempo", mx, my, clicked) THEN
      AppState.RunTempoAnalyses
    END;
    RETURN
  END;

  UI.LabelBold(ren, Margin, y, "Tempo / Beat Analysis", UI.colAccent);
  y := y + lh;

  Assign("BPM: ", buf);
  UI.FmtReal(AppState.bpmValue, 1, buf2);
  Concat(buf, buf2, buf);
  UI.Label(ren, Margin, y, buf, UI.colText);
  y := y + lh;

  Assign("Confidence: ", buf);
  UI.FmtReal(AppState.bpmConf * 100.0, 0, buf2);
  Concat(buf, buf2, buf);
  Concat(buf, "%", buf);
  UI.Label(ren, Margin, y, buf, UI.colText);
  y := y + lh;

  IF AppState.beatStrValid THEN
    Assign("Beat Strength: ", buf);
    UI.FmtReal(AppState.beatStrValue, 3, buf2);
    Concat(buf, buf2, buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh
  END;

  y := y + 4;

  IF AppState.onsetsValid THEN
    UI.LabelBold(ren, Margin, y, "Onsets", UI.colAccent);
    y := y + lh;

    Assign("Detected: ", buf);
    UI.FmtCard(AppState.numOnsets, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " onsets", buf);
    UI.Label(ren, Margin, y, buf, UI.colText);
    y := y + lh;

    (* Show first few onset times *)
    i := 0;
    WHILE (i < INTEGER(AppState.numOnsets)) AND (i < 20) AND
          (y < StatusY() - lh) DO
      Assign("  ", buf);
      UI.FmtReal(AppState.onsetTimes[i], 3, buf2);
      Concat(buf, buf2, buf);
      Concat(buf, "s", buf);
      UI.LabelSmall(ren, Margin + 8, y, buf, UI.colTextDim);
      y := y + UI.smallH;
      INC(i)
    END;
    IF INTEGER(AppState.numOnsets) > 20 THEN
      UI.LabelSmall(ren, Margin + 8, y, "  ...", UI.colTextDim)
    END
  END
END DrawTempoTab;

(* ── Tab: Harmonic ────────────────────────────────────── *)

PROCEDURE DrawHarmonicTab;
VAR y, lh, vizH, i: INTEGER;
    np: NotePtr;
    cp: ChordPtr;
BEGIN
  y := ContentY() + Margin;
  lh := UI.lineH + 2;

  IF NOT AppState.fileLoaded THEN
    UI.Label(ren, Margin, y, "Load a file first.", UI.colTextDim);
    RETURN
  END;

  IF NOT AppState.pitchValid THEN
    IF UI.Button(ren, Margin, y, 160, BtnH,
                 "Analyze Harmonic", mx, my, clicked) THEN
      AppState.RunHarmonicAnalyses
    END;
    RETURN
  END;

  (* Pitch contour visualization *)
  vizH := ContentH() DIV 3;
  UI.LabelSmall(ren, Margin, y, "Pitch Contour (F0)", UI.colTextDim);
  WaveView.DrawPitchContour(ren, Margin, y + UI.smallH,
                             winW DIV 2 - 2 * Margin, vizH - UI.smallH,
                             AppState.pitchData, AppState.pitchFrames);

  (* Right side: text results *)
  y := ContentY() + Margin;

  IF AppState.harmonicValid THEN
    UI.LabelSmall(ren, winW DIV 2 + Margin, y, "Harmonic", UI.colAccent);
    y := y + UI.smallH;
    Assign("F0: ", buf);
    UI.FmtReal(AppState.harmonicF0, 1, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " Hz", buf);
    UI.LabelSmall(ren, winW DIV 2 + Margin, y, buf, UI.colText);
    y := y + UI.smallH;
    Assign("Ratio: ", buf);
    UI.FmtReal(AppState.harmonicRatio, 3, buf2);
    Concat(buf, buf2, buf);
    UI.LabelSmall(ren, winW DIV 2 + Margin, y, buf, UI.colText);
    y := y + UI.smallH + 4
  END;

  IF AppState.voiceValid THEN
    UI.LabelSmall(ren, winW DIV 2 + Margin, y, "Voice", UI.colAccent);
    y := y + UI.smallH;
    Assign("F1: ", buf);
    UI.FmtReal(AppState.voiceF1, 0, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " Hz  ", buf);
    Assign("F2: ", buf2);
    Concat(buf, buf2, buf);
    UI.FmtReal(AppState.voiceF2, 0, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " Hz  ", buf);
    Assign("F3: ", buf2);
    Concat(buf, buf2, buf);
    UI.FmtReal(AppState.voiceF3, 0, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " Hz", buf);
    UI.LabelSmall(ren, winW DIV 2 + Margin, y, buf, UI.colText);
    y := y + UI.smallH;
    Assign("Jitter: ", buf);
    UI.FmtReal(AppState.voiceJitter * 100.0, 2, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, "%  Shimmer: ", buf);
    UI.FmtReal(AppState.voiceShimmer * 100.0, 2, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, "%  HNR: ", buf);
    UI.FmtReal(AppState.voiceHNR, 1, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " dB", buf);
    UI.LabelSmall(ren, winW DIV 2 + Margin, y, buf, UI.colText);
    y := y + UI.smallH + 4
  END;

  (* Chords — below pitch contour *)
  y := ContentY() + Margin + vizH + 4;

  IF AppState.chordsValid THEN
    UI.LabelBold(ren, Margin, y, "Chords", UI.colAccent);
    y := y + lh;
    i := 0;
    WHILE (i < INTEGER(AppState.numChords)) AND (i < 30) AND
          (y < StatusY() - UI.smallH) DO
      cp := ChordElem(AppState.chordsData, CARDINAL(i));
      Assign("  ", buf);
      Concat(buf, cp^.name, buf);
      Concat(buf, "  (", buf);
      UI.FmtReal(cp^.confidence, 2, buf2);
      Concat(buf, buf2, buf);
      Concat(buf, ")", buf);
      UI.LabelSmall(ren, Margin, y, buf, UI.colText);
      y := y + UI.smallH;
      INC(i)
    END
  END;

  (* Notes — right side lower *)
  y := ContentY() + Margin + vizH + 4;

  IF AppState.notesValid THEN
    UI.LabelBold(ren, winW DIV 2 + Margin, y, "Notes", UI.colAccent);
    y := y + lh;
    i := 0;
    WHILE (i < INTEGER(AppState.numNotes)) AND (i < 30) AND
          (y < StatusY() - UI.smallH) DO
      np := NoteElem(AppState.notesData, CARDINAL(i));
      UI.FmtReal(np^.startSec, 2, buf);
      Concat(buf, "s ", buf);
      Concat(buf, np^.noteName, buf);
      Assign(" (", buf2);
      Concat(buf, buf2, buf);
      UI.FmtReal(np^.pitchHz, 0, buf2);
      Concat(buf, buf2, buf);
      Concat(buf, " Hz)", buf);
      UI.LabelSmall(ren, winW DIV 2 + Margin, y, buf, UI.colText);
      y := y + UI.smallH;
      INC(i)
    END
  END
END DrawHarmonicTab;

(* ── Tab: Features ────────────────────────────────────── *)

PROCEDURE DrawFeaturesTab;
VAR y, lh, i: INTEGER; p: RealPtr;
    fname: ARRAY [0..63] OF CHAR;
BEGIN
  y := ContentY() + Margin;
  lh := UI.smallH;

  IF NOT AppState.fileLoaded THEN
    UI.Label(ren, Margin, y, "Load a file first.", UI.colTextDim);
    RETURN
  END;

  IF NOT AppState.featsValid THEN
    (* Extract features on demand *)
    IF UI.Button(ren, Margin, y, 160, BtnH,
                 "Extract Features", mx, my, clicked) THEN
      AppState.RunSpectralAnalyses
    END;
    RETURN
  END;

  UI.LabelBold(ren, Margin, y, "Short-Term Features (frame 0)", UI.colAccent);
  y := y + UI.lineH + 2;

  (* Show first frame's 34 features *)
  FOR i := 0 TO INTEGER(NumFeatures) - 1 DO
    IF y >= StatusY() - lh THEN RETURN END;

    FeatureName(CARDINAL(i), fname);
    p := ElemR(AppState.featsData, CARDINAL(i));
    UI.FmtReal(p^, 4, buf2);
    Assign("  ", buf);
    Concat(buf, fname, buf);
    Concat(buf, ": ", buf);
    Concat(buf, buf2, buf);
    UI.LabelSmall(ren, Margin, y, buf, UI.colText);
    y := y + lh
  END
END DrawFeaturesTab;

(* ── Draw Status Bar ──────────────────────────────────── *)

PROCEDURE DrawStatusBar;
VAR col: CARDINAL;
BEGIN
  UI.Panel(ren, 0, StatusY(), winW, StatusH, UI.colToolbar);
  (* Show analysis steps in accent color, normal status in dim *)
  IF (AppState.statusMsg[0] = 'C') AND (AppState.statusMsg[1] = 'o') AND
     (AppState.statusMsg[2] = 'm') THEN
    col := UI.colAccent  (* "Computing..." / "Com..." = active *)
  ELSIF (AppState.statusMsg[0] = 'E') AND (AppState.statusMsg[1] = 's') THEN
    col := UI.colAccent  (* "Estimating..." *)
  ELSIF (AppState.statusMsg[0] = 'D') AND (AppState.statusMsg[1] = 'e') AND
        (AppState.statusMsg[2] = 't') THEN
    col := UI.colAccent  (* "Detecting..." *)
  ELSIF (AppState.statusMsg[0] = 'T') AND (AppState.statusMsg[1] = 'r') AND
        (AppState.statusMsg[2] = 'a') THEN
    col := UI.colAccent  (* "Tracking..." / "Transcribing..." *)
  ELSIF (AppState.statusMsg[0] = 'A') AND (AppState.statusMsg[1] = 'n') AND
        (AppState.statusMsg[2] = 'a') THEN
    col := UI.colAccent  (* "Analyzing..." *)
  ELSIF (AppState.statusMsg[0] = 'E') AND (AppState.statusMsg[1] = 'x') THEN
    col := UI.colAccent  (* "Extracting..." *)
  ELSE
    col := UI.colTextDim
  END;
  UI.LabelSmall(ren, Margin, StatusY() + 4, AppState.statusMsg, col);
  IF col = UI.colAccent THEN
    UI.LabelSmall(ren, Margin + 300, StatusY() + 4,
                  "(press Esc to cancel)", UI.colTextDim)
  END;

  IF AppState.hasSelection THEN
    Assign("Selection: ", buf);
    UI.FmtCard(AppState.selStart, buf2);
    Concat(buf, buf2, buf);
    Concat(buf, " - ", buf);
    UI.FmtCard(AppState.selEnd, buf2);
    Concat(buf, buf2, buf);
    UI.LabelSmall(ren, winW DIV 2, StatusY() + 4, buf, UI.colTextDim)
  END;

  IF AppState.isPlaying THEN
    UI.LabelSmall(ren, winW - 80, StatusY() + 4, "Playing",
                  UI.colGreen)
  END
END DrawStatusBar;

(* ── Main render ──────────────────────────────────────── *)

PROCEDURE Render;
VAR newTab: CARDINAL;
BEGIN
  winW := GetWindowWidth(win);
  winH := GetWindowHeight(win);

  (* Background *)
  UI.SetCol(ren, UI.colBg);
  Clear(ren);

  SetBlendMode(ren, BLEND_ALPHA);

  DrawToolbar;
  DrawWavePanel;

  (* Tab bar *)
  newTab := UI.TabBar(ren, 0, TabY(), winW,
                       tl0, tl1, tl2, tl3, tl4, tl5, tl6, tl7,
                       NumTabs, AppState.activeTab,
                       mx, my, clicked);
  IF newTab # AppState.activeTab THEN
    AppState.activeTab := newTab;
    AppState.needsRedraw := TRUE
  END;

  (* Content area background *)
  UI.Panel(ren, 0, ContentY(), winW, ContentH(), UI.colPanel);

  (* Tab content *)
  CASE AppState.activeTab OF
    0: DrawOverview
  | 1: DrawSpectrumTab
  | 2: DrawTempoTab
  | 3: DrawHarmonicTab
  | 4: DrawFeaturesTab
  END;

  DrawStatusBar;

  Present(ren)
END Render;

(* ── Event handling ───────────────────────────────────── *)

PROCEDURE HandleEvents;
VAR
  evType: INTEGER;
  btn: INTEGER;
  sample: CARDINAL;
  tmp: CARDINAL;
BEGIN
  clicked := FALSE;

  LOOP
    evType := Poll();
    IF evType = NONE THEN EXIT END;

    IF evType = QUIT_EVENT THEN
      running := FALSE;
      EXIT
    END;

    IF evType = KEYDOWN THEN
      IF KeyCode() = KEY_ESCAPE THEN
        running := FALSE;
        EXIT
      END;
      IF KeyCode() = KEY_SPACE THEN
        IF AppState.isPlaying THEN StopPlayback
        ELSE StartPlayback END
      END;
      IF KeyCode() = KEY_TAB THEN
        AppState.activeTab := (AppState.activeTab + 1) MOD NumTabs;
        AppState.needsRedraw := TRUE
      END
    END;

    IF evType = MOUSEDOWN THEN
      mx := MouseX(); my := MouseY();
      btn := MouseButton();
      IF btn = BUTTON_LEFT THEN
        mouseDown := TRUE;
        clicked := TRUE;

        (* Start waveform drag *)
        IF (my >= WaveY()) AND (my < WaveY() + WaveH) AND
           AppState.fileLoaded THEN
          dragging := TRUE;
          dragStart := mx;
          sample := WaveView.PixelToSample(mx, 0, winW,
                                            AppState.numSamples);
          AppState.selStart := sample;
          AppState.selEnd := sample;
          AppState.hasSelection := FALSE
        END
      END
    END;

    IF evType = MOUSEUP THEN
      mx := MouseX(); my := MouseY();
      mouseDown := FALSE;
      IF dragging THEN
        dragging := FALSE;
        (* Finalize selection *)
        IF AppState.selStart # AppState.selEnd THEN
          IF AppState.selStart > AppState.selEnd THEN
            tmp := AppState.selStart;
            AppState.selStart := AppState.selEnd;
            AppState.selEnd := tmp
          END;
          AppState.hasSelection := TRUE;
          Assign("Selection set", AppState.statusMsg)
        ELSE
          AppState.hasSelection := FALSE
        END;
        AppState.needsRedraw := TRUE
      END
    END;

    IF evType = MOUSEMOVE THEN
      mx := MouseX(); my := MouseY();
      IF dragging AND AppState.fileLoaded THEN
        sample := WaveView.PixelToSample(mx, 0, winW,
                                          AppState.numSamples);
        AppState.selEnd := sample;
        AppState.needsRedraw := TRUE
      END
    END;

    IF evType = WINDOW_EVENT THEN
      IF WindowEvent() = WEVT_RESIZED THEN
        UpdateLogicalSize(ren, win);
        AppState.needsRedraw := TRUE
      ELSIF WindowEvent() = WEVT_EXPOSED THEN
        AppState.needsRedraw := TRUE
      END
    END
  END
END HandleEvents;

(* ── Main ─────────────────────────────────────────────── *)

VAR
  arg: ARRAY [0..255] OF CHAR;

BEGIN
  Assign("Overview", tl0);
  Assign("Spectrum", tl1);
  Assign("Tempo", tl2);
  Assign("Harmonic", tl3);
  Assign("Features", tl4);
  tl5[0] := 0C; tl6[0] := 0C; tl7[0] := 0C;

  IF NOT Init() THEN HALT END;
  IF NOT InitFont() THEN Quit; HALT END;

  UI.InitTheme;

  win := CreateWindow("sndys", WinW, WinH,
                       WIN_CENTERED + WIN_RESIZABLE + WIN_HIGHDPI);
  ren := CreateRenderer(win, RENDER_ACCELERATED + RENDER_VSYNC);
  UpdateLogicalSize(ren, win);

  (* Load fonts AFTER renderer exists — DpiScale() needs it *)
  IF NOT UI.LoadFonts() THEN
    DestroyRenderer(ren); DestroyWindow(win);
    QuitFont; Quit; HALT
  END;

  running := TRUE;
  mouseDown := FALSE;
  dragging := FALSE;
  mx := 0; my := 0;
  playDev := 0;

  AppState.Reset;
  AppState.onProgress := OnProgress;

  progressTick := 0;
  winW := GetWindowWidth(win);
  winH := GetWindowHeight(win);

  (* Load file from command line if provided *)
  IF ArgCount() >= 2 THEN
    GetArg(1, arg);
    RenderWithModal("Loading audio file...");
    IF AppState.LoadFile(arg) THEN
      AppState.RunOverviewAnalyses
    END
  END;

  (* Main loop *)
  WHILE running DO
    HandleEvents;
    UpdatePlayback;
    Render;
    Delay(16)  (* ~60 fps *)
  END;

  (* Cleanup *)
  IF AppState.isPlaying THEN StopPlayback END;
  AppState.FreeAll;
  UI.FreeFonts;
  DestroyRenderer(ren);
  DestroyWindow(win);
  QuitFont;
  Quit
END SndysUI.
