import AppKit
import SwiftUI

@MainActor
final class ClipOCRResultPanelController: NSObject {
    private var panel: NSPanel?

    func present(result: OCRResult, near rect: CGRect, onCopy: @escaping () -> Void) {
        let closeAction: () -> Void = { [weak self] in
            self?.close()
        }
        let rootView = ClipOCRResultView(result: result, onCopy: onCopy, onClose: closeAction)
        let targetFrame = panelFrame(size: CGSize(width: 440, height: 340), near: rect)

        if let panel {
            panel.contentView = NSHostingView(rootView: rootView)
            panel.setFrame(targetFrame, display: true)
            ClipOverlayInteractionRegistry.shared.setIgnoredFrame(panel.frame, for: panel, closeOnEscape: closeAction)
            panel.orderFrontRegardless()
            return
        }

        let panel = ClipOCRResultPanel(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clip OCR"
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: rootView)
        panel.minSize = CGSize(width: 380, height: 280)
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        self.panel = panel
        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(panel.frame, for: panel, closeOnEscape: closeAction)
        panel.orderFrontRegardless()
    }

    func close() {
        if let panel {
            ClipOverlayInteractionRegistry.shared.removeIgnoredFrame(for: panel)
        }
        panel?.orderOut(nil)
    }
}

extension ClipOCRResultPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let panel = notification.object as? NSPanel {
            ClipOverlayInteractionRegistry.shared.removeIgnoredFrame(for: panel)
            panel.orderOut(nil)
        }
    }

    func windowDidMove(_ notification: Notification) {
        updateIgnoredFrame(from: notification)
    }

    func windowDidResize(_ notification: Notification) {
        updateIgnoredFrame(from: notification)
    }

    private func updateIgnoredFrame(from notification: Notification) {
        guard let panel = notification.object as? NSPanel else {
            return
        }

        ClipOverlayInteractionRegistry.shared.setIgnoredFrame(panel.frame, for: panel)
    }
}

private struct ClipOCRResultView: View {
    let result: OCRResult
    let onCopy: () -> Void
    let onClose: () -> Void
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("OCR Result")
                        .font(.headline)
                    Text("\(result.source.rawValue) • \(result.recognizedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let confidence = result.confidence {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            Group {
                if result.isEmpty {
                    ContentUnavailableView(
                        "No text detected",
                        systemImage: "text.viewfinder",
                        description: Text("Try a clearer image or capture a slightly larger region.")
                    )
                } else {
                    ScrollView {
                        Text(result.text)
                            .font(.system(.body, design: .default))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            )

            HStack {
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: copyText) {
                    Label(didCopy ? "Copied" : "Copy Text", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                    .keyboardShortcut("c", modifiers: [.command])
                    .disabled(result.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 280)
        .onChange(of: result.text) { _, _ in
            didCopy = false
        }
    }

    private func copyText() {
        onCopy()
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            didCopy = false
        }
    }
}

private final class ClipOCRResultPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
