import XCTest
@testable import NetColors

@MainActor
final class FeedbackTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    func testMailURLAddressesTheDeveloper() throws {
        let url = try XCTUnwrap(Feedback.mailURL(appVersion: "1.0 (1)", systemVersion: "18.0"))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, "netcolors@artemlosev.com")
    }

    func testMailURLCarriesSubjectAndVersions() throws {
        UserDefaults.standard.set(AppLanguage.en.rawValue, forKey: AppLanguage.storageKey)
        let url = try XCTUnwrap(Feedback.mailURL(appVersion: "1.0 (1)", systemVersion: "18.0"))
        XCTAssertEqual(queryValue("subject", in: url), "NetColors feedback")
        XCTAssertEqual(queryValue("body", in: url), "\n\nApp version: 1.0 (1), iOS 18.0")
    }

    /// Mail apps read "+" literally, so spaces must travel as %20 and line breaks as %0A.
    func testMailURLEncodesSpacesAndLineBreaks() throws {
        let link = try XCTUnwrap(Feedback.mailURL(appVersion: "1.0 (1)", systemVersion: "18.0")).absoluteString
        XCTAssertFalse(link.contains("+"))
        XCTAssertTrue(link.contains("%20"))
        XCTAssertTrue(link.contains("%0A"))
    }

    func testRussianSubject() throws {
        UserDefaults.standard.set(AppLanguage.ru.rawValue, forKey: AppLanguage.storageKey)
        let url = try XCTUnwrap(Feedback.mailURL(appVersion: "1.0 (1)", systemVersion: "18.0"))
        XCTAssertEqual(queryValue("subject", in: url), "NetColors: отзыв")
    }
}
