IMPLEMENTATION MODULE NoteTranscribe;

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathUtil IMPORT Log2;
FROM Strings IMPORT Assign;
FROM Onset IMPORT DetectOnsets;
FROM PitchTrack IMPORT TrackPitch, FreePitch;

TYPE
  RealPtr = POINTER TO LONGREAL;
  NotePtr = POINTER TO NoteEvent;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

PROCEDURE NoteElem(base: ADDRESS; i: CARDINAL): NotePtr;
BEGIN
  RETURN NotePtr(LONGCARD(base) + LONGCARD(i * TSIZE(NoteEvent)))
END NoteElem;

(* ── HzToMidi ──────────────────────────────────────── *)

PROCEDURE HzToMidi(hz: LONGREAL): INTEGER;
VAR
  val: LONGREAL;
BEGIN
  IF hz <= 0.0 THEN RETURN 0 END;
  val := 69.0 + 12.0 * Log2(hz / 440.0);
  IF val >= 0.0 THEN
    RETURN TRUNC(val + 0.5)
  ELSE
    RETURN -TRUNC(-val + 0.5)
  END
END HzToMidi;

(* ── MidiToName ────────────────────────────────────── *)

PROCEDURE MidiToName(midi: INTEGER; VAR name: ARRAY OF CHAR);
VAR
  noteClass, octave: INTEGER;
  noteStr: ARRAY [0..3] OF CHAR;
  len: CARDINAL;
  negOct: BOOLEAN;
BEGIN
  (* Note class: 0=C, 1=C#, 2=D, ... 11=B *)
  noteClass := midi MOD 12;
  IF noteClass < 0 THEN noteClass := noteClass + 12 END;
  octave := (midi DIV 12) - 1;

  CASE noteClass OF
    0:  Assign("C", noteStr)
  | 1:  Assign("C#", noteStr)
  | 2:  Assign("D", noteStr)
  | 3:  Assign("D#", noteStr)
  | 4:  Assign("E", noteStr)
  | 5:  Assign("F", noteStr)
  | 6:  Assign("F#", noteStr)
  | 7:  Assign("G", noteStr)
  | 8:  Assign("G#", noteStr)
  | 9:  Assign("A", noteStr)
  | 10: Assign("A#", noteStr)
  | 11: Assign("B", noteStr)
  END;

  (* Copy note name *)
  len := 0;
  WHILE (len <= HIGH(noteStr)) AND (noteStr[len] # 0C) DO
    IF len <= HIGH(name) THEN
      name[len] := noteStr[len]
    END;
    INC(len)
  END;

  (* Append octave number *)
  negOct := FALSE;
  IF octave < 0 THEN
    negOct := TRUE;
    octave := -octave
  END;

  IF negOct THEN
    IF len <= HIGH(name) THEN
      name[len] := '-';
      INC(len)
    END
  END;

  IF octave >= 10 THEN
    IF len <= HIGH(name) THEN
      name[len] := CHR(ORD('0') + octave DIV 10);
      INC(len)
    END
  END;
  IF len <= HIGH(name) THEN
    name[len] := CHR(ORD('0') + octave MOD 10);
    INC(len)
  END;

  (* Null-terminate *)
  IF len <= HIGH(name) THEN
    name[len] := 0C
  END
END MidiToName;

(* ── Transcribe ────────────────────────────────────── *)

PROCEDURE Transcribe(signal: ADDRESS;
                      numSamples, sampleRate: CARDINAL;
                      VAR notes: ADDRESS;
                      VAR numNotes: CARDINAL);
VAR
  onsets: ARRAY [0..4095] OF LONGREAL;
  numOnsets: CARDINAL;
  pitches, times: ADDRESS;
  numPitchFrames: CARDINAL;
  i, j: CARDINAL;
  startSec, endSec, totalSec: LONGREAL;
  startFrame, endFrame: CARDINAL;
  pitchSum: LONGREAL;
  pitchCount: CARDINAL;
  avgPitch: LONGREAL;
  midi: INTEGER;
  p: RealPtr;
  pF0: LONGREAL;
  np: NotePtr;
  pitchStepSec: LONGREAL;
BEGIN
  notes := NIL;
  numNotes := 0;

  IF numSamples < 2 THEN RETURN END;

  totalSec := LFLOAT(numSamples) / LFLOAT(sampleRate);

  (* Step 1: Detect onsets *)
  DetectOnsets(signal, numSamples, sampleRate, 1.5, onsets, numOnsets);
  IF numOnsets = 0 THEN RETURN END;

  (* Step 2: Track pitch *)
  TrackPitch(signal, numSamples, sampleRate, 5, pitches, times, numPitchFrames);
  IF numPitchFrames = 0 THEN
    RETURN
  END;

  (* Pitch frame step size: 10ms as used in PitchTrack *)
  pitchStepSec := 0.010;

  (* Step 3: For each onset pair, compute average pitch *)
  ALLOCATE(notes, numOnsets * TSIZE(NoteEvent));

  FOR i := 0 TO numOnsets - 1 DO
    startSec := onsets[i];
    IF i < numOnsets - 1 THEN
      endSec := onsets[i + 1]
    ELSE
      endSec := totalSec
    END;

    (* Find pitch frames in [startSec, endSec) *)
    startFrame := TRUNC(startSec / pitchStepSec);
    endFrame := TRUNC(endSec / pitchStepSec);
    IF startFrame >= numPitchFrames THEN startFrame := numPitchFrames - 1 END;
    IF endFrame > numPitchFrames THEN endFrame := numPitchFrames END;

    (* Average voiced pitch in this segment *)
    pitchSum := 0.0;
    pitchCount := 0;
    FOR j := startFrame TO endFrame - 1 DO
      p := Elem(pitches, j);
      pF0 := p^;
      IF pF0 > 0.0 THEN
        pitchSum := pitchSum + pF0;
        INC(pitchCount)
      END
    END;

    np := NoteElem(notes, numNotes);

    IF pitchCount > 0 THEN
      avgPitch := pitchSum / LFLOAT(pitchCount);
      midi := HzToMidi(avgPitch);

      np^.startSec := startSec;
      np^.endSec := endSec;
      np^.pitchHz := avgPitch;
      np^.midiNote := midi;
      MidiToName(midi, np^.noteName);
      INC(numNotes)
    ELSE
      (* Unvoiced segment -- still record it with 0 pitch *)
      np^.startSec := startSec;
      np^.endSec := endSec;
      np^.pitchHz := 0.0;
      np^.midiNote := 0;
      Assign("--", np^.noteName);
      INC(numNotes)
    END
  END;

  FreePitch(pitches, times)
END Transcribe;

(* ── FreeNotes ─────────────────────────────────────── *)

PROCEDURE FreeNotes(VAR notes: ADDRESS);
BEGIN
  IF notes # NIL THEN
    DEALLOCATE(notes, 0);
    notes := NIL
  END
END FreeNotes;

END NoteTranscribe.
