import Combine
import Foundation

enum SaveLocation: String, CaseIterable, Identifiable, Sendable {
    case downloads
    case desktop
    case documents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: return "Downloads"
        case .desktop: return "Desktop"
        case .documents: return "Documents"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .desktop: return "display"
        case .documents: return "doc.text"
        }
    }

    var directoryURL: URL? {
        let directory: FileManager.SearchPathDirectory
        switch self {
        case .downloads:
            directory = .downloadsDirectory
        case .desktop:
            directory = .desktopDirectory
        case .documents:
            directory = .documentDirectory
        }
        return FileManager.default.urls(for: directory, in: .userDomainMask).first
    }
}

enum OCRLanguageMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case english
    case simplifiedChinese
    case traditionalChinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: return "English plus Simplified and Traditional Chinese"
        case .english: return "Prioritize English recognition"
        case .simplifiedChinese: return "Prioritize Simplified Chinese"
        case .traditionalChinese: return "Prioritize Traditional Chinese"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    enum Keys {
        static let launchAtLoginEnabled = "settings.launch-at-login-enabled"
        static let hideToMenuBarAfterClose = "settings.hide-to-menu-bar-after-close"
        static let defaultSaveLocation = "settings.default-save-location"
        static let clipboardMonitoringEnabled = "settings.clipboard-monitoring-enabled"
        static let copyHistoryLimit = "settings.copy-history-limit"
        static let imageHistoryMaxSizeMB = "settings.image-history-max-size-mb"
        static let ocrLanguageMode = "settings.ocr-language-mode"
    }

    static let defaultCopyHistoryLimit = 100
    static let defaultImageHistoryMaxSizeMB = 16

    private let defaults: UserDefaults

    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var hideToMenuBarAfterClose = true
    @Published private(set) var defaultSaveLocation: SaveLocation = .downloads
    @Published private(set) var clipboardMonitoringEnabled = true
    @Published private(set) var copyHistoryLimit = AppSettings.defaultCopyHistoryLimit
    @Published private(set) var imageHistoryMaxSizeMB = AppSettings.defaultImageHistoryMaxSizeMB
    @Published private(set) var ocrLanguageMode: OCRLanguageMode = .automatic

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLoginEnabled = defaults.bool(forKey: Keys.launchAtLoginEnabled)
        hideToMenuBarAfterClose = Self.bool(
            forKey: Keys.hideToMenuBarAfterClose,
            in: defaults,
            defaultValue: true
        )
        defaultSaveLocation = SaveLocation(
            rawValue: defaults.string(forKey: Keys.defaultSaveLocation) ?? ""
        ) ?? .downloads
        clipboardMonitoringEnabled = Self.bool(
            forKey: Keys.clipboardMonitoringEnabled,
            in: defaults,
            defaultValue: true
        )
        copyHistoryLimit = Self.int(
            forKey: Keys.copyHistoryLimit,
            in: defaults,
            defaultValue: Self.defaultCopyHistoryLimit,
            range: 25...500
        )
        imageHistoryMaxSizeMB = Self.int(
            forKey: Keys.imageHistoryMaxSizeMB,
            in: defaults,
            defaultValue: Self.defaultImageHistoryMaxSizeMB,
            range: 1...100
        )
        ocrLanguageMode = OCRLanguageMode(
            rawValue: defaults.string(forKey: Keys.ocrLanguageMode) ?? ""
        ) ?? .automatic
    }

    static func persistedHideToMenuBarAfterClose(defaults: UserDefaults = .standard) -> Bool {
        bool(forKey: Keys.hideToMenuBarAfterClose, in: defaults, defaultValue: true)
    }

    var defaultSaveDirectoryURL: URL? {
        defaultSaveLocation.directoryURL
    }

    var imageHistoryMaxSizeBytes: Int {
        imageHistoryMaxSizeMB * 1_024 * 1_024
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        defaults.set(enabled, forKey: Keys.launchAtLoginEnabled)
    }

    func setHideToMenuBarAfterClose(_ enabled: Bool) {
        hideToMenuBarAfterClose = enabled
        defaults.set(enabled, forKey: Keys.hideToMenuBarAfterClose)
    }

    func setDefaultSaveLocation(_ location: SaveLocation) {
        defaultSaveLocation = location
        defaults.set(location.rawValue, forKey: Keys.defaultSaveLocation)
    }

    func setClipboardMonitoringEnabled(_ enabled: Bool) {
        clipboardMonitoringEnabled = enabled
        defaults.set(enabled, forKey: Keys.clipboardMonitoringEnabled)
    }

    func setCopyHistoryLimit(_ limit: Int) {
        copyHistoryLimit = min(max(limit, 25), 500)
        defaults.set(copyHistoryLimit, forKey: Keys.copyHistoryLimit)
    }

    func setImageHistoryMaxSizeMB(_ size: Int) {
        imageHistoryMaxSizeMB = min(max(size, 1), 100)
        defaults.set(imageHistoryMaxSizeMB, forKey: Keys.imageHistoryMaxSizeMB)
    }

    func setOCRLanguageMode(_ mode: OCRLanguageMode) {
        ocrLanguageMode = mode
        defaults.set(mode.rawValue, forKey: Keys.ocrLanguageMode)
    }

    private static func bool(forKey key: String, in defaults: UserDefaults, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private static func int(
        forKey key: String,
        in defaults: UserDefaults,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return min(max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }
}
