import Foundation

struct TextDiffRow: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case equal
        case inserted
        case deleted
        case changed
    }

    struct Parts: Equatable, Sendable {
        let prefix: String
        let highlighted: String
        let suffix: String

        var fullText: String {
            prefix + highlighted + suffix
        }
    }

    let id = UUID()
    let kind: Kind
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let left: Parts?
    let right: Parts?
}

struct TextDiffSummary: Equatable, Sendable {
    let added: Int
    let deleted: Int
    let changed: Int
    let unchanged: Int

    var totalDifferences: Int {
        added + deleted + changed
    }
}
