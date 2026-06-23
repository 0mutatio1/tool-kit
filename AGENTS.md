# AGENTS.md

## Priority rules

- Read and follow `CLAUDE.md` before making code changes.
- Prefer surgical, minimal edits that directly serve the request.
- Do not revert unrelated user changes or clean up adjacent code unless asked.
- Match the existing Swift, SwiftUI, and AppKit patterns before adding new abstractions.

## Project overview

`toolKit` is a native macOS 14+ utility built with SwiftUI, AppKit, Vision, CoreGraphics, and SwiftPM.

Core product areas:

- Screen clipping, annotation, pinning, saving, and OCR
- JSON formatting with two independent editor panes
- Cron expression generation and decoding
- Text diffing
- Persistent copy history for text and images
- Settings and menu bar behavior

## Architecture map

- `Sources/toolKit/App` - app entry, app delegate, menu bar scene
- `Sources/toolKit/Views` - SwiftUI views and WebView wrappers
- `Sources/toolKit/ViewModels` - UI state and orchestration
- `Sources/toolKit/Services` - capture, overlay, OCR, clipboard, permissions, persistence, formatting, cron, diff
- `Sources/toolKit/Models` - shared data models and settings types
- `Tests/toolKitTests` - service-level SwiftPM tests

Treat these files as high risk:

- `Sources/toolKit/Services/ScreenSelectionWindowController.swift` - multi-display overlay, annotation tools, hit testing, keyboard/mouse behavior, in-place actions
- `Sources/toolKit/ViewModels/AppViewModel.swift` - cross-feature orchestration, clipboard history, OCR, pin/save/capture actions, settings updates

## Project invariants

- Screen clipping must support external monitors and regions spanning available displays.
- Starting clipping from the global hotkey must use non-activating overlay panels and must not force focus back to the main app window.
- During clipping and initial capture, regular app windows are hidden so captures contain underlying screen content.
- The custom selection overlay is the only clip UI; annotations are composited into the bitmap before copy, pin, save, or OCR.
- Pin and export output must preserve selected screen content orientation and screen-scale resolution.
- Clip OCR and pinned image windows must not force focus back to the main app window.
- OCR stays on-device using Apple Vision and image preprocessing.
- OCR language modes are automatic, English, Simplified Chinese, and Traditional Chinese.
- JSON formatting accepts raw JSON, markdown code fences, and some stringified JSON.
- Clipboard monitoring pause must not record external clipboard changes; app-generated OCR and JSON copies still enter history.
- Closing the main window hides ToolKit to the menu bar by default; explicit menu bar Quit terminates the app.

## Build, test, and package

- Build: `swift build`
- Test: `swift test`
- Run locally: `swift run`
- Package after coding changes: `zsh Scripts/package_app.sh`

The packaged app is expected at `dist/toolKit.app`.

## Engineering guidance

- Keep service-level logic testable where practical.
- Add or update focused tests for JSON, cron, diff, history, rendering, and other service behavior when changed.
- Be conservative around overlay, focus, screen capture, and pinned-window behavior; verify manually when tests cannot cover it.
- Keep UI changes consistent with the existing collapsible sidebar and dense utility-app layout.
- Preserve UserDefaults-backed settings compatibility unless the task explicitly calls for a migration.
