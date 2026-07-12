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

    func testSourceDirectoryRowsDescribeDefaultAndManualSelections() {
        let defaultSettings = AppSourceSettings()

        let defaultRows = SourceDirectorySetting.rows(for: defaultSettings)
        XCTAssertEqual(defaultRows.map(\.platformName), ["Claude Code", "Codex"])
        XCTAssertEqual(defaultRows.map(\.selectionMode), [.automatic, .automatic])
        XCTAssertEqual(defaultRows[0].folderRole, "Projects folder")
        XCTAssertEqual(defaultRows[0].displayPath, "~/.claude/projects")
        XCTAssertEqual(defaultRows[1].folderRole, "Codex home folder")
        XCTAssertEqual(defaultRows[1].displayPath, "$CODEX_HOME or ~/.codex")

        let manualSettings = AppSourceSettings(
            claudeProjectsPath: "/Users/tim/custom-claude",
            codexHomePath: "/Users/tim/custom-codex"
        )
        let manualRows = SourceDirectorySetting.rows(for: manualSettings)
        XCTAssertEqual(manualRows.map(\.selectionMode), [.manual, .manual])
        XCTAssertEqual(manualRows[0].displayPath, "/Users/tim/custom-claude")
        XCTAssertEqual(manualRows[1].displayPath, "/Users/tim/custom-codex")
    }

    func testSettingsWindowIsLargeEnoughForSourceSelectors() {
        XCTAssertGreaterThanOrEqual(AppDelegate.settingsWindowContentSize.width, 680)
        XCTAssertGreaterThanOrEqual(AppDelegate.settingsWindowContentSize.height, 460)
    }

}
