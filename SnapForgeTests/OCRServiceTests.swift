import Foundation
import Testing

@testable import SnapForge

/// Tests for OCRService — error enum and configuration.
/// Vision-based recognition tests require real images and CI entitlements,
/// so we focus on testable surface area (error types, language config).
@Suite("OCRService")
@MainActor
struct OCRServiceTests {

    @Test("OCRError provides localised descriptions")
    func errorDescriptions() {
        let invalidImage = OCRService.OCRError.invalidImage
        #expect(invalidImage.errorDescription?.contains("image") == true)

        let recognitionFailed = OCRService.OCRError.recognitionFailed("timeout")
        #expect(recognitionFailed.errorDescription?.contains("timeout") == true)
    }

    @Test("Supported languages list is non-empty and contains English")
    func supportedLanguages() {
        #expect(!OCRService.allSupportedLanguages.isEmpty)
        #expect(OCRService.allSupportedLanguages.contains("en-US"))
    }

    @Test("Supported languages include Vietnamese")
    func vietnameseSupport() {
        #expect(OCRService.allSupportedLanguages.contains("vi-VN"))
    }

    @Test("Supported languages include Chinese variants")
    func chineseSupport() {
        #expect(OCRService.allSupportedLanguages.contains("zh-Hans"))
        #expect(OCRService.allSupportedLanguages.contains("zh-Hant"))
    }

    @Test("OCRResult stores correct values")
    func ocrResult() {
        let result = OCRService.OCRResult(
            text: "Hello World",
            confidence: 0.95,
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1)
        )
        #expect(result.text == "Hello World")
        #expect(result.confidence == 0.95)
        #expect(result.boundingBox.origin.x == 0.1)
    }
}
