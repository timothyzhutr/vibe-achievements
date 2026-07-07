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

enum SourceDirectorySelectionMode: Equatable, Sendable {
    case automatic
    case manual
}

struct SourceDirectorySetting: Equatable, Sendable, Identifiable {
    enum Platform: Equatable, Sendable {
        case claude
        case codex
    }

    var id: Platform { platform }
    let platform: Platform
    let platformName: String
    let folderRole: String
    let defaultPath: String
    let manualPath: String?
    let isEnabled: Bool

    var selectionMode: SourceDirectorySelectionMode {
        manualPath == nil ? .automatic : .manual
    }

    var displayPath: String {
        manualPath ?? defaultPath
    }

    static func rows(for settings: AppSourceSettings) -> [SourceDirectorySetting] {
        [
            SourceDirectorySetting(
                platform: .claude,
                platformName: "Claude Code",
                folderRole: "Projects folder",
                defaultPath: "~/.claude/projects",
                manualPath: settings.claudeProjectsPath,
                isEnabled: settings.claudeEnabled
            ),
            SourceDirectorySetting(
                platform: .codex,
                platformName: "Codex",
                folderRole: "Codex home folder",
                defaultPath: "$CODEX_HOME or ~/.codex",
                manualPath: settings.codexHomePath,
                isEnabled: settings.codexEnabled
            )
        ]
    }
}
