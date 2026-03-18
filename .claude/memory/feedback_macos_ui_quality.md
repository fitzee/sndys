---
name: macos-ui-quality-bar
description: User expects polished macOS UI — not plain text dumps in scroll views. Use NSAttributedString with styled sections, bold headers, proper spacing, and good use of screen real estate.
type: feedback
---

For macOS native UI, don't just dump monospaced text into a single NSTextView. Instead:
- Use NSAttributedString with bold headers, different font sizes for sections vs values
- Use proper spacing between sections
- Consider NSStackView/NSGridView for structured data display
- Use the full screen width — split into columns where appropriate
- The cursor rect system (resetCursorRects/addCursorRect) is the correct AppKit pattern but may need the view to accept first responder

**Why:** User explicitly said the text dump approach "seems a bit off" and wants better use of screen real estate with bold/styled text.

**How to apply:** Replace plain String text views with NSAttributedString-based rendering using system fonts, bold headers, secondary label colors for labels, and primary colors for values.
