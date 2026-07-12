import XCTest
@testable import VibeAchievementsCore

final class SourceDiscoveryTests: XCTestCase {
    func testAdapterDoesNotTreatMissingRootAsAnEmptyCompleteInventory() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let adapter = ClaudeCodeSourceAdapter(projectsRoot: missing, detectorVersion: "test")

        XCTAssertThrowsError(try adapter.discover())
    }

    func testClaudeAdapterDiscoversAndParsesWithExistingParserParity() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let source = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let transcript = project.appendingPathComponent("claude-session.jsonl")
        try FileManager.default.copyItem(at: source, to: transcript)

        let adapter = ClaudeCodeSourceAdapter(projectsRoot: root, detectorVersion: "detectors-test")
        let inventory = try adapter.discover()

        XCTAssertEqual(inventory.detectedRoots, [root])
        XCTAssertEqual(inventory.warnings, [])
        let record = try XCTUnwrap(inventory.records.only)
        XCTAssertEqual(record.identity, SourceRecordIdentity(sourceTool: .claudeCode, stableID: "claude-session"))
        XCTAssertTrue(record.fingerprint.hasPrefix("detectors-test-"))
        guard case let .file(discoveredURL) = record.locator else {
            return XCTFail("Claude Code record should use a file locator")
        }
        XCTAssertEqual(try adapter.parse(record), try ClaudeCodeParser.parse(fileURL: discoveredURL))
    }

    func testCodexAdapterDiscoversLiveAndArchivedRecordsWithParserParity() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions/2026/07/11", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let source = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let live = sessions.appendingPathComponent("rollout-live.jsonl")
        let archivedFile = archived.appendingPathComponent("rollout-archive.jsonl")
        try FileManager.default.copyItem(at: source, to: live)
        try FileManager.default.copyItem(at: source, to: archivedFile)

        let adapter = CodexSourceAdapter(
            sessionsRoot: root.appendingPathComponent("sessions"),
            archivedSessionsRoot: archived,
            detectorVersion: "detectors-test"
        )
        let inventory = try adapter.discover()

        XCTAssertEqual(inventory.detectedRoots, [root.appendingPathComponent("sessions"), archived])
        XCTAssertEqual(inventory.warnings, [])
        XCTAssertEqual(inventory.records.map(\.stableID), ["rollout-live", "rollout-archive"])
        for record in inventory.records {
            guard case let .file(url) = record.locator else {
                return XCTFail("Codex file record should use a file locator")
            }
            XCTAssertEqual(try adapter.parse(record), try CodexParser.parse(fileURL: url))
        }
    }

    func testCodexLiveRecordWinsOverArchivedDuplicate() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let filename = "rollout-shared.jsonl"
        let live = sessions.appendingPathComponent(filename)
        let archivedFile = archived.appendingPathComponent(filename)
        try "live\n".write(to: live, atomically: true, encoding: .utf8)
        try "archived\n".write(to: archivedFile, atomically: true, encoding: .utf8)

        let inventory = try CodexSourceAdapter(
            sessionsRoot: sessions,
            archivedSessionsRoot: archived,
            detectorVersion: "test"
        ).discover()

        XCTAssertEqual(inventory.records.count, 1)
        XCTAssertEqual(inventory.warnings.first?.code, .duplicateRecord)
        guard case let .file(selected) = inventory.records[0].locator else {
            return XCTFail("Codex record should use a file locator")
        }
        XCTAssertEqual(selected.resolvingSymlinksInPath(), live.resolvingSymlinksInPath())
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

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
