import Foundation

@MainActor
final class CopyHistoryService {
    private let defaults: UserDefaults
    private let storageKey = "copy-history-items"
    var maximumItemCount: Int

    init(defaults: UserDefaults = .standard, maximumItemCount: Int = 100) {
        self.defaults = defaults
        self.maximumItemCount = max(maximumItemCount, 1)
    }

    func loadHistory() -> [CopyHistoryItem] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        return (try? JSONDecoder().decode([CopyHistoryItem].self, from: data)) ?? []
    }

    func saveHistory(_ items: [CopyHistoryItem]) {
        guard let data = try? JSONEncoder().encode(trimmed(items)) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    func prepend(_ item: CopyHistoryItem, to items: [CopyHistoryItem]) -> [CopyHistoryItem] {
        var updated = items.filter {
            $0.content != item.content
                || $0.kind != item.kind
                || $0.imageData != item.imageData
        }
        updated.insert(item, at: 0)
        return trimmed(updated)
    }

    func trimmed(_ items: [CopyHistoryItem]) -> [CopyHistoryItem] {
        Array(items.prefix(max(maximumItemCount, 1)))
    }
}
