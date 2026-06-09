import Foundation

@MainActor
final class CopyHistoryService {
    private let defaults: UserDefaults
    private let storageKey = "copy-history-items"
    private let maximumItemCount = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadHistory() -> [CopyHistoryItem] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        return (try? JSONDecoder().decode([CopyHistoryItem].self, from: data)) ?? []
    }

    func saveHistory(_ items: [CopyHistoryItem]) {
        guard let data = try? JSONEncoder().encode(Array(items.prefix(maximumItemCount))) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    func prepend(_ item: CopyHistoryItem, to items: [CopyHistoryItem]) -> [CopyHistoryItem] {
        var updated = items.filter { $0.content != item.content || $0.kind != item.kind }
        updated.insert(item, at: 0)
        return Array(updated.prefix(maximumItemCount))
    }
}
