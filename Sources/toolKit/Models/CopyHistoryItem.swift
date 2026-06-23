import Foundation

struct CopyHistoryItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case ocr = "OCR"
        case json = "JSON"
        case clipboard = "Clipboard"
        case image = "Image"
    }

    let id: UUID
    let kind: Kind
    let content: String
    let createdAt: Date
    let imageData: Data?

    init(id: UUID = UUID(), kind: Kind, content: String, createdAt: Date = Date(), imageData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.content = content
        self.createdAt = createdAt
        self.imageData = imageData
    }

    var title: String {
        switch kind {
        case .ocr:
            return "OCR Copy"
        case .json:
            return "JSON Copy"
        case .clipboard:
            return "Clipboard Copy"
        case .image:
            return "Image Copy"
        }
    }

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 180 {
            return trimmed
        }

        return String(trimmed.prefix(180)) + "…"
    }
}
