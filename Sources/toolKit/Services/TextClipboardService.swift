import AppKit

struct TextClipboardService {
    enum ClipboardError: LocalizedError {
        case missingText

        var errorDescription: String? {
            switch self {
            case .missingText:
                return "No text was found in the clipboard. Copy a JSON string first."
            }
        }
    }

    func readText() throws -> String {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            throw ClipboardError.missingText
        }

        return text
    }

    func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
