import SwiftUI

enum SubtitleColorOption: String, Codable, CaseIterable, Identifiable {
    case white
    case cyan
    case blue
    case green
    case yellow
    case magenta
    case red
    case black

    var id: Self { self }

    var title: String {
        switch self {
        case .white: "白色"
        case .cyan: "青色"
        case .blue: "蓝色"
        case .green: "绿色"
        case .yellow: "黄色"
        case .magenta: "洋红色"
        case .red: "红色"
        case .black: "黑色"
        }
    }

    var color: Color {
        switch self {
        case .white: .white
        case .cyan: .cyan
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .magenta: .purple
        case .red: .red
        case .black: .black
        }
    }
}

struct SubtitleSettings: Codable, Equatable {
    var defaultShowSubtitles = true
    var textColor: SubtitleColorOption = .white
    var backgroundColor: SubtitleColorOption = .black
    var backgroundOpacity = 0.5
    var cornerRadius = 8.0
    var usesGlassStyle = false

    func clamped() -> SubtitleSettings {
        var value = self
        value.backgroundOpacity = min(max(value.backgroundOpacity, 0), 1)
        value.cornerRadius = min(max(value.cornerRadius, 0), 20)
        return value
    }
}

enum SubtitleSettingsStore {
    private static let key = "pili.settings.subtitle.v1"

    static func load() -> SubtitleSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(SubtitleSettings.self, from: data)
        else { return SubtitleSettings() }
        return value.clamped()
    }

    static func save(_ settings: SubtitleSettings) {
        let value = settings.clamped()
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .subtitleSettingsDidChange, object: value)
    }
}

extension Notification.Name {
    static let subtitleSettingsDidChange = Notification.Name("pili.subtitle-settings.did-change")
}
