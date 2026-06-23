import AppKit
import Foundation

@MainActor
final class ClipboardMonitorService {
    var onTextCopied: ((String) -> Void)?
    var onImageCopied: ((Data, String) -> Void)?

    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredTexts: Set<String> = []
    private var ignoredImageData: Set<Data> = []
    private(set) var isMonitoring = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        lastChangeCount = pasteboard.changeCount
    }

    func ignoreNextText(_ text: String) {
        ignoredTexts.insert(text)
    }

    func ignoreNextImageData(_ data: Data) {
        ignoredImageData.insert(data)
    }

    private func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = currentChangeCount
        if let image = NSImage(pasteboard: pasteboard),
           let imageData = pngData(for: image) {
            if ignoredImageData.remove(imageData) != nil {
                return
            }

            onImageCopied?(imageData, imageDescription(for: image, data: imageData))
            return
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if ignoredTexts.remove(text) != nil {
                return
            }

            onTextCopied?(text)
        }
    }

    private func pngData(for image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private func imageDescription(for image: NSImage, data: Data) -> String {
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return "Image \(width) x \(height) · \(formatter.string(fromByteCount: Int64(data.count)))"
    }
}
