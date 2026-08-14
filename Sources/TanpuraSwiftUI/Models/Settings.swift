import Foundation

struct PanelSettings: Codable {
    var volume: Double
    var pan: Double
    var secondNote: String? // "pa" | "ma" | "ni" | nil (off)
    var playing: Bool
}

struct AppSettings: Codable {
    var baseMidi: Int
    var fineCents: Double
    var tempoBpm: Double
    var varyTempo: Bool
    var altVoice: Bool
    var panels: [PanelSettings]

    static let `default` = AppSettings(
        baseMidi: Note.toMidi("C#3"),
        fineCents: 0,
        tempoBpm: 105,
        varyTempo: true,
        altVoice: false,
        panels: [
            PanelSettings(volume: 0.8, pan: 0, secondNote: nil, playing: false),
            PanelSettings(volume: 0.8, pan: 0, secondNote: nil, playing: false),
        ]
    )
}

/// Mirrors app.js's SETTINGS_KEY localStorage persistence.
enum SettingsStore {
    private static let key = "tanpura.settings.v1"

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
