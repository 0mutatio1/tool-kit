import AppKit
import CoreImage
import Foundation

enum ClipAnnotationRenderer {
    static func render(baseImage: NSImage, annotations: [ClipOverlayAnnotation], in screenRect: CGRect) -> NSImage {
        guard !annotations.isEmpty else {
            return baseImage
        }

        let scale = imageScale(for: baseImage)
        let geometry = RenderGeometry(size: baseImage.size, screenRect: screenRect)
        let privacyShapes = PrivacyShape.shapes(from: annotations)
        let nonPrivacyAnnotations = annotations.filter { $0.kind != .blur && $0.kind != .mosaic }
        let baseWithPrivacy = privacyShapes.isEmpty
            ? baseImage
            : PrivacyRenderer.render(baseImage: baseImage, shapes: privacyShapes, in: screenRect) ?? baseImage

        guard !nonPrivacyAnnotations.isEmpty else {
            return baseWithPrivacy
        }

        guard let image = makeBitmapImage(size: baseImage.size, scale: scale, drawing: {
            baseWithPrivacy.draw(in: CGRect(origin: .zero, size: baseImage.size))

            for annotation in nonPrivacyAnnotations {
                draw(annotation, geometry: geometry)
            }
        }) else {
            return baseImage
        }

        return image
    }

    static func renderPrivacyOverlay(baseImage: NSImage, annotations: [ClipOverlayAnnotation], in screenRect: CGRect) -> NSImage? {
        let privacyShapes = PrivacyShape.shapes(from: annotations)
        guard !privacyShapes.isEmpty else {
            return nil
        }

        return PrivacyRenderer.renderOverlay(baseImage: baseImage, shapes: privacyShapes, in: screenRect)
    }

    private static func draw(
        _ annotation: ClipOverlayAnnotation,
        geometry: RenderGeometry
    ) {
        let color = NSColor(
            calibratedRed: annotation.style.red,
            green: annotation.style.green,
            blue: annotation.style.blue,
            alpha: annotation.style.alpha
        )
        color.setStroke()
        color.setFill()

        switch annotation.kind {
        case .rectangle:
            let path = NSBezierPath(rect: geometry.rect(annotation.rect))
            path.lineWidth = annotation.style.lineWidth
            path.stroke()
        case .arrow:
            stroke(points: annotation.points, geometry: geometry, style: annotation.style)
            drawArrowHead(points: annotation.points, geometry: geometry, style: annotation.style)
        case .pencil, .marker:
            stroke(points: annotation.points, geometry: geometry, style: annotation.style)
        case .mosaic, .blur:
            break
        case .text:
            drawText(annotation.text, in: geometry.rect(annotation.rect), style: annotation.style)
        }
    }

    private static func stroke(
        points: [CGPoint],
        geometry: RenderGeometry,
        style: ClipOverlayAnnotation.Style
    ) {
        guard let first = points.first else {
            return
        }

        let path = NSBezierPath()
        path.move(to: geometry.point(first))
        let imagePoints = points.map { geometry.point($0) }
        if imagePoints.count == 1 {
            path.line(to: imagePoints[0])
        } else {
            imagePoints.dropFirst().forEach { path.line(to: $0) }
        }
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawArrowHead(
        points: [CGPoint],
        geometry: RenderGeometry,
        style: ClipOverlayAnnotation.Style
    ) {
        guard points.count >= 2, let start = points.first, let end = points.last else {
            return
        }

        let imageStart = geometry.point(start)
        let imageEnd = geometry.point(end)
        let angle = atan2(imageEnd.y - imageStart.y, imageEnd.x - imageStart.x)
        let length: CGFloat = 18
        let spread: CGFloat = .pi / 7
        let left = CGPoint(x: imageEnd.x - length * cos(angle - spread), y: imageEnd.y - length * sin(angle - spread))
        let right = CGPoint(x: imageEnd.x - length * cos(angle + spread), y: imageEnd.y - length * sin(angle + spread))

        let path = NSBezierPath()
        path.move(to: left)
        path.line(to: imageEnd)
        path.line(to: right)
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private struct RenderGeometry {
        let screenRect: CGRect
        let scaleX: CGFloat
        let scaleY: CGFloat

        init(size: CGSize, screenRect: CGRect) {
            self.screenRect = screenRect
            scaleX = size.width / max(screenRect.width, 1)
            scaleY = size.height / max(screenRect.height, 1)
        }

        func point(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - screenRect.minX) * scaleX,
                y: (point.y - screenRect.minY) * scaleY
            )
        }

        func rect(_ rect: CGRect) -> CGRect {
            let standardized = rect.standardized
            return CGRect(
                x: (standardized.minX - screenRect.minX) * scaleX,
                y: (standardized.minY - screenRect.minY) * scaleY,
                width: standardized.width * scaleX,
                height: standardized.height * scaleY
            )
        }
    }

    private enum PrivacyEffectKind {
        case blur
        case mosaic

        init?(_ kind: ClipOverlayAnnotation.Kind) {
            switch kind {
            case .blur:
                self = .blur
            case .mosaic:
                self = .mosaic
            case .rectangle, .arrow, .pencil, .marker, .text:
                return nil
            }
        }

        func effectImage(from image: NSImage) -> NSImage? {
            switch self {
            case .blur:
                return blurredPrivacyImage(from: image)
            case .mosaic:
                return mosaicPrivacyImage(from: image)
            }
        }
    }

    private enum PrivacyShape {
        case track(effect: PrivacyEffectKind, points: [CGPoint], lineWidth: CGFloat)
        case rect(effect: PrivacyEffectKind, rect: CGRect, lineWidth: CGFloat)

        var effect: PrivacyEffectKind {
            switch self {
            case .track(let effect, _, _), .rect(let effect, _, _):
                return effect
            }
        }

        static func shapes(from annotations: [ClipOverlayAnnotation]) -> [PrivacyShape] {
            annotations.compactMap { annotation in
                guard let effect = PrivacyEffectKind(annotation.kind) else {
                    return nil
                }

                if annotation.points.isEmpty {
                    return .rect(effect: effect, rect: annotation.rect, lineWidth: annotation.style.lineWidth)
                }

                return .track(effect: effect, points: annotation.points, lineWidth: annotation.style.lineWidth)
            }
        }
    }

    private enum PrivacyRenderer {
        static func render(baseImage: NSImage, shapes: [PrivacyShape], in screenRect: CGRect) -> NSImage? {
            guard let imageCG = cgImage(from: baseImage) else {
                return nil
            }

            let input = CIImage(cgImage: imageCG)
            let pixelSize = CGSize(width: imageCG.width, height: imageCG.height)
            var composited = input
            let context = CIContext()

            for effect in [PrivacyEffectKind.blur, .mosaic] {
                let effectShapes = shapes.filter { $0.effect == effect }
                guard !effectShapes.isEmpty else {
                    continue
                }

                guard
                    let privacyImage = effect.effectImage(from: baseImage),
                    let privacyCG = cgImage(from: privacyImage),
                    let maskImage = maskImage(pixelSize: pixelSize, shapes: effectShapes, screenRect: screenRect),
                    let maskCG = cgImage(from: maskImage),
                    let blendFilter = CIFilter(name: "CIBlendWithMask")
                else {
                    continue
                }

                blendFilter.setValue(CIImage(cgImage: privacyCG).cropped(to: input.extent), forKey: kCIInputImageKey)
                blendFilter.setValue(composited, forKey: kCIInputBackgroundImageKey)
                blendFilter.setValue(CIImage(cgImage: maskCG).cropped(to: input.extent), forKey: kCIInputMaskImageKey)
                composited = blendFilter.outputImage?.cropped(to: input.extent) ?? composited
            }

            guard let outputCG = context.createCGImage(composited, from: input.extent) else {
                return nil
            }

            return NSImage(cgImage: outputCG, size: baseImage.size)
        }

        static func renderOverlay(baseImage: NSImage, shapes: [PrivacyShape], in screenRect: CGRect) -> NSImage? {
            guard
                let privacyImage = render(baseImage: baseImage, shapes: shapes, in: screenRect),
                let privacyCG = cgImage(from: privacyImage),
                let baseCG = cgImage(from: baseImage),
                let maskImage = maskImage(
                    pixelSize: CGSize(width: baseCG.width, height: baseCG.height),
                    shapes: shapes,
                    screenRect: screenRect
                ),
                let maskCG = cgImage(from: maskImage),
                let blendFilter = CIFilter(name: "CIBlendWithMask")
            else {
                return nil
            }

            let input = CIImage(cgImage: privacyCG)
            let clear = CIImage(color: .clear).cropped(to: input.extent)
            blendFilter.setValue(input, forKey: kCIInputImageKey)
            blendFilter.setValue(clear, forKey: kCIInputBackgroundImageKey)
            blendFilter.setValue(CIImage(cgImage: maskCG).cropped(to: input.extent), forKey: kCIInputMaskImageKey)

            guard
                let output = blendFilter.outputImage?.cropped(to: input.extent),
                let outputCG = CIContext().createCGImage(output, from: input.extent)
            else {
                return nil
            }

            return NSImage(cgImage: outputCG, size: baseImage.size)
        }

        private static func maskImage(pixelSize: CGSize, shapes: [PrivacyShape], screenRect: CGRect) -> NSImage? {
            let geometry = RenderGeometry(size: pixelSize, screenRect: screenRect)
            return makeBitmapImage(size: pixelSize, scale: 1, drawing: {
                NSColor.black.setFill()
                CGRect(origin: .zero, size: pixelSize).fill()
                NSColor.white.setStroke()
                NSColor.white.setFill()

                for shape in shapes {
                    draw(shape, geometry: geometry)
                }
            })
        }

        private static func draw(_ shape: PrivacyShape, geometry: RenderGeometry) {
            switch shape {
            case .rect(_, let rect, _):
                NSBezierPath(roundedRect: geometry.rect(rect), xRadius: 5, yRadius: 5).fill()
            case .track(_, let points, let lineWidth):
                drawTrack(points: points, lineWidth: lineWidth, geometry: geometry)
            }
        }

        private static func drawTrack(points: [CGPoint], lineWidth: CGFloat, geometry: RenderGeometry) {
            guard let first = points.first else {
                return
            }

            let scaledLineWidth = lineWidth * max(geometry.scaleX, geometry.scaleY)
            if points.count == 1 {
                let center = geometry.point(first)
                let radius = max(scaledLineWidth / 2, 6)
                NSBezierPath(
                    ovalIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                ).fill()
                return
            }

            let path = NSBezierPath()
            path.move(to: geometry.point(first))
            points.dropFirst().forEach { path.line(to: geometry.point($0)) }
            path.lineWidth = scaledLineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    private static func blurredPrivacyImage(from image: NSImage) -> NSImage? {
        guard
            let cgImage = cgImage(from: image),
            let clampFilter = CIFilter(name: "CIAffineClamp"),
            let blurFilter = CIFilter(name: "CIGaussianBlur")
        else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        clampFilter.setValue(input, forKey: kCIInputImageKey)
        clampFilter.setValue(CGAffineTransform.identity, forKey: kCIInputTransformKey)

        guard let clamped = clampFilter.outputImage else {
            return nil
        }

        let radius = max(8, min(input.extent.width, input.extent.height) / 36)
        blurFilter.setValue(clamped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard
            let output = blurFilter.outputImage?.cropped(to: input.extent),
            let blurredCGImage = CIContext().createCGImage(output, from: input.extent)
        else {
            return nil
        }

        return NSImage(cgImage: blurredCGImage, size: image.size)
    }

    private static func mosaicPrivacyImage(from image: NSImage) -> NSImage? {
        guard
            let cgImage = cgImage(from: image),
            let filter = CIFilter(name: "CIPixellate")
        else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        filter.setValue(input, forKey: kCIInputImageKey)
        let blockSize = max(12, min(input.extent.width, input.extent.height) / 26)
        filter.setValue(blockSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: input.extent.midX, y: input.extent.midY), forKey: kCIInputCenterKey)

        guard
            let pixelated = filter.outputImage?.cropped(to: input.extent),
            let colorFilter = CIFilter(name: "CIColorControls")
        else {
            return nil
        }

        colorFilter.setValue(pixelated, forKey: kCIInputImageKey)
        colorFilter.setValue(0, forKey: kCIInputSaturationKey)
        colorFilter.setValue(0.44, forKey: kCIInputContrastKey)
        colorFilter.setValue(0.04, forKey: kCIInputBrightnessKey)

        guard
            let output = colorFilter.outputImage?.cropped(to: input.extent),
            let mosaicCGImage = CIContext().createCGImage(output, from: input.extent)
        else {
            return nil
        }

        return NSImage(cgImage: mosaicCGImage, size: image.size)
    }

    private static func drawText(_ text: String, in rect: CGRect, style: ClipOverlayAnnotation.Style) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(15, min(30, rect.height * 0.48)), weight: .semibold),
            .foregroundColor: NSColor(
                calibratedRed: style.red,
                green: style.green,
                blue: style.blue,
                alpha: 1
            ),
            .paragraphStyle: paragraphStyle
        ]
        text.draw(in: rect.insetBy(dx: 6, dy: 6), withAttributes: attributes)
    }

    private static func makeBitmapImage(size: CGSize, scale: CGFloat, drawing: () -> Void) -> NSImage? {
        let scale = max(scale, 1)
        let pixelWidth = max(Int((size.width * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((size.height * scale).rounded(.up)), 1)
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high
        context.scaleBy(x: scale, y: scale)
        drawing()
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: size)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let cgImage = bitmap.cgImage {
            return cgImage
        }

        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func imageScale(for image: NSImage) -> CGFloat {
        let widthScale = image.representations
            .map { CGFloat($0.pixelsWide) / max(image.size.width, 1) }
            .max() ?? 1
        let heightScale = image.representations
            .map { CGFloat($0.pixelsHigh) / max(image.size.height, 1) }
            .max() ?? 1
        return max(widthScale, heightScale, 1)
    }
}
