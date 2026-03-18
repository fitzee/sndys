IMPLEMENTATION MODULE Chords;
(* Chord detection via cosine similarity against 48 templates:
   12 roots x 4 types (major, minor, 7th, minor 7th). *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sqrt;
FROM Strings IMPORT Assign;

TYPE
  RealPtr = POINTER TO LONGREAL;
  ChordPtr = POINTER TO ChordResult;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END Elem;

PROCEDURE ChordElem(base: ADDRESS; i: CARDINAL): ChordPtr;
BEGIN
  RETURN ChordPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(ChordResult)))
END ChordElem;

(* Chord templates: 1 = note present, 0 = absent *)
(* Root position templates (root = C = index 0):
   Major:   0, 4, 7
   Minor:   0, 3, 7
   7th:     0, 4, 7, 10
   Minor7:  0, 3, 7, 10  *)

VAR
  majorTpl:  ARRAY [0..11] OF LONGREAL;
  minorTpl:  ARRAY [0..11] OF LONGREAL;
  dom7Tpl:   ARRAY [0..11] OF LONGREAL;
  min7Tpl:   ARRAY [0..11] OF LONGREAL;
  rootNames: ARRAY [0..11] OF ARRAY [0..3] OF CHAR;

PROCEDURE InitTemplates;
VAR i: CARDINAL;
BEGIN
  FOR i := 0 TO 11 DO
    majorTpl[i] := 0.0;
    minorTpl[i] := 0.0;
    dom7Tpl[i] := 0.0;
    min7Tpl[i] := 0.0
  END;

  (* Major: root, maj3, 5th *)
  majorTpl[0] := 1.0; majorTpl[4] := 1.0; majorTpl[7] := 1.0;

  (* Minor: root, min3, 5th *)
  minorTpl[0] := 1.0; minorTpl[3] := 1.0; minorTpl[7] := 1.0;

  (* Dominant 7th: root, maj3, 5th, min7 *)
  dom7Tpl[0] := 1.0; dom7Tpl[4] := 1.0;
  dom7Tpl[7] := 1.0; dom7Tpl[10] := 1.0;

  (* Minor 7th: root, min3, 5th, min7 *)
  min7Tpl[0] := 1.0; min7Tpl[3] := 1.0;
  min7Tpl[7] := 1.0; min7Tpl[10] := 1.0;

  (* Root names -- chroma order: C, C#, D, D#, E, F, F#, G, G#, A, A#, B *)
  Assign("C", rootNames[0]);
  Assign("C#", rootNames[1]);
  Assign("D", rootNames[2]);
  Assign("D#", rootNames[3]);
  Assign("E", rootNames[4]);
  Assign("F", rootNames[5]);
  Assign("F#", rootNames[6]);
  Assign("G", rootNames[7]);
  Assign("G#", rootNames[8]);
  Assign("A", rootNames[9]);
  Assign("A#", rootNames[10]);
  Assign("B", rootNames[11])
END InitTemplates;

(* Cosine similarity between two 12-element vectors *)
PROCEDURE CosineSim(VAR a, b: ARRAY OF LONGREAL): LONGREAL;
VAR
  i: CARDINAL;
  dotAB, normA, normB, denom: LONGREAL;
BEGIN
  dotAB := 0.0;
  normA := 0.0;
  normB := 0.0;
  FOR i := 0 TO 11 DO
    dotAB := dotAB + a[i] * b[i];
    normA := normA + a[i] * a[i];
    normB := normB + b[i] * b[i]
  END;
  denom := LFLOAT(sqrt(FLOAT(normA))) * LFLOAT(sqrt(FLOAT(normB)));
  IF denom < 1.0D-10 THEN RETURN 0.0 END;
  RETURN dotAB / denom
END CosineSim;

(* Rotate a template by shift semitones *)
PROCEDURE RotateTemplate(VAR src: ARRAY OF LONGREAL;
                          shift: CARDINAL;
                          VAR dst: ARRAY OF LONGREAL);
VAR i: CARDINAL;
BEGIN
  FOR i := 0 TO 11 DO
    dst[(i + shift) MOD 12] := src[i]
  END
END RotateTemplate;

(* Build chord name from root and type *)
PROCEDURE BuildName(root, chordType: CARDINAL;
                     VAR name: ARRAY OF CHAR);
VAR
  i, len: CARDINAL;
  suffix: ARRAY [0..7] OF CHAR;
BEGIN
  (* Copy root name *)
  i := 0;
  WHILE (i <= HIGH(rootNames[root])) AND (rootNames[root][i] # 0C) DO
    IF i <= HIGH(name) THEN
      name[i] := rootNames[root][i]
    END;
    INC(i)
  END;
  len := i;

  (* Determine suffix *)
  CASE chordType OF
    0: suffix[0] := 0C  (* major: no suffix *)
  | 1: Assign("m", suffix)
  | 2: Assign("7", suffix)
  | 3: Assign("m7", suffix)
  ELSE
    suffix[0] := 0C
  END;

  (* Append suffix *)
  i := 0;
  WHILE (i <= HIGH(suffix)) AND (suffix[i] # 0C) DO
    IF len <= HIGH(name) THEN
      name[len] := suffix[i];
      INC(len)
    END;
    INC(i)
  END;

  (* Null-terminate *)
  IF len <= HIGH(name) THEN
    name[len] := 0C
  END
END BuildName;

(* ── DetectChord ───────────────────────────────────── *)

PROCEDURE DetectChord(chroma: ARRAY OF LONGREAL;
                       VAR result: ChordResult);
VAR
  root, chordType: CARDINAL;
  rotated: ARRAY [0..11] OF LONGREAL;
  sim, bestSim: LONGREAL;
  bestRoot, bestType: CARDINAL;
BEGIN
  result.confidence := 0.0;
  result.root := 0;
  Assign("N", result.name);

  bestSim := -2.0;
  bestRoot := 0;
  bestType := 0;

  FOR root := 0 TO 11 DO
    FOR chordType := 0 TO 3 DO
      (* Rotate the appropriate template *)
      CASE chordType OF
        0: RotateTemplate(majorTpl, root, rotated)
      | 1: RotateTemplate(minorTpl, root, rotated)
      | 2: RotateTemplate(dom7Tpl, root, rotated)
      | 3: RotateTemplate(min7Tpl, root, rotated)
      END;

      sim := CosineSim(chroma, rotated);
      IF sim > bestSim THEN
        bestSim := sim;
        bestRoot := root;
        bestType := chordType
      END
    END
  END;

  result.confidence := bestSim;
  IF result.confidence < 0.0 THEN result.confidence := 0.0 END;
  result.root := bestRoot;
  BuildName(bestRoot, bestType, result.name)
END DetectChord;

(* ── DetectChordSequence ───────────────────────────── *)

PROCEDURE SameChord(VAR a, b: ChordResult): BOOLEAN;
VAR i: CARDINAL;
BEGIN
  FOR i := 0 TO 15 DO
    IF a.name[i] # b.name[i] THEN RETURN FALSE END;
    IF a.name[i] = 0C THEN RETURN TRUE END
  END;
  RETURN TRUE
END SameChord;

PROCEDURE DetectChordSequence(chromagram: ADDRESS;
                               numFrames: CARDINAL;
                               VAR chords: ADDRESS;
                               VAR numChords: CARDINAL);
VAR
  t, i: CARDINAL;
  chroma: ARRAY [0..11] OF LONGREAL;
  cur, prev: ChordResult;
  p: RealPtr;
  tmpBuf: ADDRESS;
  tmpPtr: ChordPtr;
  count: CARDINAL;
BEGIN
  chords := NIL;
  numChords := 0;

  IF numFrames = 0 THEN RETURN END;

  (* First pass: detect all chords into temp buffer *)
  ALLOCATE(tmpBuf, numFrames * TSIZE(ChordResult));
  count := 0;

  FOR t := 0 TO numFrames - 1 DO
    FOR i := 0 TO 11 DO
      p := Elem(chromagram, t * 12 + i);
      chroma[i] := p^
    END;

    DetectChord(chroma, cur);

    (* Merge with previous if same chord *)
    IF (count > 0) AND SameChord(cur, prev) THEN
      (* Skip -- merge into previous segment *)
    ELSE
      tmpPtr := ChordElem(tmpBuf, count);
      tmpPtr^ := cur;
      INC(count);
      prev := cur
    END
  END;

  IF count = 0 THEN
    DEALLOCATE(tmpBuf, numFrames * TSIZE(ChordResult));
    RETURN
  END;

  (* Copy to final allocation *)
  ALLOCATE(chords, count * TSIZE(ChordResult));
  FOR i := 0 TO count - 1 DO
    tmpPtr := ChordElem(tmpBuf, i);
    cur := tmpPtr^;
    tmpPtr := ChordElem(chords, i);
    tmpPtr^ := cur
  END;

  numChords := count;
  DEALLOCATE(tmpBuf, numFrames * TSIZE(ChordResult))
END DetectChordSequence;

(* ── FreeChords ────────────────────────────────────── *)

PROCEDURE FreeChords(VAR chords: ADDRESS; numChords: CARDINAL);
BEGIN
  IF chords # NIL THEN
    DEALLOCATE(chords, numChords * TSIZE(ChordResult));
    chords := NIL
  END
END FreeChords;

BEGIN
  InitTemplates
END Chords.
