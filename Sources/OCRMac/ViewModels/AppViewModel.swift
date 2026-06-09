import AppKit
import Foundation

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

    let clipShortcutDisplay = GlobalHotKeyManager.Shortcut.defaultClipShortcut.displayText
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

    private let ocrService = OCRService()
    private let clipboardService = ClipboardImageService()
    private let textClipboardService = TextClipboardService()
    private let jsonFormatterService = JSONFormatterService()
    private let copyHistoryService = CopyHistoryService()
    private let permissionService = PermissionService()
    private let screenCaptureService = ScreenCaptureService()
    private let hotKeyManager = GlobalHotKeyManager()
    private let resultPanelController = ResultPanelController()
    private let capturedImagePanelController = CapturedImagePanelController()
    private var hasConfiguredHotKey = false

    init() {
        copyHistoryItems = copyHistoryService.loadHistory()
    }

    func configureHotKeyIfNeeded() {
        guard !hasConfiguredHotKey else {
            return
        }

        hasConfiguredHotKey = true
        hotKeyManager.onKeyDown = { [weak self] in
            self?.runScreenClipCapture(preferredScreen: NSScreen.screenContainingMouse, keepWindowsHiddenAfterCapture: true)
        }
        hotKeyManager.register()
    }

    func runClipboardOCR() {
        Task {
            await performOCR(source: .clipboard) {
                try self.clipboardService.readImage()
            }
        }
    }

    func runScreenClipOCR(preferredScreen: NSScreen? = nil, keepWindowsHiddenAfterCapture: Bool = false) {
        runScreenClipCapture(preferredScreen: preferredScreen, keepWindowsHiddenAfterCapture: keepWindowsHiddenAfterCapture)
    }

    func runScreenClipCapture(preferredScreen: NSScreen? = nil, keepWindowsHiddenAfterCapture: Bool = false) {
        Task {
            isProcessing = true
            lastErrorMessage = nil

            do {
                try self.permissionService.ensureScreenCapturePermission()
                let image = try await self.screenCaptureService.captureRegion(
                    preferredScreen: preferredScreen,
                    restoreWindowsAfterCapture: !keepWindowsHiddenAfterCapture
                )
                isProcessing = false
                presentCapturedImage(image)
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
        formattedJSON = ""
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
        textClipboardService.writeText(item.content)
        appendCopyHistoryItem(kind: item.kind, content: item.content)
    }

    func deleteCopyHistoryItem(_ item: CopyHistoryItem) {
        copyHistoryItems.removeAll { $0.id == item.id }
        persistCopyHistory()
    }

    func clearCopyHistory() {
        copyHistoryItems.removeAll()
        persistCopyHistory()
    }

    private func performOCR(
        source: OCRResult.Source,
        imageProvider: @escaping @MainActor () async throws -> NSImage
    ) async {
        isProcessing = true
        lastErrorMessage = nil

        do {
            let image = try await imageProvider()
            let payload = try await ocrService.recognizeText(from: image)
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
        textClipboardService.writeText(text)
        appendCopyHistoryItem(kind: .ocr, content: text)
    }

    private func presentCapturedImage(_ image: NSImage) {
        capturedImagePanelController.present(
            image: image,
            onCopyImage: { [weak self] in
                self?.clipboardService.writeImage(image)
            },
            onRunOCR: { [weak self] in
                guard let self else {
                    return
                }

                capturedImagePanelController.close()
                Task {
                    await performOCR(source: .screenClip) {
                        image
                    }
                }
            }
        )
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

        textClipboardService.writeText(trimmedText)
        appendCopyHistoryItem(kind: .json, content: trimmedText)
        jsonFormatterErrorMessage = nil
        jsonFormatterStatusMessage = statusMessage
    }

    private var currentJSONText: String {
        formattedJSON.isEmpty ? jsonInput : formattedJSON
    }
}
