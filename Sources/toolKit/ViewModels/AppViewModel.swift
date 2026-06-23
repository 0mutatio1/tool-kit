import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum MainTab: Hashable, CaseIterable, Identifiable {
    case capture
    case jsonFormatter
    case cron
    case diff
    case copyHistory
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .capture: return "Clip OCR"
        case .jsonFormatter: return "JSON Formatter"
        case .cron: return "Cron"
        case .diff: return "Diff"
        case .copyHistory: return "Copy History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: return "text.viewfinder"
        case .jsonFormatter: return "curlybraces"
        case .cron: return "calendar.badge.clock"
        case .diff: return "rectangle.split.2x1"
        case .copyHistory: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var result: OCRResult?
    @Published var lastErrorMessage: String?
    @Published var jsonInput = ""
    @Published var formattedJSON = ""
    @Published var jsonFormatterErrorMessage: String?
    @Published var jsonFormatterStatusMessage: String?
    @Published var copyHistoryItems: [CopyHistoryItem] = []
    @Published var cronExpression = "*/15 * * * *"
    @Published var cronGeneratorMode: CronGeneratorMode = .everyNMinutes
    @Published var cronMinute = 0
    @Published var cronHour = 9
    @Published var cronDayOfMonth = 1
    @Published var cronWeekday = 1
    @Published var cronIntervalMinutes = 15
    @Published var cronExplanationSummary = ""
    @Published var cronExplanationDetails: [String] = []
    @Published var cronTimeline: [Date] = []
    @Published var cronErrorMessage: String?
    @Published var cronStatusMessage: String?
    @Published var diffLeftText = ""
    @Published var diffRightText = ""
    @Published var diffRows: [TextDiffRow] = []
    @Published var diffSummary = TextDiffSummary(added: 0, deleted: 0, changed: 0, unchanged: 0)
    @Published var diffErrorMessage: String?
    @Published var diffStatusMessage: String?
    @Published var selectedMainTab: MainTab = .capture
    @Published var settingsStatusMessage: String?
    @Published var settingsErrorMessage: String?

    let clipShortcutDisplay = GlobalHotKeyManager.Shortcut.defaultClipShortcut.displayText
    let settings: AppSettings
    var hasJSONText: Bool {
        !currentJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var hasLeftJSONText: Bool {
        !jsonInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var hasRightJSONText: Bool {
        !formattedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var hasJSONInput: Bool { hasLeftJSONText }
    var hasFormattedJSON: Bool { hasRightJSONText }
    var hasCronExpression: Bool {
        !cronExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var hasDiffText: Bool {
        !diffLeftText.isEmpty || !diffRightText.isEmpty
    }

    private let ocrService = OCRService()
    private let clipboardService = ClipboardImageService()
    private let textClipboardService = TextClipboardService()
    private let jsonFormatterService = JSONFormatterService()
    private let cronExpressionService = CronExpressionService()
    private let textDiffService = TextDiffService()
    private let copyHistoryService: CopyHistoryService
    private let clipboardMonitorService = ClipboardMonitorService()
    private let permissionService = PermissionService()
    private let screenCaptureService = ScreenCaptureService()
    private let hotKeyManager = GlobalHotKeyManager()
    private let resultPanelController = ResultPanelController()
    private let pinnedClipPanelController = PinnedClipPanelController()
    private let clipOCRResultPanelController = ClipOCRResultPanelController()
    private let windowFocusService = WindowFocusService()
    private let launchAtLoginService = LaunchAtLoginService()
    private var hasConfiguredHotKey = false
    private var settingsCancellable: AnyCancellable?

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.copyHistoryService = CopyHistoryService(maximumItemCount: settings.copyHistoryLimit)
        copyHistoryItems = copyHistoryService.loadHistory()
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        clipboardMonitorService.onTextCopied = { [weak self] text in
            self?.appendCopyHistoryItem(kind: .clipboard, content: text)
        }
        clipboardMonitorService.onImageCopied = { [weak self] data, description in
            self?.appendImageHistoryItem(data: data, description: description)
        }
        explainCronExpression()
    }

    func configureHotKeyIfNeeded() {
        guard !hasConfiguredHotKey else {
            return
        }

        hasConfiguredHotKey = true
        applyClipboardMonitoringPreference()
        hotKeyManager.onKeyDown = { [weak self] in
            self?.runScreenClipCapture(preferredScreen: NSScreen.screenContainingMouse, keepWindowsHiddenAfterCapture: false)
        }
        hotKeyManager.register()
    }

    func runScreenClipOCR(preferredScreen: NSScreen? = nil, keepWindowsHiddenAfterCapture: Bool = false) {
        runScreenClipCapture(preferredScreen: preferredScreen, keepWindowsHiddenAfterCapture: keepWindowsHiddenAfterCapture)
    }

    func openMainWindow() {
        windowFocusService.focusAppWindowOnScreenContainingMouse()
    }

    func openCopyHistory() {
        selectedMainTab = .copyHistory
        openMainWindow()
    }

    func openSettings() {
        selectedMainTab = .settings
        openMainWindow()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func toggleClipboardMonitoring() {
        setClipboardMonitoringEnabled(!settings.clipboardMonitoringEnabled)
    }

    func setClipboardMonitoringEnabled(_ enabled: Bool) {
        settings.setClipboardMonitoringEnabled(enabled)
        applyClipboardMonitoringPreference()
        settingsErrorMessage = nil
        settingsStatusMessage = enabled ? "Clipboard monitoring resumed." : "Clipboard monitoring paused."
    }

    func setHideToMenuBarAfterClose(_ enabled: Bool) {
        settings.setHideToMenuBarAfterClose(enabled)
        settingsErrorMessage = nil
        settingsStatusMessage = enabled
            ? "Closing the main window will keep ToolKit in the menu bar."
            : "Closing the last main window will quit OCRMac."
    }

    func setDefaultSaveLocation(_ location: SaveLocation) {
        settings.setDefaultSaveLocation(location)
        settingsErrorMessage = nil
        settingsStatusMessage = "Default save location set to \(location.title)."
    }

    func setOCRLanguageMode(_ mode: OCRLanguageMode) {
        settings.setOCRLanguageMode(mode)
        settingsErrorMessage = nil
        settingsStatusMessage = "OCR language mode set to \(mode.title)."
    }

    func updateCopyHistoryLimit(_ limit: Int) {
        settings.setCopyHistoryLimit(limit)
        copyHistoryService.maximumItemCount = settings.copyHistoryLimit
        copyHistoryItems = copyHistoryService.trimmed(copyHistoryItems)
        persistCopyHistory()
        settingsErrorMessage = nil
        settingsStatusMessage = "Copy history keeps the latest \(settings.copyHistoryLimit) items."
    }

    func updateImageHistoryMaxSizeMB(_ size: Int) {
        settings.setImageHistoryMaxSizeMB(size)
        settingsErrorMessage = nil
        settingsStatusMessage = "Image history limit set to \(settings.imageHistoryMaxSizeMB) MB."
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            settings.setLaunchAtLoginEnabled(enabled)
            settingsErrorMessage = nil
            settingsStatusMessage = enabled ? "ToolKit will launch at login." : "Launch at login disabled."
        } catch {
            settings.setLaunchAtLoginEnabled(false)
            settingsStatusMessage = nil
            settingsErrorMessage = error.localizedDescription
        }
    }

    func runScreenClipCapture(preferredScreen: NSScreen? = nil, keepWindowsHiddenAfterCapture: Bool = false) {
        Task {
            isProcessing = true
            lastErrorMessage = nil

            do {
                try self.permissionService.ensureScreenCapturePermission()
                let capturedRegion = try await self.screenCaptureService.captureRegion(
                    preferredScreen: preferredScreen,
                    defaultSaveDirectory: settings.defaultSaveDirectoryURL,
                    restoreWindowsAfterCapture: !keepWindowsHiddenAfterCapture,
                    handleInPlaceResult: { [weak self] capturedRegion in
                        self?.handleInPlaceClipAction(capturedRegion)
                    }
                )
                switch capturedRegion.action {
                case .capture:
                    clipboardService.writeImage(capturedRegion.image)
                    isProcessing = false
                case .ocr:
                    await performOCR(source: .screenClip) {
                        capturedRegion.image
                    }
                case .pin:
                    pinClipImage(capturedRegion.image, near: capturedRegion.rect)
                    isProcessing = false
                case .save:
                    saveClipImage(capturedRegion.image)
                    isProcessing = false
                }
            } catch is CancellationError {
                lastErrorMessage = nil
                isProcessing = false
            } catch {
                lastErrorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    func clearResult() {
        result = nil
        lastErrorMessage = nil
    }

    func pasteJSONFromClipboard() {
        pasteJSONIntoLeftEditor()
    }

    func pasteJSONIntoLeftEditor() {
        do {
            updateLeftJSONText(try textClipboardService.readText())
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Pasted into left editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func pasteJSONIntoRightEditor() {
        do {
            updateRightJSONText(try textClipboardService.readText())
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Pasted into right editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func formatJSON() {
        formatJSONInput()
    }

    func formatJSONInput() {
        formatLeftJSON()
    }

    func formatLeftJSON() {
        do {
            jsonInput = try jsonFormatterService.format(jsonInput)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Formatted left editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func formatRightJSON() {
        do {
            formattedJSON = try jsonFormatterService.format(formattedJSON)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Formatted right editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func compactJSON() {
        compactFormattedJSON()
    }

    func compactFormattedJSON() {
        compactRightJSON()
    }

    func compactLeftJSON() {
        do {
            jsonInput = try jsonFormatterService.compact(jsonInput)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Compacted left editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func compactRightJSON() {
        do {
            formattedJSON = try jsonFormatterService.compact(formattedJSON)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Compacted right editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func repairJSON() {
        repairJSONInput()
    }

    func repairJSONInput() {
        repairLeftJSON()
    }

    func repairLeftJSON() {
        do {
            jsonInput = try jsonFormatterService.repairAndFormat(jsonInput)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Repaired left editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func repairRightJSON() {
        do {
            formattedJSON = try jsonFormatterService.repairAndFormat(formattedJSON)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Repaired right editor."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func validateJSON() {
        validateJSONInput()
    }

    func validateJSONInput() {
        validateLeftJSON()
    }

    func validateLeftJSON() {
        do {
            try jsonFormatterService.validate(jsonInput)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Left editor contains valid JSON."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func validateRightJSON() {
        do {
            try jsonFormatterService.validate(formattedJSON)
            jsonFormatterErrorMessage = nil
            jsonFormatterStatusMessage = "Right editor contains valid JSON."
        } catch {
            jsonFormatterErrorMessage = error.localizedDescription
            jsonFormatterStatusMessage = nil
        }
    }

    func clearJSON() {
        jsonInput = ""
        formattedJSON = ""
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = nil
    }

    func clearJSONInput() {
        jsonInput = ""
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = nil
    }

    func clearFormattedJSON() {
        formattedJSON = ""
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = nil
    }

    func updateJSONInput(_ text: String) {
        updateLeftJSONText(text)
    }

    func updateLeftJSONText(_ text: String) {
        jsonInput = text
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = nil
    }

    func updateRightJSONText(_ text: String) {
        formattedJSON = text
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = nil
    }

    func useFormattedJSONAsInput() {
        copyRightJSONToLeft()
    }

    func copyLeftJSONToRight() {
        let text = jsonInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            jsonFormatterErrorMessage = "There is no left editor JSON to copy to the right editor."
            jsonFormatterStatusMessage = nil
            return
        }

        formattedJSON = jsonInput
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = "Copied left editor to right editor."
    }

    func copyRightJSONToLeft() {
        let text = formattedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            jsonFormatterErrorMessage = "There is no right editor JSON to copy to the left editor."
            jsonFormatterStatusMessage = nil
            return
        }

        jsonInput = formattedJSON
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = "Copied right editor to left editor."
    }

    func copyCurrentJSON() {
        let text = currentJSONText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            jsonFormatterErrorMessage = "There is no JSON text to copy yet."
            jsonFormatterStatusMessage = nil
            return
        }

        copyJSONText(text, emptyMessage: "There is no JSON text to copy yet.", statusMessage: "Copied JSON.")
    }

    func copyJSONInput() {
        copyLeftJSON()
    }

    func copyLeftJSON() {
        copyJSONText(
            jsonInput,
            emptyMessage: "There is no left editor JSON to copy yet.",
            statusMessage: "Copied left editor JSON."
        )
    }

    func copyFormattedJSON() {
        copyRightJSON()
    }

    func copyRightJSON() {
        copyJSONText(
            formattedJSON,
            emptyMessage: "There is no right editor JSON to copy yet.",
            statusMessage: "Copied right editor JSON."
        )
    }

    func copyHistoryItem(_ item: CopyHistoryItem) {
        if item.kind == .image, let imageData = item.imageData, let image = NSImage(data: imageData) {
            writeImageToClipboard(image, imageData: imageData)
            appendImageHistoryItem(data: imageData, description: item.content)
            return
        }

        writeTextToClipboard(item.content)
        appendCopyHistoryItem(kind: item.kind, content: item.content)
    }

    func runCopyHistoryImageOCR(_ item: CopyHistoryItem) {
        guard item.kind == .image,
              let imageData = item.imageData,
              let image = NSImage(data: imageData)
        else {
            lastErrorMessage = "The selected history item does not contain a readable image."
            return
        }

        Task {
            await performOCR(source: .imageHistory) {
                image
            }
        }
    }

    func deleteCopyHistoryItem(_ item: CopyHistoryItem) {
        copyHistoryItems.removeAll { $0.id == item.id }
        persistCopyHistory()
    }

    func useHistoryItemInLeftJSON(_ item: CopyHistoryItem) {
        updateLeftJSONText(item.content)
        jsonFormatterStatusMessage = "Loaded history item into left editor."
    }

    func useHistoryItemInRightJSON(_ item: CopyHistoryItem) {
        updateRightJSONText(item.content)
        jsonFormatterStatusMessage = "Loaded history item into right editor."
    }

    func clearCopyHistory() {
        copyHistoryItems.removeAll()
        persistCopyHistory()
    }

    func updateCronExpression(_ expression: String) {
        cronExpression = expression
        cronErrorMessage = nil
        cronStatusMessage = nil
    }

    func generateCronExpression() {
        cronExpression = cronExpressionService.generate(
            mode: cronGeneratorMode,
            minute: cronMinute,
            hour: cronHour,
            dayOfMonth: cronDayOfMonth,
            weekday: cronWeekday,
            intervalMinutes: cronIntervalMinutes
        )
        cronStatusMessage = "Generated cron expression."
        explainCronExpression()
    }

    func explainCronExpression() {
        do {
            let explanation = try cronExpressionService.explain(cronExpression)
            cronExplanationSummary = explanation.summary
            cronExplanationDetails = explanation.details
            cronTimeline = explanation.nextRuns
            cronErrorMessage = nil
            if cronStatusMessage == nil {
                cronStatusMessage = "Cron expression explained."
            }
        } catch {
            cronExplanationSummary = ""
            cronExplanationDetails = []
            cronTimeline = []
            cronErrorMessage = error.localizedDescription
            cronStatusMessage = nil
        }
    }

    func copyCronExpression() {
        let expression = cronExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            cronErrorMessage = "There is no cron expression to copy."
            cronStatusMessage = nil
            return
        }

        writeTextToClipboard(expression)
        cronErrorMessage = nil
        cronStatusMessage = "Copied cron expression."
    }

    func updateDiffLeftText(_ text: String) {
        diffLeftText = text
        diffErrorMessage = nil
        diffStatusMessage = nil
    }

    func updateDiffRightText(_ text: String) {
        diffRightText = text
        diffErrorMessage = nil
        diffStatusMessage = nil
    }

    func pasteDiffLeftFromClipboard() {
        pasteDiffText { text in
            diffLeftText = text
            diffStatusMessage = "Pasted into left side."
        }
    }

    func pasteDiffRightFromClipboard() {
        pasteDiffText { text in
            diffRightText = text
            diffStatusMessage = "Pasted into right side."
        }
    }

    func compareDiffText() {
        let result = textDiffService.diff(left: diffLeftText, right: diffRightText)
        diffRows = result.rows
        diffSummary = result.summary
        diffErrorMessage = nil
        diffStatusMessage = result.summary.totalDifferences == 0 ? "No differences found." : "Diff complete."
    }

    func swapDiffText() {
        swap(&diffLeftText, &diffRightText)
        compareDiffText()
    }

    func clearDiffText() {
        diffLeftText = ""
        diffRightText = ""
        diffRows = []
        diffSummary = TextDiffSummary(added: 0, deleted: 0, changed: 0, unchanged: 0)
        diffErrorMessage = nil
        diffStatusMessage = nil
    }

    func copyDiffSummary() {
        let text = "Added: \(diffSummary.added), Deleted: \(diffSummary.deleted), Changed: \(diffSummary.changed), Unchanged: \(diffSummary.unchanged)"
        writeTextToClipboard(text)
        diffStatusMessage = "Copied diff summary."
        diffErrorMessage = nil
    }

    private func pasteDiffText(_ update: (String) -> Void) {
        do {
            update(try textClipboardService.readText())
            diffErrorMessage = nil
        } catch {
            diffErrorMessage = error.localizedDescription
            diffStatusMessage = nil
        }
    }

    private func performOCR(
        source: OCRResult.Source,
        imageProvider: @escaping @MainActor () async throws -> NSImage
    ) async {
        isProcessing = true
        lastErrorMessage = nil

        do {
            let image = try await imageProvider()
            let payload = try await ocrService.recognizeText(from: image, languageMode: settings.ocrLanguageMode)
            let newResult = OCRResult(source: source, text: payload.text, recognizedAt: Date(), confidence: payload.confidence)
            result = newResult
            resultPanelController.present(result: newResult) { [weak self] in
                self?.copyResultText(newResult.text)
            }
        } catch is CancellationError {
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    private func copyResultText(_ text: String) {
        writeTextToClipboard(text)
        appendCopyHistoryItem(kind: .ocr, content: text)
    }

    private func handleInPlaceClipAction(_ capturedRegion: ScreenCaptureService.CapturedRegion) {
        switch capturedRegion.action {
        case .capture:
            clipboardService.writeImage(capturedRegion.image)
        case .pin:
            pinClipImage(capturedRegion.image, near: capturedRegion.rect)
        case .save:
            saveClipImage(capturedRegion.image, to: capturedRegion.saveURL)
        case .ocr:
            runInPlaceClipOCR(capturedRegion)
        }
    }

    private func pinClipImage(_ image: NSImage, near rect: CGRect) {
        pinnedClipPanelController.pin(image: image, near: rect) { [weak self] image, panelRect in
            self?.runPinnedClipOCR(image, near: panelRect)
        }
    }

    private func saveClipImage(_ image: NSImage, to saveURL: URL? = nil) {
        if let saveURL {
            writeClipImage(image, to: saveURL)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultClipImageName()
        panel.directoryURL = settings.defaultSaveDirectoryURL

        guard panel.runModal() == .OK, let url = panel.url, let data = pngData(for: image) else {
            return
        }

        writeClipImageData(data, to: url)
    }

    private func writeClipImage(_ image: NSImage, to url: URL) {
        guard let data = pngData(for: image) else {
            return
        }
        writeClipImageData(data, to: url)
    }

    private func writeClipImageData(_ data: Data, to url: URL) {
        do {
            try data.write(to: url)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func defaultClipImageName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Clip \(formatter.string(from: Date())).png"
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

    private func runInPlaceClipOCR(_ capturedRegion: ScreenCaptureService.CapturedRegion) {
        Task {
            do {
                let payload = try await ocrService.recognizeText(from: capturedRegion.image, languageMode: settings.ocrLanguageMode)
                let newResult = OCRResult(
                    source: .screenClip,
                    text: payload.text,
                    recognizedAt: Date(),
                    confidence: payload.confidence
                )
                result = newResult
                clipOCRResultPanelController.present(result: newResult, near: capturedRegion.rect) { [weak self] in
                    self?.copyResultText(newResult.text)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func runPinnedClipOCR(_ image: NSImage, near rect: CGRect) {
        Task {
            do {
                let payload = try await ocrService.recognizeText(from: image, languageMode: settings.ocrLanguageMode)
                let newResult = OCRResult(
                    source: .screenClip,
                    text: payload.text,
                    recognizedAt: Date(),
                    confidence: payload.confidence
                )
                result = newResult
                clipOCRResultPanelController.present(result: newResult, near: rect) { [weak self] in
                    self?.copyResultText(newResult.text)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func appendCopyHistoryItem(kind: CopyHistoryItem.Kind, content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return
        }

        let item = CopyHistoryItem(kind: kind, content: trimmedContent)
        copyHistoryItems = copyHistoryService.prepend(item, to: copyHistoryItems)
        persistCopyHistory()
    }

    private func appendImageHistoryItem(data: Data, description: String) {
        guard data.count <= settings.imageHistoryMaxSizeBytes else {
            return
        }

        let item = CopyHistoryItem(kind: .image, content: description, imageData: data)
        copyHistoryItems = copyHistoryService.prepend(item, to: copyHistoryItems)
        persistCopyHistory()
    }

    private func persistCopyHistory() {
        copyHistoryService.saveHistory(copyHistoryItems)
    }

    private func copyJSONText(_ text: String, emptyMessage: String, statusMessage: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            jsonFormatterErrorMessage = emptyMessage
            jsonFormatterStatusMessage = nil
            return
        }

        writeTextToClipboard(trimmedText)
        appendCopyHistoryItem(kind: .json, content: trimmedText)
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = statusMessage
    }

    private func writeTextToClipboard(_ text: String) {
        clipboardMonitorService.ignoreNextText(text)
        textClipboardService.writeText(text)
    }

    private func writeImageToClipboard(_ image: NSImage, imageData: Data) {
        clipboardMonitorService.ignoreNextImageData(imageData)
        clipboardService.writeImage(image)
    }

    private func applyClipboardMonitoringPreference() {
        if settings.clipboardMonitoringEnabled {
            clipboardMonitorService.start()
        } else {
            clipboardMonitorService.stop()
        }
    }

    private var currentJSONText: String {
        formattedJSON.isEmpty ? jsonInput : formattedJSON
    }
}
