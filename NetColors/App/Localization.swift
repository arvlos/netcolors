import Foundation

/// UI language chosen in Settings. `.system` follows the device language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ru

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Language code used for lookup: Russian when chosen or preferred by the device, English otherwise.
    var resolvedCode: String {
        switch self {
        case .en: "en"
        case .ru: "ru"
        case .system: Bundle.main.preferredLocalizations.first == "ru" ? "ru" : "en"
        }
    }

    var locale: Locale { Locale(identifier: resolvedCode) }
}

/// Looks up UI strings in the language chosen in Settings rather than the device language,
/// so switching takes effect without restarting the app. Keys are the English texts,
/// so a missing translation falls back to English.
enum L10n {
    static func tr(_ key: String) -> String {
        guard let bundle = bundle(for: AppLanguage.current) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: AppLanguage.current.locale, arguments: arguments)
    }

    /// Network tokens stored by `CarrierInfo` ("WiFi", "LTE", "Cellular"…) in the current language.
    /// Technology names (LTE, 5G) stay as they are.
    static func networkName(_ token: String) -> String {
        switch token {
        case "WiFi": "Wi-Fi"
        case "Cellular": L10n.tr("Cellular")
        case "Unknown": L10n.tr("Unknown")
        case "None": L10n.tr("No Network")
        default: token
        }
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.resolvedCode, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}
