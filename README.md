# OCRMac

A native macOS OCR utility built with SwiftUI, AppKit, Vision, and CoreGraphics.

## Current features

- Clip a screen region across one or more connected displays, including external monitors
- Read an image from the clipboard
- Paste a JSON string from the clipboard and format it in the app
- Save copied OCR text and formatted JSON into a reusable copy history tab
- Extract text on-device
- English, Simplified Chinese, and Traditional Chinese OCR
- Show the recognized text in a result sheet
 - Show OCR output in a standalone popup result window
- Global hotkey to start clipping: `⌃⌥⌘C`

## Run

1. Open this folder in Xcode, or build with Swift Package Manager.
2. Run the executable.
3. Use the **Capture OCR**, **JSON Formatter**, or **Copy History** tab.

## Package as .app

1. Build the app bundle with `zsh Scripts/package_app.sh`.
2. Find the packaged app at `dist/OCRMac.app`.
3. Launch it with Finder or `open dist/OCRMac.app`.

## Notes

- Screen clipping requires macOS Screen Recording permission.
- Screen clipping works across connected monitors and can span multiple displays in one drag.
- Starting a clip from the hotkey opens clip overlays on all displays and automatically activates the one under the mouse pointer.
- During clipping, the app hides its own regular windows briefly so the captured image contains the underlying content instead of the app UI.
- Clipping now uses macOS's built-in interactive screenshot flow for more reliable multi-window and multi-display capture.
- After clipping, the result opens in its own popup window. Closing that popup keeps the app running in the background.
- OCR uses Apple Vision and runs locally on the device.
- OCR now preprocesses captured images and runs both mixed-language and Chinese-focused recognition passes to improve Chinese text extraction.
- The JSON formatter can handle raw JSON, markdown code fences, and stringified JSON values copied from other apps.
- The copy history tab stores recent copied OCR and JSON content, supports one-click recopy, and allows deleting single entries or clearing all history.
- The generated `.app` is ad-hoc signed for local use.
- Pressing `Esc` or cancelling a clip no longer shows a cancellation error.

## Next steps

- Add a global shortcut
- Improve result editing and history
- Replace the legacy screen capture call with a full ScreenCaptureKit path
# tool-kit
