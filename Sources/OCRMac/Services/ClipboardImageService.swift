import AppKit

struct ClipboardImageService {
    enum ClipboardError: LocalizedError {
        case missingImage

        var errorDescription: String? {
            switch self {
            case .missingImage:
                return "No image was found in the clipboard. Copy an image first and try again."
            }
        }
    }

    func readImage() throws -> NSImage {
        let pasteboard = NSPasteboard.general

        guard let image = NSImage(pasteboard: pasteboard) else {
            throw ClipboardError.missingImage
        }

        return image
    }

    func writeImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
