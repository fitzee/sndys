# Playback

The `Playback` module provides SDL2 queued audio output for playing mono or stereo PCM audio. It wraps SDL2's audio queue API with a minimal, explicit Modula-2 interface.

## Why Playback?

The other m2audio modules analyze, extract, transform, and generate audio — but none of them produce sound. Playback closes this gap with a thin SDL2 wrapper that lets callers push LONGREAL sample data to an audio device. This enables the `sndys play` command and serves as the foundation for future interactive audio tools.

## Playback Model

This module uses SDL2's **queued audio output** model:

1. Open a device — it starts paused
2. Convert and queue sample data in chunks
3. Resume the device — SDL drains the queue asynchronously
4. Monitor `GetQueuedBytes` to track playback progress
5. Close when done

Callers provide LONGREAL samples in `[-1.0, 1.0]`. The module converts to the device's native format (F32 or S16) internally using a managed conversion buffer. SDL copies the queued data, so the caller's buffer can be freed immediately after `QueueSamples` returns.

There is no callback-based streaming, no mixing, no resampling, and no effects. This is intentionally low-level.

## Types

### DeviceID

```modula2
TYPE DeviceID = CARDINAL;
```

Opaque audio device identifier. 0 = invalid / not open. Values >= 2 are valid SDL device IDs.

### AudioSpec

```modula2
TYPE AudioSpec = RECORD
  freq:      CARDINAL;  (* sample rate in Hz *)
  format:    CARDINAL;  (* FormatS16 or FormatF32 *)
  channels:  CARDINAL;  (* 1 = mono, 2 = stereo *)
  samples:   CARDINAL;  (* buffer size in sample frames *)
  frameSize: CARDINAL   (* bytes per frame *)
END;
```

Describes the audio format negotiated by SDL after opening a device.

## Constants

```modula2
CONST
  FormatS16 = 32784;     (* signed 16-bit little-endian PCM *)
  FormatF32 = 33056;     (* 32-bit float little-endian PCM *)
  MaxQueueFrames = 1048576;  (* max frames per QueueSamples call *)
```

## Procedures

### InitAudio / QuitAudio

```modula2
PROCEDURE InitAudio(): BOOLEAN;
PROCEDURE QuitAudio();
```

Initialize and shut down the SDL2 audio subsystem. `InitAudio` must be called before `OpenDevice`. `QuitAudio` closes any open device and frees internal buffers.

### OpenDevice

```modula2
PROCEDURE OpenDevice(freq, channels, format, bufferFrames: CARDINAL): DeviceID;
```

Open an audio output device for queued playback. The device opens **paused** — call `ResumeDevice` to start output.

- `freq`: desired sample rate (e.g. 44100, 48000)
- `channels`: 1 for mono, 2 for stereo
- `format`: `FormatS16` or `FormatF32`
- `bufferFrames`: SDL audio buffer size in sample frames (e.g. 1024, 2048). Smaller = lower latency, larger = fewer underruns.

Returns a `DeviceID` > 0 on success, 0 on failure.

### CloseDevice

```modula2
PROCEDURE CloseDevice(dev: DeviceID);
```

Close an audio device and free the internal conversion buffer.

### GetObtainedSpec

```modula2
PROCEDURE GetObtainedSpec(VAR spec: AudioSpec);
```

Query the actual audio parameters negotiated by SDL. Call after a successful `OpenDevice`.

### PauseDevice / ResumeDevice

```modula2
PROCEDURE PauseDevice(dev: DeviceID);
PROCEDURE ResumeDevice(dev: DeviceID);
```

Pause or resume audio output. Pausing preserves queued data.

### QueueSamples

```modula2
PROCEDURE QueueSamples(dev: DeviceID; samples: ADDRESS;
                       numFrames, channels: CARDINAL): BOOLEAN;
```

Convert LONGREAL samples to the device format and queue for playback.

- `samples`: `numFrames * channels` LONGREALs in `[-1.0, 1.0]`
- Values are clamped before conversion
- SDL copies the data — caller retains ownership
- Maximum `MaxQueueFrames` per call

Returns TRUE on success.

### QueueBytes

```modula2
PROCEDURE QueueBytes(dev: DeviceID; data: ADDRESS; len: CARDINAL): BOOLEAN;
```

Queue raw pre-formatted PCM bytes directly, bypassing conversion. The data must match the device's native format.

### GetQueuedBytes / ClearQueued

```modula2
PROCEDURE GetQueuedBytes(dev: DeviceID): CARDINAL;
PROCEDURE ClearQueued(dev: DeviceID);
```

Query or discard pending audio in SDL's queue.

### GetLastError

```modula2
PROCEDURE GetLastError(VAR buf: ARRAY OF CHAR): CARDINAL;
```

Copy SDL's last error message into `buf`. Returns the length written.

### Delay / GetTicks

```modula2
PROCEDURE Delay(ms: CARDINAL);
PROCEDURE GetTicks(): CARDINAL;
```

Timer utilities for drain-wait loops. `Delay` sleeps for the given milliseconds. `GetTicks` returns milliseconds since `InitAudio`.

### RawMode / RestoreMode / KeyPressed

```modula2
PROCEDURE RawMode();
PROCEDURE RestoreMode();
PROCEDURE KeyPressed(): BOOLEAN;
```

Terminal input utilities for interruptible playback. `RawMode` puts the terminal into non-canonical mode (no line buffering, no echo). `KeyPressed` performs a non-blocking check — returns TRUE if a key was pressed, consuming the keystroke. Always call `RestoreMode` before exiting.

## Ownership

- **Sample data** passed to `QueueSamples` is copied by SDL. The caller owns the buffer and may free it immediately.
- The **conversion buffer** is managed internally. It is allocated on first `QueueSamples` call and freed on `CloseDevice` or `QuitAudio`.
- **Terminal state** must be restored by calling `RestoreMode` before the program exits.

## Limitations

- Queued output only — no callback-based streaming
- No mixing, resampling, or effects
- One obtained-spec at a time (global state in the C bridge)
- `MaxQueueFrames` (1M) limits a single `QueueSamples` call to ~22 seconds at 48 kHz
- `KeyPressed` requires a real terminal (not pipes or tool runners)
- macOS only (links homebrew SDL2); Linux would need adjusted library paths

## Platform Notes

Requires SDL2 installed via Homebrew (`brew install sdl2`). The m2audio `m2.toml` links `-lSDL2` and sets macOS-specific include/library paths. The C bridge (`ax_bridge.c`) is compiled directly into the binary via `extra-c=`.

## Example

```modula2
FROM Playback IMPORT InitAudio, QuitAudio, OpenDevice, CloseDevice,
                     ResumeDevice, QueueSamples, GetQueuedBytes, Delay,
                     DeviceID, FormatF32;

VAR dev: DeviceID;
BEGIN
  InitAudio();
  dev := OpenDevice(48000, 1, FormatF32, 2048);
  QueueSamples(dev, signal, numFrames, 1);
  ResumeDevice(dev);
  WHILE GetQueuedBytes(dev) > 0 DO Delay(10) END;
  CloseDevice(dev);
  QuitAudio
END
```
