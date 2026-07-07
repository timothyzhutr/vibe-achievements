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
