---
name: apple-hig-compliance
description: User expects native macOS apps to follow Apple Human Interface Guidelines — proper sidebar navigation, no ugly bezel tabs, proper use of NSToolbar, NSSplitView, source list patterns.
type: feedback
---

When building macOS native apps, follow Apple HIG:
- Use NSToolbar (not a custom toolbar NSView with plain buttons)
- Use NSSplitView with sidebar navigation (not centered bezel NSTabView)
- Use source list style for navigation (NSOutlineView or list)
- Use proper NSTableView/NSOutlineView for data display
- Dark appearance should be automatic, not custom themed
- Buttons should use proper system styles
- Don't mix paradigms (SDL-style layouts with native widgets)

**Why:** User explicitly called out that the current implementation "doesn't follow Apple Style guidelines" — the bezel tab view centered in the middle looks dated and non-native.

**How to apply:** Use NSToolbar for actions, NSSplitView for sidebar+content, source list for navigation between analysis sections.
