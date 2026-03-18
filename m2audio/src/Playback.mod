IMPLEMENTATION MODULE Playback;
(* SDL2 queued audio playback — converts LONGREAL samples to device format. *)

FROM SYSTEM IMPORT ADDRESS, TSIZE;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM AxBridge IMPORT ax_init, ax_quit,
                     ax_open_device, ax_close_device,
                     ax_pause_device, ax_resume_device,
                     ax_queue_audio, ax_get_queued_size, ax_clear_queued,
                     ax_obtained_freq, ax_obtained_format,
                     ax_obtained_channels, ax_obtained_samples,
                     ax_obtained_frame_size,
                     ax_get_error, ax_get_ticks, ax_delay,
                     ax_terminal_raw, ax_terminal_restore,
                     ax_key_pressed;

TYPE
  RealPtr  = POINTER TO LONGREAL;
  FloatPtr = POINTER TO REAL;
  ShortPtr = POINTER TO INTEGER;
  CharPtr  = POINTER TO CHAR;

VAR
  (* Internal conversion buffer — allocated on first QueueSamples,
     freed on CloseDevice / QuitAudio *)
  convBuf: ADDRESS;
  convBufSize: CARDINAL;
  currentFormat: CARDINAL;

(* ── Helpers ──────────────────────────────────────────────────────── *)

PROCEDURE ElemR(base: ADDRESS; i: CARDINAL): RealPtr;
BEGIN
  RETURN RealPtr(LONGCARD(base) + LONGCARD(i) * LONGCARD(TSIZE(LONGREAL)))
END ElemR;

PROCEDURE Clamp(x: LONGREAL): LONGREAL;
BEGIN
  IF x > 1.0 THEN RETURN 1.0
  ELSIF x < -1.0 THEN RETURN -1.0
  ELSE RETURN x
  END
END Clamp;

PROCEDURE FreeConvBuf;
BEGIN
  IF convBuf # NIL THEN
    DEALLOCATE(convBuf, convBufSize);
    convBuf := NIL;
    convBufSize := 0
  END
END FreeConvBuf;

(* ── Subsystem lifecycle ──────────────────────────────────────────── *)

PROCEDURE InitAudio(): BOOLEAN;
BEGIN
  RETURN ax_init() # 0
END InitAudio;

PROCEDURE QuitAudio();
BEGIN
  FreeConvBuf;
  ax_quit
END QuitAudio;

(* ── Device management ────────────────────────────────────────────── *)

PROCEDURE OpenDevice(freq, channels, format, bufferFrames: CARDINAL): DeviceID;
BEGIN
  RETURN ax_open_device(INTEGER(freq), INTEGER(channels),
                        INTEGER(format), INTEGER(bufferFrames))
END OpenDevice;

PROCEDURE CloseDevice(dev: DeviceID);
BEGIN
  FreeConvBuf;
  ax_close_device(dev)
END CloseDevice;

PROCEDURE GetObtainedSpec(VAR spec: AudioSpec);
BEGIN
  spec.freq := CARDINAL(ax_obtained_freq());
  spec.format := CARDINAL(ax_obtained_format());
  spec.channels := CARDINAL(ax_obtained_channels());
  spec.samples := CARDINAL(ax_obtained_samples());
  spec.frameSize := CARDINAL(ax_obtained_frame_size())
END GetObtainedSpec;

(* ── Playback control ─────────────────────────────────────────────── *)

PROCEDURE PauseDevice(dev: DeviceID);
BEGIN
  ax_pause_device(dev)
END PauseDevice;

PROCEDURE ResumeDevice(dev: DeviceID);
BEGIN
  ax_resume_device(dev)
END ResumeDevice;

(* ── Queue operations ─────────────────────────────────────────────── *)

PROCEDURE QueueSamples(dev: DeviceID; samples: ADDRESS;
                       numFrames, channels: CARDINAL): BOOLEAN;
VAR
  totalSamples, i: CARDINAL;
  neededSize: CARDINAL;
  fmt: CARDINAL;
  pSrc: RealPtr;
  pF32: FloatPtr;
  pS16: ShortPtr;
  val: LONGREAL;
  sval: INTEGER;
BEGIN
  IF (numFrames = 0) OR (channels = 0) THEN RETURN TRUE END;
  IF numFrames > MaxQueueFrames THEN RETURN FALSE END;

  totalSamples := numFrames * channels;
  fmt := CARDINAL(ax_obtained_format());

  (* Compute needed conversion buffer size *)
  IF fmt = FormatF32 THEN
    neededSize := totalSamples * TSIZE(REAL)
  ELSIF fmt = FormatS16 THEN
    neededSize := totalSamples * TSIZE(INTEGER)
  ELSE
    RETURN FALSE  (* unsupported format *)
  END;

  (* Resize conversion buffer if needed *)
  IF neededSize > convBufSize THEN
    FreeConvBuf;
    ALLOCATE(convBuf, neededSize);
    convBufSize := neededSize
  END;

  (* Convert LONGREAL [-1,1] to device format *)
  IF fmt = FormatF32 THEN
    FOR i := 0 TO totalSamples - 1 DO
      pSrc := ElemR(samples, i);
      val := Clamp(pSrc^);
      pF32 := FloatPtr(LONGCARD(convBuf) + LONGCARD(i) * LONGCARD(TSIZE(REAL)));
      pF32^ := FLOAT(val)
    END
  ELSIF fmt = FormatS16 THEN
    FOR i := 0 TO totalSamples - 1 DO
      pSrc := ElemR(samples, i);
      val := Clamp(pSrc^);
      sval := TRUNC(val * 32767.0);
      pS16 := ShortPtr(LONGCARD(convBuf) + LONGCARD(i) * LONGCARD(TSIZE(INTEGER)));
      pS16^ := sval
    END
  END;

  RETURN ax_queue_audio(dev, convBuf, neededSize) # 0
END QueueSamples;

PROCEDURE QueueBytes(dev: DeviceID; data: ADDRESS; len: CARDINAL): BOOLEAN;
BEGIN
  RETURN ax_queue_audio(dev, data, len) # 0
END QueueBytes;

PROCEDURE GetQueuedBytes(dev: DeviceID): CARDINAL;
BEGIN
  RETURN ax_get_queued_size(dev)
END GetQueuedBytes;

PROCEDURE ClearQueued(dev: DeviceID);
BEGIN
  ax_clear_queued(dev)
END ClearQueued;

(* ── Utilities ────────────────────────────────────────────────────── *)

PROCEDURE GetLastError(VAR buf: ARRAY OF CHAR): CARDINAL;
VAR
  errPtr: ADDRESS;
  cp: CharPtr;
  i: CARDINAL;
BEGIN
  errPtr := ax_get_error();
  IF errPtr = NIL THEN
    buf[0] := 0C;
    RETURN 0
  END;
  i := 0;
  LOOP
    cp := CharPtr(LONGCARD(errPtr) + LONGCARD(i));
    IF cp^ = 0C THEN EXIT END;
    IF i > HIGH(buf) THEN EXIT END;
    buf[i] := cp^;
    INC(i)
  END;
  IF i <= HIGH(buf) THEN buf[i] := 0C END;
  RETURN i
END GetLastError;

PROCEDURE Delay(ms: CARDINAL);
BEGIN
  ax_delay(ms)
END Delay;

PROCEDURE GetTicks(): CARDINAL;
BEGIN
  RETURN ax_get_ticks()
END GetTicks;

PROCEDURE RawMode();
BEGIN
  ax_terminal_raw
END RawMode;

PROCEDURE RestoreMode();
BEGIN
  ax_terminal_restore
END RestoreMode;

PROCEDURE KeyPressed(): BOOLEAN;
BEGIN
  RETURN ax_key_pressed() # 0
END KeyPressed;

BEGIN
  convBuf := NIL;
  convBufSize := 0;
  currentFormat := 0
END Playback.
