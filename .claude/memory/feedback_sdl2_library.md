---
name: sdl2-audio-in-m2audio
description: User wants SDL2 audio playback as a module inside m2audio, not a separate library. Don't create new mx libraries when adding to an existing one makes more sense.
type: feedback
---

When adding SDL2 audio playback, add it as a module inside m2audio (e.g. Playback.mod), not as a separate mx library. The user prefers keeping related audio functionality together rather than proliferating small libraries.

**Why:** The audio playback wrapper is small enough to live alongside the other audio modules. Creating a separate library adds unnecessary packaging overhead.

**How to apply:** When the user asks for new audio-related functionality, default to adding it as a module in m2audio unless there's a clear reason to separate it.
