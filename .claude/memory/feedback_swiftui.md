---
name: prefer-swiftui
description: User expects modern macOS apps to use SwiftUI, not AppKit. When the user says "native mac", they mean SwiftUI with current HIG (Sonoma/Sequoia era).
type: feedback
---

Default to SwiftUI for macOS UI work. AppKit is acceptable only for custom views (waveform, spectrogram) embedded via NSViewRepresentable. The user expects modern HIG: NavigationSplitView, Inspector, SF Symbols, vibrancy, system accent colors.

**Why:** User explicitly said "I thought it was SwiftUI" when shown AppKit UI that looked dated.

**How to apply:** Use SwiftUI for layout/navigation/text, NSViewRepresentable for custom drawing (waveform, spectrogram), and the same C bridge layer for analysis.
