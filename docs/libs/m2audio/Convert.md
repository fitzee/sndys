# Convert

The `Convert` module handles audio format conversion via an ffmpeg bridge. It converts MP3, OGG, FLAC, AAC, AIFF, and any other ffmpeg-supported format to 16-bit mono WAV for processing by the rest of the sndys toolkit.

## Why Convert?

sndys natively reads WAV files. Convert bridges the gap to all other audio formats by delegating to ffmpeg, which must be installed on the system. This keeps the core codebase pure Modula-2 while supporting the full range of audio formats.

## Procedures

### ConvertToWav

```modula2
PROCEDURE ConvertToWav(inPath: ARRAY OF CHAR;
                       outPath: ARRAY OF CHAR;
                       sampleRate: CARDINAL;
                       VAR ok: BOOLEAN);
```

Convert any audio file to 16-bit mono WAV using ffmpeg. Returns FALSE if ffmpeg is not installed or the conversion fails.

```modula2
VAR ok: BOOLEAN;
ConvertToWav("song.mp3", "/tmp/song.wav", 44100, ok);
IF ok THEN (* process /tmp/song.wav *) END;
```

### IsWavFile

```modula2
PROCEDURE IsWavFile(path: ARRAY OF CHAR): BOOLEAN;
```

Check if a filename ends with `.wav` (case insensitive).

### NeedsConversion

```modula2
PROCEDURE NeedsConversion(path: ARRAY OF CHAR): BOOLEAN;
```

Returns TRUE if the file is not WAV and needs ffmpeg conversion.
