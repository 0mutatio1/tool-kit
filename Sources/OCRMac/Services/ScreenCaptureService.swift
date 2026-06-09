import AppKit
import Foundation

@MainActor
final class ScreenCaptureService {
    struct SelectionResult: Sendable {
        let rect: CGRect
    }

    private let windowVisibilityService = AppWindowVisibilityService()

    enum ScreenCaptureError: LocalizedError {
        case missingScreen
        case invalidSelection
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .missingScreen:
                return "A display could not be found for clipping."
            case .invalidSelection:
                return "Select a larger area to capture."
            case .captureFailed:
                return "The selected area could not be captured."
            }
        }
    }

    func captureRegion(preferredScreen: NSScreen? = nil, restoreWindowsAfterCapture: Bool = true) async throws -> NSImage {
        guard !NSScreen.screens.isEmpty else {
            throw ScreenCaptureError.missingScreen
        }

        _ = preferredScreen

        let hiddenWindows = windowVisibilityService.hideRegularWindows()
        defer {
            if restoreWindowsAfterCapture {
                windowVisibilityService.restoreWindows(hiddenWindows)
            }
        }

        try await Task.sleep(for: .milliseconds(120))

        let captureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        defer {
            try? FileManager.default.removeItem(at: captureURL)
        }

        try await runInteractiveCapture(to: captureURL)

        guard let image = NSImage(contentsOf: captureURL) else {
            throw ScreenCaptureError.captureFailed
        }

        guard image.size.width > 4, image.size.height > 4 else {
            throw ScreenCaptureError.invalidSelection
        }

        return image
    }

    private func runInteractiveCapture(to fileURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", fileURL.path]

        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                if process.terminationReason == .exit, process.terminationStatus == 0 {
                    continuation.resume()
                } else if process.terminationReason == .exit, process.terminationStatus == 1 {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: ScreenCaptureError.captureFailed)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
