import Testing
@testable import SnapForge

/// Tests for AutoRedactService.classifySensitiveText — pure classification logic.
@Suite("AutoRedactService — Sensitive Text Classification")
struct AutoRedactServiceTests {

    // MARK: - Email Detection

    @Test("Detects email addresses")
    func detectEmail() {
        #expect(AutoRedactService.classifySensitiveText("user@example.com") == .email)
        #expect(AutoRedactService.classifySensitiveText("admin@company.io") == .email)
    }

    @Test("Does not flag plain text as email")
    func noFalseEmail() {
        #expect(AutoRedactService.classifySensitiveText("hello world") == nil)
        #expect(AutoRedactService.classifySensitiveText("no @ sign here") == nil)
    }

    // MARK: - SSN Detection

    @Test("Detects SSN patterns")
    func detectSSN() {
        #expect(AutoRedactService.classifySensitiveText("123-45-6789") == .ssn)
        #expect(AutoRedactService.classifySensitiveText("123 45 6789") == .ssn)
        #expect(AutoRedactService.classifySensitiveText("123456789") == .ssn)
    }

    // MARK: - IP Address Detection

    @Test("Detects IP addresses")
    func detectIPAddress() {
        #expect(AutoRedactService.classifySensitiveText("192.168.1.1") == .ipAddress)
        #expect(AutoRedactService.classifySensitiveText("10.0.0.1") == .ipAddress)
        #expect(AutoRedactService.classifySensitiveText("255.255.255.0") == .ipAddress)
    }

    @Test("Does not flag partial IPs")
    func noFalseIP() {
        #expect(AutoRedactService.classifySensitiveText("1.2.3") != .ipAddress)
    }

    // MARK: - Credit Card Detection

    @Test("Detects credit card numbers")
    func detectCreditCard() {
        #expect(AutoRedactService.classifySensitiveText("4111 1111 1111 1111") == .creditCard)
        #expect(AutoRedactService.classifySensitiveText("4111-1111-1111-1111") == .creditCard)
        #expect(AutoRedactService.classifySensitiveText("5500000000000004") == .creditCard)
    }

    // MARK: - Phone Detection

    @Test("Detects phone numbers")
    func detectPhone() {
        #expect(AutoRedactService.classifySensitiveText("+1 (555) 123-4567") == .phone)
        #expect(AutoRedactService.classifySensitiveText("555-1234567") == .phone)
        #expect(AutoRedactService.classifySensitiveText("(408) 555-1234") == .phone)
    }

    // MARK: - Password Detection

    @Test("Detects password-like strings")
    func detectPassword() {
        #expect(AutoRedactService.classifySensitiveText("P@ssw0rd!") == .password)
        #expect(AutoRedactService.classifySensitiveText("MyS3cretK3y!") == .password)
        #expect(AutoRedactService.classifySensitiveText("Abc12345!") == .password)
    }

    @Test("Does not flag simple words as password")
    func noFalsePassword() {
        #expect(AutoRedactService.classifySensitiveText("Hello") == nil)
        #expect(AutoRedactService.classifySensitiveText("Simple text") == nil)
    }

    // MARK: - No Detection

    @Test("Returns nil for non-sensitive text")
    func noSensitiveText() {
        #expect(AutoRedactService.classifySensitiveText("Hello") == nil)
        #expect(AutoRedactService.classifySensitiveText("The quick brown fox") == nil)
        #expect(AutoRedactService.classifySensitiveText("SnapForge") == nil)
    }

    @Test("Returns nil for short strings below threshold")
    func shortText() {
        #expect(AutoRedactService.classifySensitiveText("Hi") == nil)
        #expect(AutoRedactService.classifySensitiveText("ab") == nil)
        #expect(AutoRedactService.classifySensitiveText("") == nil)
    }

    // MARK: - RedactType Properties

    @Test("RedactType display names are non-empty")
    func redactTypeDisplayNames() {
        for type in RedactType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("RedactType icons are non-empty")
    func redactTypeIcons() {
        for type in RedactType.allCases {
            #expect(!type.icon.isEmpty)
        }
    }

    @Test("RedactType covers expected cases")
    func redactTypeCases() {
        #expect(RedactType.allCases.count == 7)
    }
}
