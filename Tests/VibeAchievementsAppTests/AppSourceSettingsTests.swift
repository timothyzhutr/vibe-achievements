import XCTest
@testable import VibeAchievementsApp

final class AppSourceSettingsTests: XCTestCase {
    func testSettingsRoundTripThroughUserDefaults() {
        let suiteName = "AppSourceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSourceSettings(
            claudeEnabled: false,
            codexEnabled: true,
            cursorEnabled: true,
            openCodeEnabled: true,
            antigravityEnabled: false,
            claudeProjectsPath: "/tmp/claude/projects",
            codexHomePath: "/tmp/codex",
            cursorHomePath: "/tmp/cursor",
            openCodeDataPath: "/tmp/opencode",
            antigravityHomePath: "/tmp/gemini"
        )

        settings.save(to: defaults)
        let loaded = AppSourceSettings.load(from: defaults)

        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.discoveryConfiguration.claudeProjectsOverride?.path, "/tmp/claude/projects")
        XCTAssertEqual(loaded.discoveryConfiguration.codexHomeOverride?.path, "/tmp/codex")
        XCTAssertEqual(loaded.discoveryConfiguration.cursorHomeOverride?.path, "/tmp/cursor")
        XCTAssertEqual(loaded.discoveryConfiguration.openCodeDataOverride?.path, "/tmp/opencode")
        XCTAssertEqual(loaded.discoveryConfiguration.antigravityHomeOverride?.path, "/tmp/gemini")
    }

    func testResetClearsManualPathButKeepsEnabledState() {
        var settings = AppSourceSettings(
            claudeEnabled: false,
            codexEnabled: false,
            cursorEnabled: false,
            openCodeEnabled: false,
            antigravityEnabled: false,
            claudeProjectsPath: "/tmp/claude/projects",
            codexHomePath: "/tmp/codex",
            cursorHomePath: "/tmp/cursor",
            openCodeDataPath: "/tmp/opencode",
            antigravityHomePath: "/tmp/gemini"
        )

        settings.resetClaudePath()
        settings.resetCodexPath()
        settings.resetCursorPath()
        settings.resetOpenCodePath()
        settings.resetAntigravityPath()

        XCTAssertFalse(settings.claudeEnabled)
        XCTAssertFalse(settings.codexEnabled)
        XCTAssertFalse(settings.cursorEnabled)
        XCTAssertFalse(settings.openCodeEnabled)
        XCTAssertFalse(settings.antigravityEnabled)
        XCTAssertNil(settings.claudeProjectsPath)
        XCTAssertNil(settings.codexHomePath)
        XCTAssertNil(settings.cursorHomePath)
        XCTAssertNil(settings.openCodeDataPath)
        XCTAssertNil(settings.antigravityHomePath)
    }

}
