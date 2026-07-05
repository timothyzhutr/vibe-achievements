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
            claudeProjectsPath: "/tmp/claude/projects",
            codexHomePath: "/tmp/codex"
        )

        settings.save(to: defaults)
        let loaded = AppSourceSettings.load(from: defaults)

        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.discoveryConfiguration.claudeProjectsOverride?.path, "/tmp/claude/projects")
        XCTAssertEqual(loaded.discoveryConfiguration.codexHomeOverride?.path, "/tmp/codex")
    }

    func testResetClearsManualPathButKeepsEnabledState() {
        var settings = AppSourceSettings(
            claudeEnabled: false,
            codexEnabled: false,
            claudeProjectsPath: "/tmp/claude/projects",
            codexHomePath: "/tmp/codex"
        )

        settings.resetClaudePath()
        settings.resetCodexPath()

        XCTAssertFalse(settings.claudeEnabled)
        XCTAssertFalse(settings.codexEnabled)
        XCTAssertNil(settings.claudeProjectsPath)
        XCTAssertNil(settings.codexHomePath)
    }

}
