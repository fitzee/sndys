MODULE Spectrum;
(* Compute and print the FFT magnitude spectrum of the first frame
   of a WAV file.  Shows the top 20 frequency bins by magnitude.

   Demonstrates: m2wav, m2fft, m2math *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM Args IMPORT ArgCount, GetArg;
FROM MathLib IMPORT sin;
FROM Wav IMPORT WavInfo, ReadWav, FreeWav, StereoToMono, FreeMono;
FROM FFT IMPORT Forward, RealToComplex, Magnitude;
FROM MathUtil IMPORT NextPow2;

CONST
  FrameMs = 50;  (* 50 ms analysis frame *)

TYPE
  RealPtr = POINTER TO LONGREAL;

PROCEDURE Elem(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i * TSIZE(LONGREAL)))
END Elem;

VAR
  path: ARRAY [0..255] OF CHAR;
  info: WavInfo;
  rawSamples, mono, complexBuf, magBuf: ADDRESS;
  ok: BOOLEAN;
  frameSamples, fftSize, fftHalf: CARDINAL;
  i, j, maxIdx: CARDINAL;
  p, pMax: RealPtr;
  maxVal, freqHz: LONGREAL;
  printed: CARDINAL;

BEGIN
  IF ArgCount() < 2 THEN
    WriteString("Usage: spectrum <file.wav>"); WriteLn;
    HALT
  END;

  GetArg(1, path);

  (* Read WAV *)
  ReadWav(path, info, rawSamples, ok);
  IF NOT ok THEN
    WriteString("Error: could not read WAV file"); WriteLn;
    HALT
  END;

  (* Convert stereo to mono if needed *)
  IF info.numChannels = 2 THEN
    StereoToMono(rawSamples, info.numSamples, mono);
    FreeWav(rawSamples, info.numSamples * info.numChannels)
  ELSE
    mono := rawSamples
  END;

  (* Determine frame size *)
  frameSamples := info.sampleRate * FrameMs DIV 1000;
  IF frameSamples > info.numSamples THEN
    frameSamples := info.numSamples
  END;
  fftSize := NextPow2(frameSamples);
  fftHalf := fftSize DIV 2 + 1;

  WriteString("FFT of first "); WriteCard(FrameMs, 0);
  WriteString("ms frame ("); WriteCard(frameSamples, 0);
  WriteString(" samples, padded to "); WriteCard(fftSize, 0);
  WriteString(")"); WriteLn; WriteLn;

  (* Allocate buffers *)
  ALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  ALLOCATE(magBuf, fftSize * TSIZE(LONGREAL));

  (* Zero-pad into complex buffer *)
  FOR i := 0 TO fftSize - 1 DO
    p := Elem(complexBuf, 2 * i);
    IF i < frameSamples THEN
      pMax := Elem(mono, i);
      p^ := pMax^
    ELSE
      p^ := 0.0
    END;
    p := Elem(complexBuf, 2 * i + 1);
    p^ := 0.0
  END;

  (* Compute FFT and magnitude *)
  Forward(complexBuf, fftSize);
  Magnitude(complexBuf, fftSize, magBuf);

  (* Print top 20 bins by magnitude *)
  WriteString("Top 20 frequency bins:"); WriteLn;
  WriteString("  Bin    Freq (Hz)    Magnitude"); WriteLn;
  WriteString("  ---    ---------    ---------"); WriteLn;

  printed := 0;
  WHILE printed < 20 DO
    (* Find max remaining bin *)
    maxVal := -1.0;
    maxIdx := 0;
    FOR i := 0 TO fftHalf - 1 DO
      p := Elem(magBuf, i);
      IF p^ > maxVal THEN
        maxVal := p^;
        maxIdx := i
      END
    END;

    IF maxVal <= 0.0 THEN
      (* no more non-zero bins *)
      EXIT
    END;

    freqHz := LFLOAT(maxIdx) * LFLOAT(info.sampleRate) / LFLOAT(fftSize);

    WriteString("  ");
    WriteCard(maxIdx, 5);
    WriteString("    ");
    WriteCard(TRUNC(freqHz), 6);
    WriteString(" Hz    ");
    WriteCard(TRUNC(maxVal * 1000.0), 8);
    WriteString(" (x1000)");
    WriteLn;

    (* Zero out this bin so we find the next one *)
    p := Elem(magBuf, maxIdx);
    p^ := 0.0;

    INC(printed)
  END;

  (* Cleanup *)
  DEALLOCATE(complexBuf, 2 * fftSize * TSIZE(LONGREAL));
  DEALLOCATE(magBuf, fftSize * TSIZE(LONGREAL));
  IF info.numChannels = 2 THEN
    FreeMono(mono, info.numSamples)
  ELSE
    FreeWav(mono, info.numSamples)
  END
END Spectrum.
