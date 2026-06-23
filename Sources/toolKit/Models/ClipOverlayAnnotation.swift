import CoreGraphics
import Foundation

struct ClipOverlayAnnotation: Equatable, Sendable {
    enum Kind: String, Sendable {
        case rectangle
        case arrow
        case pencil
        case marker
        case mosaic
        case blur
        case text
    }

    struct Style: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
        var lineWidth: CGFloat

        static let redStroke = Style(red: 1, green: 0.16, blue: 0.12, alpha: 1, lineWidth: 4)
        static let marker = Style(red: 1, green: 0.88, blue: 0.08, alpha: 0.45, lineWidth: 18)
        static let mosaic = Style(red: 0.56, green: 0.60, blue: 0.66, alpha: 0.22, lineWidth: 40)
        static let blur = Style(red: 0.72, green: 0.78, blue: 0.86, alpha: 0.18, lineWidth: 40)
        static let text = Style(red: 0.08, green: 0.34, blue: 1, alpha: 1, lineWidth: 2)
    }

    var kind: Kind
    var rect: CGRect
    var points: [CGPoint]
    var text: String
    var style: Style

    var bounds: CGRect {
        switch kind {
        case .arrow, .pencil, .marker, .mosaic, .blur:
            guard let first = points.first else {
                return rect
            }

            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partialResult, point in
                partialResult.union(CGRect(origin: point, size: .zero))
            }.insetBy(dx: -max(style.lineWidth, 12), dy: -max(style.lineWidth, 12))
        default:
            return rect.standardized
        }
    }
}

enum ClipCaptureAction: Sendable {
    case capture
    case ocr
    case pin
    case save
}
