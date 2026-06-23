import AppKit
import Foundation

@MainActor
final class ScreenCaptureService {
    struct CapturedRegion: Sendable {
        let rect: CGRect
        let image: NSImage
        let action: ClipCaptureAction
        let saveURL: URL?
    }

    struct SelectionResult: Sendable {
        let rect: CGRect
        let annotations: [ClipOverlayAnnotation]
        let action: ClipCaptureAction
        let saveURL: URL?
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

    func captureRegion(
        preferredScreen: NSScreen? = nil,
        defaultSaveDirectory: URL? = nil,
        restoreWindowsAfterCapture: Bool = true,
        handleInPlaceResult: (@MainActor (CapturedRegion) async -> Void)? = nil
    ) async throws -> CapturedRegion {
        guard !NSScreen.screens.isEmpty else {
            throw ScreenCaptureError.missingScreen
        }

        let hiddenWindows = windowVisibilityService.hideRegularWindows()
        defer {
            if restoreWindowsAfterCapture {
                windowVisibilityService.restoreWindows(hiddenWindows)
            }
        }

        try await Task.sleep(for: .milliseconds(120))

        let selection = try await ScreenSelectionWindowController.capture(
            preferredScreen: preferredScreen,
            defaultSaveDirectory: defaultSaveDirectory,
            captureInPlace: { [weak self] selection in
                guard let self else {
                    throw ScreenCaptureError.captureFailed
                }
                return try await self.capturedRegion(from: selection)
            },
            handleInPlaceResult: { capturedRegion in
                await handleInPlaceResult?(capturedRegion)
            }
        )

        guard selection.rect.width > 4, selection.rect.height > 4 else {
            throw ScreenCaptureError.invalidSelection
        }

        return try await capturedRegion(from: selection)
    }

    func captureImage(in selectionRect: CGRect) async throws -> NSImage {
        guard selectionRect.width > 0, selectionRect.height > 0 else {
            throw ScreenCaptureError.captureFailed
        }

        let screens = NSScreen.screens
            .map { screen in (screen, selectionRect.intersection(screen.frame)) }
            .filter { !$0.1.isNull && $0.1.width > 0 && $0.1.height > 0 }

        guard !screens.isEmpty else {
            throw ScreenCaptureError.captureFailed
        }

        let outputScale = max(screens.map { pixelScale(for: $0.0).maxScale }.max() ?? 1, 1)
        let outputPixelWidth = max(Int((selectionRect.width * outputScale).rounded(.up)), 1)
        let outputPixelHeight = max(Int((selectionRect.height * outputScale).rounded(.up)), 1)
        var didDraw = false

        guard let context = CGContext(
            data: nil,
            width: outputPixelWidth,
            height: outputPixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenCaptureError.captureFailed
        }

        context.interpolationQuality = .high

        for (screen, intersection) in screens {
            guard
                let displayID = screen.displayID,
                let cgImage = CGDisplayCreateImage(displayID, rect: displayCaptureRect(for: intersection, on: screen))
            else {
                continue
            }

            let destination = CGRect(
                x: (intersection.minX - selectionRect.minX) * outputScale,
                y: (intersection.minY - selectionRect.minY) * outputScale,
                width: intersection.width * outputScale,
                height: intersection.height * outputScale
            ).integral
            context.draw(cgImage, in: destination)
            didDraw = true
        }

        guard didDraw else {
            throw ScreenCaptureError.captureFailed
        }

        guard let cgImage = context.makeImage() else {
            throw ScreenCaptureError.captureFailed
        }

        return NSImage(cgImage: cgImage, size: selectionRect.size)
    }

    private func displayCaptureRect(for intersection: CGRect, on screen: NSScreen) -> CGRect {
        let scale = pixelScale(for: screen)
        return CGRect(
            x: (intersection.minX - screen.frame.minX) * scale.x,
            y: (screen.frame.maxY - intersection.maxY) * scale.y,
            width: intersection.width * scale.x,
            height: intersection.height * scale.y
        ).integral
    }

    private func pixelScale(for screen: NSScreen) -> (x: CGFloat, y: CGFloat, maxScale: CGFloat) {
        guard let displayID = screen.displayID else {
            let scale = max(screen.backingScaleFactor, 1)
            return (scale, scale, scale)
        }

        let scaleX = max(CGFloat(CGDisplayPixelsWide(displayID)) / max(screen.frame.width, 1), 1)
        let scaleY = max(CGFloat(CGDisplayPixelsHigh(displayID)) / max(screen.frame.height, 1), 1)
        return (scaleX, scaleY, max(scaleX, scaleY))
    }

    private func render(_ baseImage: NSImage, annotations: [ClipOverlayAnnotation], in screenRect: CGRect) -> NSImage {
        ClipAnnotationRenderer.render(baseImage: baseImage, annotations: annotations, in: screenRect)
    }

    private func capturedRegion(from selection: SelectionResult) async throws -> CapturedRegion {
        let capturedImage = try await captureImage(in: selection.rect)
        let image = render(capturedImage, annotations: selection.annotations, in: selection.rect)
        return CapturedRegion(rect: selection.rect, image: image, action: selection.action, saveURL: selection.saveURL)
    }

}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
