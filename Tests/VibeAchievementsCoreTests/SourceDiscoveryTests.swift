import XCTest
@testable import VibeAchievementsCore

final class SourceDiscoveryTests: XCTestCase {
    func testTranscriptPathsIncludeClaudeCodexAndArchivedJSONL() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claude = root.appendingPathComponent(".claude/projects/project-a", isDirectory: true)
        let codexDay = root.appendingPathComponent(".codex/sessions/2026/07/04", isDirectory: true)
        let codexArchive = root.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDay, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexArchive, withIntermediateDirectories: true)

        let claudeFile = claude.appendingPathComponent("claude.jsonl")
        let codexFile = codexDay.appendingPathComponent("rollout-codex.jsonl")
        let archiveFile = codexArchive.appendingPathComponent("rollout-archive.jsonl")
        let ignoredFile = codexArchive.appendingPathComponent("notes.txt")
        try "{}\n".write(to: claudeFile, atomically: true, encoding: .utf8)
        try "{}\n".write(to: codexFile, atomically: true, encoding: .utf8)
        try "{}\n".write(to: archiveFile, atomically: true, encoding: .utf8)
        try "ignore".write(to: ignoredFile, atomically: true, encoding: .utf8)

        let locations = SourceDiscovery.discover(home: root)
        let paths = SourceDiscovery.transcriptPaths(in: locations)
            .map { $0.resolvingSymlinksInPath().path }

        XCTAssertEqual(Set(paths), Set([
            claudeFile.resolvingSymlinksInPath().path,
            codexFile.resolvingSymlinksInPath().path,
            archiveFile.resolvingSymlinksInPath().path
        ]))
    }

    func testSourceConfigurationCanDisableClaudeOrCodex() throws {
        let root = try makeRoot()
        let claude = root.appendingPathComponent(".claude/projects", isDirectory: true)
        let codexSessions = root.appendingPathComponent(".codex/sessions", isDirectory: true)
        let codexArchive = root.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexArchive, withIntermediateDirectories: true)

        let withoutClaude = SourceDiscovery.discover(
            home: root,
            configuration: SourceConfiguration(claudeEnabled: false, codexEnabled: true)
        )
        XCTAssertNil(withoutClaude.claudeProjects)
        XCTAssertEqual(withoutClaude.codexSessions, codexSessions)
        XCTAssertEqual(withoutClaude.codexArchivedSessions, codexArchive)

        let withoutCodex = SourceDiscovery.discover(
            home: root,
            configuration: SourceConfiguration(claudeEnabled: true, codexEnabled: false)
        )
        XCTAssertEqual(withoutCodex.claudeProjects, claude)
        XCTAssertNil(withoutCodex.codexSessions)
        XCTAssertNil(withoutCodex.codexArchivedSessions)
    }

    func testSourceConfigurationUsesManualDirectories() throws {
        let root = try makeRoot()
        let claudeOverride = root.appendingPathComponent("custom-claude", isDirectory: true)
        let codexOverride = root.appendingPathComponent("custom-codex", isDirectory: true)
        let codexSessions = codexOverride.appendingPathComponent("sessions", isDirectory: true)
        let codexArchive = codexOverride.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeOverride, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexArchive, withIntermediateDirectories: true)

        let locations = SourceDiscovery.discover(
            home: root,
            configuration: SourceConfiguration(
                claudeEnabled: true,
                codexEnabled: true,
                claudeProjectsOverride: claudeOverride,
                codexHomeOverride: codexOverride
            )
        )

        XCTAssertEqual(locations.claudeProjects, claudeOverride)
        XCTAssertEqual(locations.codexSessions, codexSessions)
        XCTAssertEqual(locations.codexArchivedSessions, codexArchive)
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
