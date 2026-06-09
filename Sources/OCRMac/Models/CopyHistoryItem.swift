import Foundation

struct CopyHistoryItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case ocr = "OCR"
        case json = "JSON"
    }

    let id: UUID
    let kind: Kind
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), kind: Kind, content: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.content = content
        self.createdAt = createdAt
    }

    var title: String {
        switch kind {
        case .ocr:
            return "OCR Copy"
        case .json:
            return "JSON Copy"
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
