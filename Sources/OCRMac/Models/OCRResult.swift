import Foundation

struct OCRResult: Sendable {
    enum Source: String, Sendable {
        case screenClip = "Screen Clip"
        case clipboard = "Clipboard"
    }

    let source: Source
    let text: String
    let recognizedAt: Date
    let confidence: Float?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
