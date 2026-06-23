import AppKit
@testable import toolKit
import XCTest

final class JSONFormatterServiceTests: XCTestCase {
    func testFormatsMarkdownFencedJSON() throws {
        let service = JSONFormatterService()

        let formatted = try service.format("""
        ```json
        {"name":"OCRMac","enabled":true}
        ```
        """)

        XCTAssertTrue(formatted.contains("\"enabled\" : true"))
        XCTAssertTrue(formatted.contains("\"name\" : \"OCRMac\""))
    }

    func testRepairsCommonLooseJSON() throws {
        let service = JSONFormatterService()

        let repaired = try service.repairAndFormat("""
        {
          // comment
          name: 'OCRMac',
        }
        """)

        XCTAssertTrue(repaired.contains("\"name\" : \"OCRMac\""))
        XCTAssertNoThrow(try service.validate(repaired))
    }
}

final class CronExpressionServiceTests: XCTestCase {
    func testGeneratesIntervalExpression() {
        let service = CronExpressionService()

        let expression = service.generate(
            mode: .everyNMinutes,
            minute: 0,
            hour: 0,
            dayOfMonth: 1,
            weekday: 0,
            intervalMinutes: 15
        )

        XCTAssertEqual(expression, "*/15 * * * *")
    }

    func testExplainsExpressionWithUpcomingRuns() throws {
        let service = CronExpressionService()
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 9, minute: 0)))

        let explanation = try service.explain("*/30 * * * *", from: start, count: 3)

        XCTAssertFalse(explanation.summary.isEmpty)
        XCTAssertEqual(explanation.details.count, 5)
        XCTAssertEqual(explanation.nextRuns.count, 3)
    }
}

final class TextDiffServiceTests: XCTestCase {
    func testSummarizesChangedAndInsertedRows() {
        let service = TextDiffService()

        let result = service.diff(left: "alpha\nbeta\ngamma", right: "alpha\nbetter\ngamma\ndelta")

        XCTAssertEqual(result.summary.unchanged, 2)
        XCTAssertEqual(result.summary.changed, 1)
        XCTAssertEqual(result.summary.added, 1)
        XCTAssertEqual(result.summary.deleted, 0)
    }
}

@MainActor
final class CopyHistoryServiceTests: XCTestCase {
    func testRetentionAndDeduplicationUseConfiguredLimit() {
        let suiteName = "toolKitTests.CopyHistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let service = CopyHistoryService(defaults: defaults, maximumItemCount: 2)

        var items: [CopyHistoryItem] = []
        items = service.prepend(CopyHistoryItem(kind: .clipboard, content: "first"), to: items)
        items = service.prepend(CopyHistoryItem(kind: .clipboard, content: "second"), to: items)
        items = service.prepend(CopyHistoryItem(kind: .clipboard, content: "first"), to: items)

        XCTAssertEqual(items.map(\.content), ["first", "second"])

        items = service.prepend(CopyHistoryItem(kind: .json, content: "third"), to: items)
        service.saveHistory(items)

        XCTAssertEqual(service.loadHistory().map(\.content), ["third", "first"])
    }
}

final class ClipAnnotationRendererTests: XCTestCase {
    func testRenderedImageKeepsBasePointSize() throws {
        let baseImage = makeImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotations = [
            ClipOverlayAnnotation(
                kind: .rectangle,
                rect: CGRect(x: 10, y: 10, width: 40, height: 30),
                points: [],
                text: "",
                style: .redStroke
            ),
            ClipOverlayAnnotation(
                kind: .text,
                rect: CGRect(x: 54, y: 18, width: 54, height: 28),
                points: [],
                text: "Hi",
                style: .text
            )
        ]

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: annotations,
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertEqual(rendered.size.width, 120)
        XCTAssertEqual(rendered.size.height, 80)
        XCTAssertFalse(rendered.representations.isEmpty)
    }

    func testBlurPrivacyAnnotationChangesSelectedPixels() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .blur,
            rect: CGRect(x: 36, y: 18, width: 48, height: 44),
            points: [],
            text: "",
            style: .blur
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertGreaterThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 41, y: 28),
                    CGPoint(x: 49, y: 40),
                    CGPoint(x: 58, y: 48),
                    CGPoint(x: 72, y: 34)
                ]
            ),
            0.8
        )
    }

    func testMosaicPrivacyAnnotationChangesSelectedPixels() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .mosaic,
            rect: CGRect(x: 36, y: 18, width: 48, height: 44),
            points: [],
            text: "",
            style: .mosaic
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertGreaterThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 41, y: 28),
                    CGPoint(x: 49, y: 40),
                    CGPoint(x: 58, y: 48),
                    CGPoint(x: 72, y: 34)
                ]
            ),
            0.8
        )
    }

    func testBlurTrackPrivacyAnnotationChangesPaintedPixels() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .blur,
            rect: .zero,
            points: [
                CGPoint(x: 28, y: 40),
                CGPoint(x: 44, y: 40),
                CGPoint(x: 60, y: 40),
                CGPoint(x: 76, y: 40),
                CGPoint(x: 92, y: 40)
            ],
            text: "",
            style: .blur
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertGreaterThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 38, y: 40),
                    CGPoint(x: 56, y: 40),
                    CGPoint(x: 74, y: 40)
                ]
            ),
            0.8
        )
    }

    func testBlurTrackPrivacyAnnotationKeepsUnpaintedPixels() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .blur,
            rect: .zero,
            points: [
                CGPoint(x: 28, y: 40),
                CGPoint(x: 44, y: 40),
                CGPoint(x: 60, y: 40),
                CGPoint(x: 76, y: 40),
                CGPoint(x: 92, y: 40)
            ],
            text: "",
            style: .blur
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertLessThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 38, y: 5),
                    CGPoint(x: 56, y: 75),
                    CGPoint(x: 116, y: 10)
                ]
            ),
            0.05
        )
    }

    func testBlurTrackFollowsBentMousePathWithoutCuttingCorner() throws {
        let baseImage = makeCheckerboardImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .blur,
            rect: .zero,
            points: [
                CGPoint(x: 24, y: 16),
                CGPoint(x: 24, y: 60),
                CGPoint(x: 88, y: 60)
            ],
            text: "",
            style: ClipOverlayAnnotation.Style(
                red: ClipOverlayAnnotation.Style.blur.red,
                green: ClipOverlayAnnotation.Style.blur.green,
                blue: ClipOverlayAnnotation.Style.blur.blue,
                alpha: ClipOverlayAnnotation.Style.blur.alpha,
                lineWidth: 8
            )
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertGreaterThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 24, y: 36),
                    CGPoint(x: 56, y: 60)
                ]
            ),
            0.2
        )
        XCTAssertLessThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 38, y: 46)
                ]
            ),
            0.05
        )
    }

    func testMosaicTrackPrivacyAnnotationChangesPaintedPixels() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .mosaic,
            rect: .zero,
            points: [
                CGPoint(x: 28, y: 40),
                CGPoint(x: 44, y: 40),
                CGPoint(x: 60, y: 40),
                CGPoint(x: 76, y: 40),
                CGPoint(x: 92, y: 40)
            ],
            text: "",
            style: .mosaic
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertGreaterThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 38, y: 40),
                    CGPoint(x: 56, y: 40),
                    CGPoint(x: 74, y: 40)
                ]
            ),
            0.8
        )
    }

    func testMosaicTrackPrivacyAnnotationKeepsUnpaintedPixels() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .mosaic,
            rect: .zero,
            points: [
                CGPoint(x: 28, y: 40),
                CGPoint(x: 44, y: 40),
                CGPoint(x: 60, y: 40),
                CGPoint(x: 76, y: 40),
                CGPoint(x: 92, y: 40)
            ],
            text: "",
            style: .mosaic
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertLessThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 38, y: 5),
                    CGPoint(x: 56, y: 75),
                    CGPoint(x: 116, y: 10)
                ]
            ),
            0.05
        )
    }

    func testBlurAndMosaicTracksRenderDifferentPrivacyEffects() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let points = [
            CGPoint(x: 28, y: 40),
            CGPoint(x: 44, y: 40),
            CGPoint(x: 60, y: 40),
            CGPoint(x: 76, y: 40),
            CGPoint(x: 92, y: 40)
        ]
        let blur = ClipOverlayAnnotation(
            kind: .blur,
            rect: .zero,
            points: points,
            text: "",
            style: .blur
        )
        let mosaic = ClipOverlayAnnotation(
            kind: .mosaic,
            rect: .zero,
            points: points,
            text: "",
            style: .mosaic
        )

        let blurRendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [blur],
            in: CGRect(origin: .zero, size: baseImage.size)
        )
        let mosaicRendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [mosaic],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertGreaterThan(
            try maximumColorDistance(
                between: blurRendered,
                and: mosaicRendered,
                points: [
                    CGPoint(x: 38, y: 40),
                    CGPoint(x: 56, y: 40),
                    CGPoint(x: 74, y: 40)
                ]
            ),
            0.05
        )
    }

    func testSinglePointBlurTrackChangesStartPixels() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .blur,
            rect: .zero,
            points: [CGPoint(x: 60, y: 40)],
            text: "",
            style: .blur
        )

        let rendered = ClipAnnotationRenderer.render(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        )

        XCTAssertGreaterThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 60, y: 40),
                    CGPoint(x: 68, y: 40)
                ]
            ),
            0.8
        )
        XCTAssertLessThan(
            try maximumColorDistance(
                between: baseImage,
                and: rendered,
                points: [
                    CGPoint(x: 10, y: 40),
                    CGPoint(x: 110, y: 40)
                ]
            ),
            0.05
        )
    }

    func testPrivacyOverlayShowsEffectOnlyOnTrack() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .blur,
            rect: .zero,
            points: [
                CGPoint(x: 28, y: 40),
                CGPoint(x: 44, y: 40),
                CGPoint(x: 60, y: 40),
                CGPoint(x: 76, y: 40),
                CGPoint(x: 92, y: 40)
            ],
            text: "",
            style: .blur
        )

        let overlay = try XCTUnwrap(ClipAnnotationRenderer.renderPrivacyOverlay(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        ))

        XCTAssertGreaterThan(try alpha(in: overlay, at: CGPoint(x: 60, y: 40)), 0.95)
        XCTAssertLessThan(try alpha(in: overlay, at: CGPoint(x: 60, y: 5)), 0.05)
    }

    func testPrivacyOverlayKeepsAsymmetricTrackAtMouseY() throws {
        let baseImage = makeStripedImage(size: CGSize(width: 120, height: 80), scale: 2)
        let annotation = ClipOverlayAnnotation(
            kind: .blur,
            rect: .zero,
            points: [
                CGPoint(x: 20, y: 16),
                CGPoint(x: 80, y: 16)
            ],
            text: "",
            style: ClipOverlayAnnotation.Style(
                red: ClipOverlayAnnotation.Style.blur.red,
                green: ClipOverlayAnnotation.Style.blur.green,
                blue: ClipOverlayAnnotation.Style.blur.blue,
                alpha: ClipOverlayAnnotation.Style.blur.alpha,
                lineWidth: 8
            )
        )

        let overlay = try XCTUnwrap(ClipAnnotationRenderer.renderPrivacyOverlay(
            baseImage: baseImage,
            annotations: [annotation],
            in: CGRect(origin: .zero, size: baseImage.size)
        ))

        XCTAssertGreaterThan(try alpha(in: overlay, at: CGPoint(x: 50, y: 16)), 0.95)
        XCTAssertLessThan(try alpha(in: overlay, at: CGPoint(x: 50, y: 64)), 0.05)
    }

    private func makeImage(size: CGSize, scale: CGFloat) -> NSImage {
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        return NSImage(cgImage: context.makeImage()!, size: size)
    }

    private func makeStripedImage(size: CGSize, scale: CGFloat) -> NSImage {
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        for x in 0..<pixelWidth {
            let value: CGFloat = (x / 6).isMultiple(of: 2) ? 0.04 : 0.96
            context.setFillColor(NSColor(calibratedWhite: value, alpha: 1).cgColor)
            context.fill(CGRect(x: x, y: 0, width: 1, height: pixelHeight))
        }

        return NSImage(cgImage: context.makeImage()!, size: size)
    }

    private func makeCheckerboardImage(size: CGSize, scale: CGFloat) -> NSImage {
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let value: CGFloat = ((x / 6) + (y / 6)).isMultiple(of: 2) ? 0.04 : 0.96
                context.setFillColor(NSColor(calibratedWhite: value, alpha: 1).cgColor)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        return NSImage(cgImage: context.makeImage()!, size: size)
    }

    private func color(in image: NSImage, at point: CGPoint) throws -> NSColor {
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let scaleX = CGFloat(bitmap.pixelsWide) / max(image.size.width, 1)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(image.size.height, 1)
        let x = min(max(Int((point.x * scaleX).rounded(.down)), 0), bitmap.pixelsWide - 1)
        let imageY = min(max(Int((point.y * scaleY).rounded(.down)), 0), bitmap.pixelsHigh - 1)
        let y = bitmap.pixelsHigh - 1 - imageY
        return try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

    private func colorDistance(_ first: NSColor, _ second: NSColor) -> CGFloat {
        abs(first.redComponent - second.redComponent)
            + abs(first.greenComponent - second.greenComponent)
            + abs(first.blueComponent - second.blueComponent)
    }

    private func maximumColorDistance(between first: NSImage, and second: NSImage, points: [CGPoint]) throws -> CGFloat {
        try points
            .map { point in
                try colorDistance(color(in: first, at: point), color(in: second, at: point))
            }
            .max() ?? 0
    }

    private func alpha(in image: NSImage, at point: CGPoint) throws -> CGFloat {
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let scaleX = CGFloat(bitmap.pixelsWide) / max(image.size.width, 1)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(image.size.height, 1)
        let x = min(max(Int((point.x * scaleX).rounded(.down)), 0), bitmap.pixelsWide - 1)
        let imageY = min(max(Int((point.y * scaleY).rounded(.down)), 0), bitmap.pixelsHigh - 1)
        let y = bitmap.pixelsHigh - 1 - imageY
        return try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
    }

}
