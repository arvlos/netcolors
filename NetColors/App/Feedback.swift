import Foundation
import UIKit

/// Feedback by e-mail: no server and no form — the user sees the message and sends it from their own mail app.
enum Feedback {
    static let address = "netcolors@artemlosev.com"

    /// Version and build from the bundle, e.g. "1.0 (1)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// A mailto link with a subject and the app and iOS versions, which help to reproduce a problem.
    @MainActor
    static func mailURL(appVersion: String = appVersion,
                        systemVersion: String = UIDevice.current.systemVersion) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.tr("NetColors feedback")),
            URLQueryItem(name: "body", value: "\n\n" + L10n.tr("App version: %@, iOS %@", appVersion, systemVersion)),
        ]
        return components.url
    }
}
