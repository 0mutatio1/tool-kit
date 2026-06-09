import AppKit
import SwiftUI

@MainActor
final class ResultPanelController: NSObject {
    private var window: NSPanel?

    func present(result: OCRResult, onCopy: @escaping () -> Void) {
        let closeAction: () -> Void = { [weak self] in
            self?.close()
        }

        let rootView = ResultView(
            result: result,
            onCopy: onCopy,
            onClose: closeAction
        )

        if let window {
            window.contentView = NSHostingView(rootView: rootView)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "OCR Result"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.center()
        panel.contentView = NSHostingView(rootView: rootView)
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}

extension ResultPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }
}
