# Wav

The `Wav` module provides reading and writing of WAV audio files in RIFF PCM format. It handles 8-bit and 16-bit PCM data in mono or stereo configurations, normalizing all sample data to `LONGREAL` arrays in the range `[-1.0, 1.0]`. Stereo samples are stored interleaved as `[L0, R0, L1, R1, ...]`.

## Why Wav?

Working with raw audio in Modula-2 typically means manually parsing RIFF headers, byte-swapping sample data, and converting between integer PCM and floating-point representations. The `Wav` module handles all of this behind a small set of procedures. It reads any PCM 8-bit or 16-bit WAV file into a normalized `LONGREAL` array, and writes one back out, so the rest of your code can work entirely in floating-point without worrying about file format details. It also provides a stereo-to-mono downmix helper and a duration query, covering the most common operations needed when loading audio for analysis or synthesis.

File I/O is performed via the `Sys` module (`DEFINITION MODULE FOR "C"`) which wraps `m2sys_fopen`, `m2sys_fclose`, `m2sys_fread_bytes`, and `m2sys_fwrite_bytes` from the m2sys C shim. Projects using m2wav must link `m2sys.c` (via `extra-c` in m2.toml or passing it on the command line).

## Types

### WavInfo

```modula2
TYPE
  WavInfo = RECORD
    sampleRate: CARDINAL;     (* samples per second, e.g. 44100 *)
    numChannels: CARDINAL;    (* 1 = mono, 2 = stereo *)
    bitsPerSample: CARDINAL;  (* 8 or 16 *)
    numSamples: CARDINAL;     (* total sample frames (per channel) *)
    dataSize: CARDINAL        (* raw PCM data size in bytes *)
  END;
```

A record that describes the format of a WAV file. After a successful call to `ReadWav`, every field is populated from the file header.

| Field | Meaning |
|-------|---------|
| `sampleRate` | Number of sample frames per second (e.g. 8000, 22050, 44100, 48000). |
| `numChannels` | Channel count. 1 for mono, 2 for stereo. |
| `bitsPerSample` | Bit depth of the original PCM data. Either 8 or 16. |
| `numSamples` | Number of sample frames per channel. For a stereo file, the total number of `LONGREAL` values in the sample array is `numSamples * 2`. |
| `dataSize` | Size of the raw PCM data chunk in bytes, as stored in the file. |

## Procedures

### ReadWav

```modula2
PROCEDURE ReadWav(path: ARRAY OF CHAR;
                  VAR info: WavInfo;
                  VAR samples: ADDRESS;
                  VAR ok: BOOLEAN);
```

Reads a WAV file from disk and returns its sample data as a dynamically allocated `LONGREAL` array normalized to the range `[-1.0, 1.0]`. The `info` record is filled with the file's format metadata. For stereo files the samples are interleaved: `[L0, R0, L1, R1, ...]`. The total number of `LONGREAL` elements allocated equals `info.numSamples * info.numChannels`.

If the file cannot be opened, is not a valid RIFF/WAV file, or uses a format other than PCM 8-bit or 16-bit, `ok` is set to `FALSE` and `samples` is undefined.

The caller is responsible for freeing the returned sample array by calling `FreeWav`.

```modula2
VAR
  info: WavInfo;
  samples: ADDRESS;
  ok: BOOLEAN;
BEGIN
  ReadWav("input.wav", info, samples, ok);
  IF ok THEN
    (* process samples... *)
    FreeWav(samples)
  END
END
```

### FreeWav

```modula2
PROCEDURE FreeWav(VAR samples: ADDRESS);
```

Deallocates the sample array that was allocated by `ReadWav`. After the call, `samples` is set to `NIL`. Always call `FreeWav` when you are finished with the sample data to avoid memory leaks.

```modula2
ReadWav("input.wav", info, samples, ok);
IF ok THEN
  (* use samples *)
  FreeWav(samples)
END
```

### StereoToMono

```modula2
PROCEDURE StereoToMono(stereo: ADDRESS;
                       numFrames: CARDINAL;
                       VAR mono: ADDRESS);
```

Converts an interleaved stereo sample array into a mono array by averaging the left and right channels: `mono[i] = (L[i] + R[i]) / 2.0`. A new `LONGREAL` array of `numFrames` elements is allocated for the result. The original stereo array is not modified.

The `numFrames` parameter should be the number of sample frames (i.e. `info.numSamples`), not the total number of interleaved values.

The caller must free the returned mono array with `FreeMono`.

```modula2
ReadWav("stereo.wav", info, samples, ok);
IF ok AND (info.numChannels = 2) THEN
  StereoToMono(samples, info.numSamples, mono);
  (* mono now contains info.numSamples LONGREALs *)
  FreeMono(mono);
  FreeWav(samples)
END
```

### FreeMono

```modula2
PROCEDURE FreeMono(VAR mono: ADDRESS);
```

Deallocates the mono sample array returned by `StereoToMono`. After the call, `mono` is set to `NIL`.

```modula2
StereoToMono(samples, info.numSamples, mono);
(* use mono *)
FreeMono(mono)
```

### WriteWav

```modula2
PROCEDURE WriteWav(path: ARRAY OF CHAR;
                   samples: ADDRESS;
                   numSamples, sampleRate, numChannels,
                   bitsPerSample: CARDINAL;
                   VAR ok: BOOLEAN);
```

Writes a `LONGREAL` sample array to a WAV file on disk. The samples are expected to be in the range `[-1.0, 1.0]` and are converted to integer PCM (16-bit signed or 8-bit unsigned) during writing. For stereo output the sample array must be interleaved.

The `numSamples` parameter is the number of sample frames per channel, so the total number of `LONGREAL` values read from the array is `numSamples * numChannels`.

If the file cannot be created, `ok` is set to `FALSE`.

```modula2
(* Write a 1-second 44100 Hz mono 16-bit silence file *)
WriteWav("silence.wav", buf, 44100, 44100, 1, 16, ok);
IF NOT ok THEN
  (* handle error *)
END
```

### GetDuration

```modula2
PROCEDURE GetDuration(VAR info: WavInfo): LONGREAL;
```

Returns the duration of the audio in seconds, computed as `numSamples / sampleRate`. The `info` record must have been populated by a prior call to `ReadWav`.

```modula2
ReadWav("input.wav", info, samples, ok);
IF ok THEN
  dur := GetDuration(info);
  (* dur is the length in seconds *)
  FreeWav(samples)
END
```

## Supported Formats

The module supports the following PCM WAV configurations:

| Bit depth | Sample format | Channels |
|-----------|---------------|----------|
| 8-bit | Unsigned integer (0..255), normalized to [-1.0, 1.0] | Mono or Stereo |
| 16-bit | Signed integer (-32768..32767), normalized to [-1.0, 1.0] | Mono or Stereo |

All formats use the standard RIFF/WAV container. Compressed formats (ADPCM, MP3, float, etc.) are not supported and will cause `ReadWav` to set `ok` to `FALSE`.

## Example

A complete program that reads a stereo WAV file, downmixes it to mono, and writes the result as a 16-bit mono WAV file.

```modula2
MODULE DownmixToMono;

FROM SYSTEM IMPORT ADDRESS;
FROM Wav IMPORT WavInfo, ReadWav, FreeWav,
                StereoToMono, FreeMono,
                WriteWav, GetDuration;
FROM InOut IMPORT WriteString, WriteLn;
FROM RealInOut IMPORT WriteReal;

VAR
  info: WavInfo;
  samples, mono: ADDRESS;
  ok: BOOLEAN;
  dur: LONGREAL;

BEGIN
  ReadWav("input.wav", info, samples, ok);
  IF NOT ok THEN
    WriteString("Error: cannot read input.wav");
    WriteLn;
    HALT
  END;

  dur := GetDuration(info);
  WriteString("Duration: ");
  WriteReal(dur, 12);
  WriteString(" seconds");
  WriteLn;

  IF info.numChannels = 2 THEN
    StereoToMono(samples, info.numSamples, mono);
    WriteWav("output.wav", mono, info.numSamples,
             info.sampleRate, 1, 16, ok);
    FreeMono(mono)
  ELSE
    WriteWav("output.wav", samples, info.numSamples,
             info.sampleRate, 1, 16, ok);
  END;

  FreeWav(samples);

  IF ok THEN
    WriteString("Wrote output.wav");
    WriteLn
  ELSE
    WriteString("Error: cannot write output.wav");
    WriteLn
  END
END DownmixToMono.
```
