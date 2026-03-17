MODULE WavInfo;
(* Print metadata and duration of a WAV file.
   Usage: wavinfo samples/file_example_WAV_1MG.wav *)

FROM InOut IMPORT WriteString, WriteInt, WriteCard, WriteLn;
FROM Args IMPORT ArgCount, GetArg;
FROM Wav IMPORT WavInfo, ReadWav, FreeWav, GetDuration;

VAR
  path: ARRAY [0..255] OF CHAR;
  info: WavInfo;
  samples: ADDRESS;
  ok: BOOLEAN;
  dur: LONGREAL;
  durSec, durMs: CARDINAL;

BEGIN
  IF ArgCount() < 2 THEN
    WriteString("Usage: wavinfo <file.wav>"); WriteLn;
    HALT
  END;

  GetArg(1, path);
  WriteString("File: "); WriteString(path); WriteLn;
  WriteLn;

  ReadWav(path, info, samples, ok);
  IF NOT ok THEN
    WriteString("Error: could not read WAV file"); WriteLn;
    HALT
  END;

  WriteString("  Sample rate:    "); WriteCard(info.sampleRate, 0);
  WriteString(" Hz"); WriteLn;

  WriteString("  Channels:       "); WriteCard(info.numChannels, 0);
  IF info.numChannels = 1 THEN
    WriteString(" (mono)")
  ELSIF info.numChannels = 2 THEN
    WriteString(" (stereo)")
  END;
  WriteLn;

  WriteString("  Bits/sample:    "); WriteCard(info.bitsPerSample, 0);
  WriteLn;

  WriteString("  Total samples:  "); WriteCard(info.numSamples, 0);
  WriteString(" (per channel)"); WriteLn;

  WriteString("  Data size:      "); WriteCard(info.dataSize, 0);
  WriteString(" bytes"); WriteLn;

  dur := GetDuration(info);
  durSec := TRUNC(dur);
  durMs := TRUNC((dur - LFLOAT(durSec)) * 1000.0);
  WriteString("  Duration:       "); WriteCard(durSec, 0);
  WriteString(".");
  IF durMs < 100 THEN WriteString("0") END;
  IF durMs < 10 THEN WriteString("0") END;
  WriteCard(durMs, 0);
  WriteString(" seconds"); WriteLn;

  FreeWav(samples)
END WavInfo.
