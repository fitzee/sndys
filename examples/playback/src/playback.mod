MODULE PlaybackDemo;
(* Demonstrates SDL2 audio playback via the Playback module.
   Generates a 440 Hz sine wave and plays it through the audio device. *)

FROM SYSTEM IMPORT ADDRESS, ADR, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM MathLib IMPORT sin;
FROM MathUtil IMPORT TwoPi;
FROM InOut IMPORT WriteString, WriteCard, WriteLn;
FROM Playback IMPORT InitAudio, QuitAudio, OpenDevice, CloseDevice,
                     ResumeDevice, QueueSamples, GetQueuedBytes,
                     GetObtainedSpec, Delay, GetLastError,
                     DeviceID, AudioSpec, FormatF32;

CONST
  SampleRate = 48000;
  Channels   = 2;
  BufFrames  = 2048;
  Duration   = 2;  (* seconds *)
  Freq       = 440.0;
  Amplitude  = 0.3;

TYPE
  RealPtr = POINTER TO LONGREAL;

VAR
  dev: DeviceID;
  spec: AudioSpec;
  signal: ADDRESS;
  numFrames, i: CARDINAL;
  phase, sample: LONGREAL;
  p: RealPtr;
  errBuf: ARRAY [0..255] OF CHAR;
  ok: BOOLEAN;
BEGIN
  WriteString("Playback demo: 440 Hz stereo sine, 2 seconds"); WriteLn;

  IF NOT InitAudio() THEN
    WriteString("Error: InitAudio failed"); WriteLn;
    HALT
  END;

  dev := OpenDevice(SampleRate, Channels, FormatF32, BufFrames);
  IF dev = 0 THEN
    GetLastError(errBuf);
    WriteString("Error: OpenDevice failed: "); WriteString(errBuf); WriteLn;
    QuitAudio;
    HALT
  END;

  GetObtainedSpec(spec);
  WriteString("Device opened:"); WriteLn;
  WriteString("  Rate:     "); WriteCard(spec.freq, 0); WriteString(" Hz"); WriteLn;
  WriteString("  Channels: "); WriteCard(spec.channels, 0); WriteLn;
  WriteString("  Buffer:   "); WriteCard(spec.samples, 0); WriteString(" frames"); WriteLn;

  (* Generate stereo sine wave: L and R get the same signal *)
  numFrames := SampleRate * Duration;
  ALLOCATE(signal, numFrames * Channels * TSIZE(LONGREAL));

  FOR i := 0 TO numFrames - 1 DO
    phase := TwoPi * Freq * LFLOAT(i) / LFLOAT(SampleRate);
    sample := Amplitude * LFLOAT(sin(FLOAT(phase)));
    p := RealPtr(LONGCARD(signal)
         + LONGCARD(i * Channels) * LONGCARD(TSIZE(LONGREAL)));
    p^ := sample;
    p := RealPtr(LONGCARD(signal)
         + LONGCARD(i * Channels + 1) * LONGCARD(TSIZE(LONGREAL)));
    p^ := sample
  END;

  WriteString("Queuing "); WriteCard(numFrames, 0);
  WriteString(" frames..."); WriteLn;

  ok := QueueSamples(dev, signal, numFrames, Channels);
  IF NOT ok THEN
    GetLastError(errBuf);
    WriteString("Error: QueueSamples failed: "); WriteString(errBuf); WriteLn
  END;

  DEALLOCATE(signal, numFrames * Channels * TSIZE(LONGREAL));

  (* Start playback and wait for queue to drain *)
  ResumeDevice(dev);
  WriteString("Playing..."); WriteLn;

  WHILE GetQueuedBytes(dev) > 0 DO
    Delay(50)
  END;
  (* Small extra delay for the final buffer to finish *)
  Delay(100);

  WriteString("Done."); WriteLn;

  CloseDevice(dev);
  QuitAudio
END PlaybackDemo.
