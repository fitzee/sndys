# NoteTranscribe

The `NoteTranscribe` module performs note-level transcription by combining onset detection with pitch tracking to produce a sequence of musical note events with start/end times, pitch, MIDI number, and note name.

## Why NoteTranscribe?

Note transcription bridges the gap between raw audio and symbolic music representation. It enables automatic sheet music generation, MIDI export, melodic analysis, and music search by converting a continuous audio signal into discrete note events.

## Types

```modula2
TYPE
  NoteEvent = RECORD
    startSec: LONGREAL;
    endSec: LONGREAL;
    pitchHz: LONGREAL;
    midiNote: INTEGER;
    noteName: ARRAY [0..7] OF CHAR
  END;
```

A single detected note with timing, frequency, MIDI note number (60 = C4), and name string (e.g., "A4", "C#4").

## Procedures

### Transcribe

```modula2
PROCEDURE Transcribe(signal: ADDRESS;
                      numSamples, sampleRate: CARDINAL;
                      VAR notes: ADDRESS;
                      VAR numNotes: CARDINAL);
```

Detect notes in a mono audio signal. The pipeline: (1) detect onsets, (2) track pitch between consecutive onsets, (3) convert to note events. Allocates the `notes` array; caller must free with `FreeNotes`.

### HzToMidi

```modula2
PROCEDURE HzToMidi(hz: LONGREAL): INTEGER;
```

Convert a frequency in Hz to a MIDI note number: `69 + 12 * log2(hz / 440)`.

### MidiToName

```modula2
PROCEDURE MidiToName(midi: INTEGER; VAR name: ARRAY OF CHAR);
```

Convert a MIDI note number to a human-readable name string. For example, 69 becomes "A4", 60 becomes "C4", 61 becomes "C#4".

### FreeNotes

```modula2
PROCEDURE FreeNotes(VAR notes: ADDRESS);
```

Deallocate a notes array returned by `Transcribe`.

```modula2
VAR notes: ADDRESS; n: CARDINAL;
Transcribe(signal, numSamples, 44100, notes, n);
(* n = 24 notes detected with start/end times and names *)
FreeNotes(notes);
```
