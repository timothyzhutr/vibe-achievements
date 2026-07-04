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
}
