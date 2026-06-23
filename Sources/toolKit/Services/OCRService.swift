import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

struct OCRService {
    struct RecognitionLine: Sendable {
        let text: String
        let confidence: Float
    }

    func recognizeText(from image: NSImage, languageMode: OCRLanguageMode = .automatic) async throws -> OCRResultPayload {
        let cgImage = try image.cgImageValue()
        let preparedImage = try preprocessImage(cgImage)

        switch languageMode {
        case .automatic:
            break
        case .english:
            return try recognize(
                cgImage: preparedImage,
                languages: ["en-US"],
                usesLanguageCorrection: true,
                automaticallyDetectLanguage: false
            )
        case .simplifiedChinese:
            return try recognize(
                cgImage: preparedImage,
                languages: ["zh-Hans", "en-US"],
                usesLanguageCorrection: false,
                automaticallyDetectLanguage: true
            )
        case .traditionalChinese:
            return try recognize(
                cgImage: preparedImage,
                languages: ["zh-Hant", "en-US"],
                usesLanguageCorrection: false,
                automaticallyDetectLanguage: true
            )
        }

        let mixedPayload = try recognize(
            cgImage: preparedImage,
            languages: ["en-US", "zh-Hans", "zh-Hant"],
            usesLanguageCorrection: true,
            automaticallyDetectLanguage: true
        )

        let chinesePayload = try recognize(
            cgImage: preparedImage,
            languages: ["zh-Hans", "zh-Hant", "en-US"],
            usesLanguageCorrection: false,
            automaticallyDetectLanguage: true
        )

        return bestPayload(between: mixedPayload, and: chinesePayload)
    }

    private func recognize(
        cgImage: CGImage,
        languages: [String],
        usesLanguageCorrection: Bool,
        automaticallyDetectLanguage: Bool
    ) throws -> OCRResultPayload {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection
        request.recognitionLanguages = languages
        request.minimumTextHeight = 0.012

        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = automaticallyDetectLanguage
        }

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.compactMap { observation -> RecognitionLine? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            return RecognitionLine(text: candidate.string, confidence: candidate.confidence)
        }

        return OCRResultPayload(
            text: lines.map(\.text).joined(separator: "\n"),
            confidence: lines.isEmpty ? nil : lines.map(\.confidence).reduce(0, +) / Float(lines.count)
        )
    }

    private func bestPayload(between first: OCRResultPayload, and second: OCRResultPayload) -> OCRResultPayload {
        let firstScore = payloadScore(first)
        let secondScore = payloadScore(second)
        return secondScore > firstScore ? second : first
    }

    private func payloadScore(_ payload: OCRResultPayload) -> Double {
        let trimmedText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let characterScore = Double(trimmedText.count)
        let confidenceScore = Double(payload.confidence ?? 0) * 100
        let chineseBonus = Double(trimmedText.unicodeScalars.filter(Self.isChineseScalar).count) * 0.5
        return characterScore + confidenceScore + chineseBonus
    }

    private func preprocessImage(_ cgImage: CGImage) throws -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        let scale = recommendedScale(for: cgImage)

        let scaledImage: CIImage
        if scale > 1 {
            let scaleFilter = CIFilter.lanczosScaleTransform()
            scaleFilter.inputImage = ciImage
            scaleFilter.scale = Float(scale)
            scaleFilter.aspectRatio = 1
            scaledImage = scaleFilter.outputImage ?? ciImage
        } else {
            scaledImage = ciImage
        }

        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = scaledImage
        colorFilter.brightness = 0.02
        colorFilter.contrast = 1.18
        colorFilter.saturation = 0

        let sharpenFilter = CIFilter.sharpenLuminance()
        sharpenFilter.inputImage = colorFilter.outputImage ?? scaledImage
        sharpenFilter.sharpness = 0.45

        let outputImage = sharpenFilter.outputImage ?? colorFilter.outputImage ?? scaledImage
        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let processedImage = context.createCGImage(outputImage, from: outputImage.extent.integral) else {
            throw OCRServiceError.unreadableImage
        }

        return processedImage
    }

    private func recommendedScale(for cgImage: CGImage) -> CGFloat {
        let longestEdge = max(cgImage.width, cgImage.height)
        switch longestEdge {
        case ..<1200:
            return 2.4
        case ..<1800:
            return 1.8
        default:
            return 1
        }
    }

    private static func isChineseScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF:
            return true
        default:
            return false
        }
    }
}

struct OCRResultPayload: Sendable {
    let text: String
    let confidence: Float?
}

private extension NSImage {
    func cgImageValue() throws -> CGImage {
        var proposedRect = CGRect(origin: .zero, size: size)

        if let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }

        guard
            let tiffData = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmap.cgImage
        else {
            throw OCRServiceError.unreadableImage
        }

        return cgImage
    }
}

enum OCRServiceError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The selected image could not be prepared for OCR."
        }
    }
}
