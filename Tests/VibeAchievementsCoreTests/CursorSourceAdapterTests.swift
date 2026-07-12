import XCTest
import SQLite3
@testable import VibeAchievementsCore

final class CursorSourceAdapterTests: XCTestCase {
    func testDefaultRootsUseCursorApplicationSupportAndProjects() {
        let home = URL(fileURLWithPath: "/tmp/cursor-home")

        let roots = CursorSourceAdapter.defaultRoots(home: home)

        XCTAssertEqual(
            roots.applicationSupport,
            home.appendingPathComponent("Library/Application Support/Cursor")
        )
        XCTAssertEqual(roots.projects, home.appendingPathComponent(".cursor/projects"))
    }

    func testManualRootsAreUsedForDiscovery() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationSupport = root.appendingPathComponent("cursor-app", isDirectory: true)
        let projects = root.appendingPathComponent("cursor-projects", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

        let adapter = CursorSourceAdapter(
            roots: CursorRoots(applicationSupport: applicationSupport, projects: projects),
            detectorVersion: "cursor-test"
        )

        let inventory = try adapter.discover()

        XCTAssertEqual(inventory.detectedRoots, [applicationSupport, projects])
        XCTAssertTrue(inventory.records.isEmpty)
        XCTAssertTrue(inventory.warnings.isEmpty)
    }

    func testDiscoveryFindsGlobalWorkspaceAndTranscriptRecordsButIgnoresUnrelatedKeys() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationSupport = root.appendingPathComponent("Cursor", isDirectory: true)
        let globalStorage = applicationSupport.appendingPathComponent("User/globalStorage", isDirectory: true)
        let workspaceStorage = applicationSupport.appendingPathComponent("User/workspaceStorage/ws-1", isDirectory: true)
        let projects = root.appendingPathComponent(".cursor/projects/project-slug/agent-transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: globalStorage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceStorage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let nestedTranscripts = projects.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedTranscripts, withIntermediateDirectories: true)

        let globalDatabase = globalStorage.appendingPathComponent("state.vscdb")
        try makeDatabase(at: globalDatabase, composerID: "global-composer", workspaceID: "workspace-1")
        let workspaceDatabase = workspaceStorage.appendingPathComponent("state.vscdb")
        try makeDatabase(at: workspaceDatabase, composerID: "legacy-composer", workspaceID: "workspace-1")
        try "{}\n".write(
            to: projects.appendingPathComponent("transcript-1.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try "{}\n".write(
            to: nestedTranscripts.appendingPathComponent("transcript-2.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try "ignore\n".write(
            to: projects.deletingLastPathComponent().appendingPathComponent("unrelated.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let inventory = try CursorSourceAdapter(
            roots: CursorRoots(applicationSupport: applicationSupport, projects: root.appendingPathComponent(".cursor/projects")),
            detectorVersion: "cursor-test"
        ).discover()

        XCTAssertTrue(inventory.isComplete)
        XCTAssertEqual(inventory.records.filter { $0.sourceTool == .cursor }.count, 4)
        XCTAssertTrue(inventory.records.allSatisfy { $0.fingerprint.hasPrefix("cursor-test-") })
        XCTAssertFalse(inventory.records.contains { $0.stableID.contains("checkpoint") })
        XCTAssertEqual(
            inventory.records.filter {
                guard case .file = $0.locator else { return false }
                return $0.stableID.contains("project-slug")
            }.count,
            2
        )
    }

    func testMissingConfiguredRootsAreIncompleteNotEmptyComplete() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missingApplicationSupport = root.appendingPathComponent("missing-cursor")
        let missingProjects = root.appendingPathComponent("missing-projects")

        let inventory = try CursorSourceAdapter(
            roots: CursorRoots(applicationSupport: missingApplicationSupport, projects: missingProjects),
            detectorVersion: "cursor-test"
        ).discover()

        XCTAssertFalse(inventory.isComplete)
        XCTAssertEqual(inventory.records.count, 0)
        XCTAssertFalse(inventory.warnings.isEmpty)
    }

    func testMissingGenerationKeepsDiscoveryConservative() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationSupport = root.appendingPathComponent("Cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)

        let inventory = try CursorSourceAdapter(
            roots: CursorRoots(
                applicationSupport: applicationSupport,
                projects: root.appendingPathComponent("missing-projects")
            ),
            detectorVersion: "cursor-test"
        ).discover()

        XCTAssertFalse(inventory.isComplete)
        XCTAssertEqual(inventory.warnings.count, 1)
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDatabase(at url: URL, composerID: String, workspaceID: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw FixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER, lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER, value TEXT);
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO composerHeaders VALUES ('\(composerID)', '\(workspaceID)', 1, 2, 0, 0, 2, 0, '{}');
        INSERT INTO cursorDiskKV VALUES ('composerData:\(composerID)', '{}');
        INSERT INTO cursorDiskKV VALUES ('checkpointId:ignored', '{}');
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.sqlite }
    }
}

private enum FixtureError: Error {
    case sqlite
}
