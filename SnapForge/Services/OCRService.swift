import AppKit
import Vision

/// OCR text recognition service using Apple Vision framework.
/// Supports 18 languages: English, French, Italian, German, Spanish, Portuguese,
/// Chinese (Simplified/Traditional), Cantonese, Korean, Japanese, Russian, Ukrainian,
/// Thai, Vietnamese, Arabic.
@MainActor
final class OCRService {
    static let shared = OCRService()
    private init() {}

    /// All languages supported by Vision on macOS 15+
    static let allSupportedLanguages: [String] = [
        "en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR",
        "zh-Hans", "zh-Hant", "yue-Hans", "yue-Hant",
        "ko-KR", "ja-JP", "ru-RU", "uk-UA",
        "th-TH", "vi-VN", "ar-SA",
    ]

    struct OCRResult: Sendable {
        let text: String
        let confidence: Float
        let boundingBox: CGRect  // Normalized (0–1) coordinates
    }

    /// Recognize text in an image. Returns results sorted top-to-bottom, left-to-right.
    func recognizeText(
        in image: NSImage,
        languages: [String]? = nil
    ) async throws -> [OCRResult] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let request = VNRecognizeTextRequest { request, error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error {
                    continuation.resume(
                        throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results = observations.compactMap { observation -> OCRResult? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return OCRResult(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
                // Sort top-to-bottom (Vision uses bottom-left origin, so flip Y)
                .sorted {
                    ($0.boundingBox.origin.y + $0.boundingBox.height)
                        > ($1.boundingBox.origin.y + $1.boundingBox.height)
                }

                continuation.resume(returning: results)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages ?? OCRService.allSupportedLanguages
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(
                    throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    /// Convenience: extract all text as a single string, lines separated by newlines.
    func extractFullText(from image: NSImage) async throws -> String {
        let results = try await recognizeText(in: image)
        return results.map(\.text).joined(separator: "\n")
    }

    enum OCRError: LocalizedError {
        case invalidImage
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage: "Could not process image for OCR"
            case .recognitionFailed(let msg): "OCR failed: \(msg)"
            }
        }
    }
}
