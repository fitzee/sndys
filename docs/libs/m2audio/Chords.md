# Chords

The `Chords` module detects chords from chroma vectors by matching against major, minor, 7th, and minor 7th templates (12 roots x 4 types = 48 templates) using cosine similarity.

## Why Chords?

Chord detection is a core task in music information retrieval. Identifying the harmonic content of audio enables automatic lead-sheet generation, music transcription, harmonic analysis, and song structure segmentation. Template-based matching provides a lightweight, interpretable approach without requiring trained models.

## Types

```modula2
TYPE
  ChordResult = RECORD
    name: ARRAY [0..15] OF CHAR;
    confidence: LONGREAL;
    root: CARDINAL
  END;
```

A detected chord: `name` is the chord label (e.g., "C", "Am", "G7", "Dm7"), `confidence` is the cosine similarity score, and `root` is the pitch class (0..11, where 0 = C).

## Procedures

### DetectChord

```modula2
PROCEDURE DetectChord(chroma: ARRAY OF LONGREAL;
                       VAR result: ChordResult);
```

Match a single 12-element chroma vector against all 48 chord templates. Sets `result.name`, `result.confidence`, and `result.root` to the best match.

### DetectChordSequence

```modula2
PROCEDURE DetectChordSequence(chromagram: ADDRESS;
                               numFrames: CARDINAL;
                               VAR chords: ADDRESS;
                               VAR numChords: CARDINAL);
```

Detect chords across an entire chromagram (`numFrames` x 12 LONGREALs, row-major). Merges consecutive identical chords into segments. Allocates an array of `ChordResult` records. Caller must free with `FreeChords`.

### FreeChords

```modula2
PROCEDURE FreeChords(VAR chords: ADDRESS);
```

Deallocate a chord result array returned by `DetectChordSequence`.

```modula2
VAR r: ChordResult;
DetectChord(chroma, r);
(* r.name = "Am", r.confidence = 0.92, r.root = 9 *)
```
