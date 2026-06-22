import Foundation
import SwiftUI

enum L10n {
    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }

    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
