import Foundation
import VibeAchievementsCore

struct AppSourceSettings: Equatable, Sendable {
    var claudeEnabled: Bool = true
    var codexEnabled: Bool = true
    var claudeProjectsPath: String?
    var codexHomePath: String?

    var discoveryConfiguration: SourceConfiguration {
        SourceConfiguration(
            claudeEnabled: claudeEnabled,
            codexEnabled: codexEnabled,
            claudeProjectsOverride: claudeProjectsPath.map(URL.init(fileURLWithPath:)),
            codexHomeOverride: codexHomePath.map(URL.init(fileURLWithPath:))
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSourceSettings {
        AppSourceSettings(
            claudeEnabled: defaults.object(forKey: Keys.claudeEnabled) as? Bool ?? true,
            codexEnabled: defaults.object(forKey: Keys.codexEnabled) as? Bool ?? true,
            claudeProjectsPath: defaults.string(forKey: Keys.claudeProjectsPath),
            codexHomePath: defaults.string(forKey: Keys.codexHomePath)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(claudeEnabled, forKey: Keys.claudeEnabled)
        defaults.set(codexEnabled, forKey: Keys.codexEnabled)
        saveOptional(claudeProjectsPath, key: Keys.claudeProjectsPath, defaults: defaults)
        saveOptional(codexHomePath, key: Keys.codexHomePath, defaults: defaults)
    }

    mutating func resetClaudePath() {
        claudeProjectsPath = nil
    }

    mutating func resetCodexPath() {
        codexHomePath = nil
    }

    private func saveOptional(_ value: String?, key: String, defaults: UserDefaults) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let claudeEnabled = "sources.claude.enabled"
        static let codexEnabled = "sources.codex.enabled"
        static let claudeProjectsPath = "sources.claude.projectsPath"
        static let codexHomePath = "sources.codex.homePath"
    }
}
