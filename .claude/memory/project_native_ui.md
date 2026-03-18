---
name: native-macos-ui-direction
description: User wants to explore native macOS (Cocoa/AppKit) UI for sndys instead of SDL2-based m2gfx UI. Motivated by SDL2 compositor issues (modal not showing, font rendering quality) on macOS.
type: project
---

User asked about building sndysUI with native macOS Cocoa widgets wrapping the existing Modula-2 audio libraries. This came after frustration with SDL2 rendering issues on macOS (font quality, modal dialogs not flushing to compositor, DPI scaling complexity).

**Why:** Native AppKit gives proper font rendering (Core Text), real modal dialogs, native file pickers, proper HiDPI support, and macOS compositor integration for free.

**How to apply:** If pursuing this, the approach would be a Swift/ObjC front-end that calls into the compiled Modula-2 libraries via C FFI. The mx-compiled M2 code produces standard C objects that can be linked into any native app.
