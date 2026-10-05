import XCTest
@testable import NetColors

/// Guards the in-app language switch and the wording rule: texts describe what was observed
/// and never name who restricts access.
@MainActor
final class LocalizationTests: XCTestCase {

    /// Case-insensitive substrings that must not appear in any UI text, in any language.
    private let forbidden = [
        "ТСПУ", "TSPU", "DPI", "Роскомнадзор", "Roskomnadzor",
        "censor", "цензур", "block", "блокир",
        "нужен VPN", "требуется VPN", "require VPN", "VPN needed",
    ]

    /// Short acronyms are matched as whole words: as substrings they hit ordinary
    /// identifiers and words (netwoRKName, свеРКНуть).
    private let forbiddenWords = ["RKN", "РКН"]

    private func violations(in text: String, extraSubstrings: [String] = []) -> [String] {
        let substrings = (forbidden + extraSubstrings).filter {
            text.range(of: $0, options: .caseInsensitive) != nil
        }
        let words = forbiddenWords.filter {
            text.range(of: "\\b\($0)\\b", options: [.regularExpression, .caseInsensitive]) != nil
        }
        return substrings + words
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func use(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

    private func table(_ code: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: code),
            "No \(code) strings table in the app bundle"
        )
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// Swift sources of a top-level directory, read from the repository next to this file.
    private func sources(in directory: String = "NetColors") throws -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(directory)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let sources = try files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        XCTAssertFalse(sources.isEmpty, "No Swift sources found in \(directory)")
        return sources
    }

    private func matches(_ pattern: String, in text: String) -> [(line: Int, captured: String)] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let line = ns.substring(to: match.range.location).components(separatedBy: "\n").count
            return (line, ns.substring(with: match.range(at: match.numberOfRanges - 1)))
        }
    }

    // MARK: - Language switch

    func testSwitchingLanguageChangesStrings() {
        use(.ru)
        XCTAssertEqual(AccessMode.whitelist.title, "Только отдельные сервисы")
        XCTAssertEqual(ProbeGroup.whitelist.title, "Белые списки")
        XCTAssertEqual(ProbeGroup.usuallyUnavailable.title, "Обычно недоступные")

        use(.en)
        XCTAssertEqual(AccessMode.whitelist.title, "Only Selected Services")
        XCTAssertEqual(ProbeGroup.whitelist.title, "Whitelist")
        XCTAssertEqual(ProbeGroup.usuallyUnavailable.title, "Usually Unavailable")
    }

    func testFormattedStringsUseChosenLanguage() {
        use(.ru)
        XCTAssertEqual(L10n.tr("Cut off after %lld KB", 16), "Обрыв после 16 КБ")
        XCTAssertEqual(L10n.tr("%.1f KB", 1.5), "1,5 КБ")

        use(.en)
        XCTAssertEqual(L10n.tr("Cut off after %lld KB", 16), "Cut off after 16 KB")
        XCTAssertEqual(L10n.tr("%.1f KB", 1.5), "1.5 KB")
    }

    func testNetworkTokensAreTranslated() {
        use(.ru)
        XCTAssertEqual(L10n.networkName("Cellular"), "Мобильная сеть")
        XCTAssertEqual(L10n.networkName("WiFi"), "Wi-Fi")
        XCTAssertEqual(L10n.networkName("LTE"), "LTE")
    }

    // MARK: - Catalog completeness

    func testEnglishAndRussianTablesHaveSameKeys() throws {
        XCTAssertEqual(Set(try table("en").keys), Set(try table("ru").keys))
    }

    func testEveryKeyUsedInCodeIsTranslated() throws {
        let russian = try table("ru")
        for (path, text) in try sources() {
            for (line, key) in matches(#"L10n\.tr\("((?:[^"\\]|\\.)*)""#, in: text) {
                XCTAssertNotNil(russian[key], "\(path):\(line) — no Russian translation for \"\(key)\"")
            }
        }
    }

    /// A string literal passed straight to a SwiftUI view is localized by the device language,
    /// bypassing the in-app switch. Literals without letters (separators) are fine.
    func testViewsDoNotShowLiteralStrings() throws {
        let initializers = #"\b(?:Text|Section|Label|Button|Picker|Toggle|LabeledContent|ContentUnavailableView|ProgressView|NavigationLink)\(\s*"([^"]*)""#
        let modifiers = #"\.(?:navigationTitle|confirmationDialog|alert)\(\s*"([^"]*)""#
        for (path, text) in try sources() {
            for pattern in [initializers, modifiers] {
                for (line, literal) in matches(pattern, in: text) where literal.contains(where: \.isLetter) {
                    XCTFail("\(path):\(line) — literal \"\(literal)\" bypasses L10n")
                }
            }
        }
    }

    // MARK: - Wording rule

    /// The code is published, so identifiers and comments follow the same rule as UI texts.
    func testSourceCodeUsesNeutralNames() throws {
        for directory in ["NetColors", "NetColorsTests"] {
            for (path, text) in try sources(in: directory) where path != "LocalizationTests.swift" {
                for word in violations(in: text, extraSubstrings: ["kill", "throttl", "interference"]) {
                    XCTFail("\(directory)/\(path) contains \"\(word)\"")
                }
            }
        }
    }

    func testNoTextNamesWhoRestrictsAccess() throws {
        for code in ["en", "ru"] {
            for (key, value) in try table(code) {
                for word in violations(in: value) {
                    XCTFail("[\(code)] \"\(key)\" contains \"\(word)\"")
                }
            }
        }
    }
}
