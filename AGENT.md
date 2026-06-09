# AGENT.md


## Agent Rules

- Read and follow `CLAUDE.md` before making code changes.

## Project overview

`OCRMac` is a native macOS OCR utility built with SwiftUI, AppKit, Vision, and CoreGraphics.

## Current architecture

- `Sources/OCRMac/App` — app entry
- `Sources/OCRMac/Views` — SwiftUI views
- `Sources/OCRMac/ViewModels` — UI state and orchestration
- `Sources/OCRMac/Services` — screen capture, selection overlay, OCR, clipboard, permissions
- `Sources/OCRMac/Models` — shared data models

## Current feature scope

- Clip a screen region across one or more connected displays
- Keep the Clip screen region with two icon one can copy the 
  clip screen region as image the other can OCR an image from the clipboard
- Store copied OCR and JSON text in a persistent copy history
- On-device OCR only
- English, Simplified Chinese, and Traditional Chinese recognition
- Show OCR result in a result sheet
- Show OCR results in a standalone popup window
- Global clip hotkey: `⌃⌥⌘C`

### Json Formatter
- Use `https://github.com/josdejong/jsoneditor` to format json text
- JSON Formatter tab uses two separate jsoneditor panes: Left and Right
- Each editor is independent and has its own separate actions 
- Removed the scroll wrapper from the JSON tab so the editors can resize with the current tab.
- The editors should fill the available tab height and respond to window resizing.
- Layout stays side-by-side on wide windows and stacks on narrow windows.

## Build and run

- Build: `swift build`
- Run: `swift run`
- Package app bundle: `zsh Scripts/package_app.sh`

## Important constraints

- Requires macOS 14+
- Screen clipping needs Screen Recording permission
- Screen clipping supports external monitors and can compose one capture across multiple displays
- Starting a clip from the hotkey opens overlay windows on all displays and activates the one containing the mouse pointer
- During clipping, regular app windows are temporarily hidden so screen capture reads the actual underlying content
- Clipping uses macOS's built-in interactive screenshot flow rather than relying only on custom overlay capture
- Closing the result popup does not quit the app; the app keeps running in the background and can be reopened
- OCR is implemented with Apple Vision plus image preprocessing and dedicated Chinese-friendly recognition passes
- The main UI is tabbed: one tab for capture OCR and one tab for JSON formatting
- The main UI is tabbed for capture OCR, JSON formatting, and copy history management
- JSON formatter that accepts raw JSON, markdown code fences, and some stringified JSON
- The packaged app is created at `dist/OCRMac.app`

## Suggested next work

1. Replace capture path with ScreenCaptureKit
2. Improve result editing/history
