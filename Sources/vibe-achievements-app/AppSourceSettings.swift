import Foundation
import VibeAchievementsCore

struct AppSourceSettings: Equatable, Sendable {
    var claudeEnabled: Bool = true
    var codexEnabled: Bool = true
    var cursorEnabled: Bool = true
    var openCodeEnabled: Bool = true
    var antigravityEnabled: Bool = true
    var claudeProjectsPath: String?
    var codexHomePath: String?
    var cursorHomePath: String?
    var openCodeDataPath: String?
    var antigravityHomePath: String?

    var discoveryConfiguration: SourceConfiguration {
        SourceConfiguration(
            claudeEnabled: claudeEnabled,
            codexEnabled: codexEnabled,
            cursorEnabled: cursorEnabled,
            openCodeEnabled: openCodeEnabled,
            antigravityEnabled: antigravityEnabled,
            claudeProjectsOverride: claudeProjectsPath.map(URL.init(fileURLWithPath:)),
            codexHomeOverride: codexHomePath.map(URL.init(fileURLWithPath:)),
            cursorHomeOverride: cursorHomePath.map(URL.init(fileURLWithPath:)),
            openCodeDataOverride: openCodeDataPath.map(URL.init(fileURLWithPath:)),
            antigravityHomeOverride: antigravityHomePath.map(URL.init(fileURLWithPath:))
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSourceSettings {
        AppSourceSettings(
            claudeEnabled: defaults.object(forKey: Keys.claudeEnabled) as? Bool ?? true,
            codexEnabled: defaults.object(forKey: Keys.codexEnabled) as? Bool ?? true,
            cursorEnabled: defaults.object(forKey: Keys.cursorEnabled) as? Bool ?? true,
            openCodeEnabled: defaults.object(forKey: Keys.openCodeEnabled) as? Bool ?? true,
            antigravityEnabled: defaults.object(forKey: Keys.antigravityEnabled) as? Bool ?? true,
            claudeProjectsPath: defaults.string(forKey: Keys.claudeProjectsPath),
            codexHomePath: defaults.string(forKey: Keys.codexHomePath),
            cursorHomePath: defaults.string(forKey: Keys.cursorHomePath),
            openCodeDataPath: defaults.string(forKey: Keys.openCodeDataPath),
            antigravityHomePath: defaults.string(forKey: Keys.antigravityHomePath)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(claudeEnabled, forKey: Keys.claudeEnabled)
        defaults.set(codexEnabled, forKey: Keys.codexEnabled)
        defaults.set(cursorEnabled, forKey: Keys.cursorEnabled)
        defaults.set(openCodeEnabled, forKey: Keys.openCodeEnabled)
        defaults.set(antigravityEnabled, forKey: Keys.antigravityEnabled)
        saveOptional(claudeProjectsPath, key: Keys.claudeProjectsPath, defaults: defaults)
        saveOptional(codexHomePath, key: Keys.codexHomePath, defaults: defaults)
        saveOptional(cursorHomePath, key: Keys.cursorHomePath, defaults: defaults)
        saveOptional(openCodeDataPath, key: Keys.openCodeDataPath, defaults: defaults)
        saveOptional(antigravityHomePath, key: Keys.antigravityHomePath, defaults: defaults)
    }

    mutating func resetClaudePath() {
        claudeProjectsPath = nil
    }

    mutating func resetCodexPath() {
        codexHomePath = nil
    }

    mutating func resetCursorPath() {
        cursorHomePath = nil
    }

    mutating func resetOpenCodePath() {
        openCodeDataPath = nil
    }

    mutating func resetAntigravityPath() {
        antigravityHomePath = nil
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
        static let cursorEnabled = "sources.cursor.enabled"
        static let openCodeEnabled = "sources.opencode.enabled"
        static let antigravityEnabled = "sources.antigravity.enabled"
        static let claudeProjectsPath = "sources.claude.projectsPath"
        static let codexHomePath = "sources.codex.homePath"
        static let cursorHomePath = "sources.cursor.homePath"
        static let openCodeDataPath = "sources.opencode.dataPath"
        static let antigravityHomePath = "sources.antigravity.homePath"
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
