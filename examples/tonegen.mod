MODULE ToneGen;
(* Generate a WAV file containing a pure sine tone.
   Demonstrates: m2wav, m2math

   Usage: tonegen 440 2 output.wav
          (frequency in Hz, duration in seconds, output path) *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Args IMPORT ArgCount, GetArg;
FROM MathLib IMPORT sin;
FROM MathUtil IMPORT TwoPi;
FROM Wav IMPORT WriteWav;

CONST
  SampleRate = 44100;
  BitsPerSample = 16;

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

(* Simple integer parser for command-line args *)
PROCEDURE ParseInt(s: ARRAY OF CHAR): INTEGER;
VAR
  i, result: INTEGER;
  neg: BOOLEAN;
BEGIN
  result := 0;
  i := 0;
  neg := FALSE;
  IF s[0] = '-' THEN neg := TRUE; i := 1 END;
  WHILE (i <= HIGH(s)) AND (s[i] # 0C) AND
        (s[i] >= '0') AND (s[i] <= '9') DO
    result := result * 10 + (ORD(s[i]) - ORD('0'));
    INC(i)
  END;
  IF neg THEN RETURN -result END;
  RETURN result
END ParseInt;

VAR
  freqArg, durArg, pathArg: ARRAY [0..255] OF CHAR;
  freq, dur: INTEGER;
  numSamples, i: CARDINAL;
  samples: ADDRESS;
  p: RealPtr;
  phase: LONGREAL;
  ok: BOOLEAN;

BEGIN
  IF ArgCount() < 4 THEN
    WriteString("Usage: tonegen <freq_hz> <duration_sec> <output.wav>");
    WriteLn;
    WriteString("  Example: tonegen 440 2 tone440.wav"); WriteLn;
    HALT
  END;

  GetArg(1, freqArg);
  GetArg(2, durArg);
  GetArg(3, pathArg);

  freq := ParseInt(freqArg);
  dur := ParseInt(durArg);

  IF (freq <= 0) OR (dur <= 0) THEN
    WriteString("Error: frequency and duration must be positive"); WriteLn;
    HALT
  END;

  numSamples := CARDINAL(dur) * SampleRate;

  WriteString("Generating "); WriteInt(freq, 0);
  WriteString(" Hz tone, "); WriteInt(dur, 0);
  WriteString(" seconds ("); WriteCard(numSamples, 0);
  WriteString(" samples)"); WriteLn;

  (* Allocate and fill sample buffer *)
  ALLOCATE(samples, numSamples * TSIZE(LONGREAL));

  FOR i := 0 TO numSamples - 1 DO
    phase := TwoPi * LFLOAT(freq) * LFLOAT(i) / LFLOAT(SampleRate);
    p := Elem(samples, i);
    p^ := 0.8 * LFLOAT(sin(FLOAT(phase)))
  END;

  (* Write WAV *)
  WriteWav(pathArg, samples, numSamples, SampleRate, 1, BitsPerSample, ok);

  IF ok THEN
    WriteString("Wrote: "); WriteString(pathArg); WriteLn
  ELSE
    WriteString("Error: could not write WAV file"); WriteLn
  END;

  DEALLOCATE(samples, numSamples * TSIZE(LONGREAL))
END ToneGen.
