import Foundation
import XCTest
@testable import VibeAchievementsCore

final class AntigravitySourceAdapterTests: XCTestCase {
    func testDiscoversOnlyCanonicalTranscriptFilesInUUIDBrainDirectories() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let ideRoot = home.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        let cliRoot = home.appendingPathComponent(".gemini/antigravity-cli/brain", isDirectory: true)
        let ideID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let cliID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))

        try writeTranscript(root: ideRoot, id: ideID, text: #"{"type":"user_input","text":"ide"}"# + "\n")
        try writeTranscript(root: cliRoot, id: cliID, text: #"{"type":"user_input","text":"cli"}"# + "\n")

        let ideDirectory = ideRoot.appendingPathComponent(ideID.uuidString, isDirectory: true)
        try "ignored".write(
            to: ideDirectory.appendingPathComponent(".system_generated/logs/transcript_full.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored".write(
            to: ideDirectory.appendingPathComponent(".system_generated/logs/other.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let nonUUID = ideRoot.appendingPathComponent("not-a-uuid", isDirectory: true)
        try FileManager.default.createDirectory(at: nonUUID, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: nonUUID.appendingPathComponent(".system_generated/logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "ignored".write(
            to: nonUUID.appendingPathComponent(".system_generated/logs/transcript.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let inventory = try makeAdapter(home: home).discover()

        XCTAssertEqual(inventory.records.map(\.stableID), [
            "antigravity:ide:\(ideID.uuidString.lowercased())",
            "antigravity:cli:\(cliID.uuidString.lowercased())"
        ])
        XCTAssertEqual(inventory.records.count, 2)
        XCTAssertTrue(inventory.records.allSatisfy { $0.displayPath.hasSuffix("/.system_generated/logs/transcript.jsonl") })
        XCTAssertFalse(inventory.records.contains { $0.displayPath.contains("transcript_full.jsonl") })
    }

    func testEmptyCanonicalRootsProduceAnEmptyCompleteInventory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let ideRoot = home.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        let cliRoot = home.appendingPathComponent(".gemini/antigravity-cli/brain", isDirectory: true)
        try FileManager.default.createDirectory(at: ideRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cliRoot, withIntermediateDirectories: true)

        let inventory = try makeAdapter(home: home).discover()

        XCTAssertTrue(inventory.records.isEmpty)
        XCTAssertTrue(inventory.warnings.isEmpty)
        XCTAssertTrue(inventory.isComplete)
        XCTAssertEqual(inventory.detectedRoots, [ideRoot, cliRoot])
    }

    func testManualRootsOverrideCanonicalHomeLocations() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let manualIDE = root.appendingPathComponent("manual/ide-brain", isDirectory: true)
        let manualCLI = root.appendingPathComponent("manual/cli-brain", isDirectory: true)
        let ideID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let cliID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        try writeTranscript(root: manualIDE, id: ideID, text: #"{"type":"user_input","text":"manual ide"}"# + "\n")
        try writeTranscript(root: manualCLI, id: cliID, text: #"{"type":"user_input","text":"manual cli"}"# + "\n")

        let inventory = try makeAdapter(home: home, ideRoot: manualIDE, cliRoot: manualCLI).discover()

        XCTAssertEqual(inventory.detectedRoots, [manualIDE, manualCLI])
        XCTAssertEqual(inventory.records.map(\.stableID), [
            "antigravity:ide:\(ideID.uuidString.lowercased())",
            "antigravity:cli:\(cliID.uuidString.lowercased())"
        ])
    }

    func testIDEAndCLIImportsRemainDistinctWithoutDiscoveryContentReads() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let ideID = try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let cliID = try XCTUnwrap(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let transcript = #"{"type":"user_input","timestamp":"2026-07-11T00:00:00Z","text":"same"}"#
            + "\n"
            + #"{"type":"planner_response","timestamp":"2026-07-11T00:00:01Z","text":"history"}"#
            + "\n"
        try writeTranscript(root: home.appendingPathComponent(".gemini/antigravity/brain"), id: ideID, text: transcript)
        try writeTranscript(root: home.appendingPathComponent(".gemini/antigravity-cli/brain"), id: cliID, text: transcript)

        let inventory = try makeAdapter(home: home).discover()

        XCTAssertEqual(inventory.records.map(\.stableID), [
            "antigravity:ide:\(ideID.uuidString.lowercased())",
            "antigravity:cli:\(cliID.uuidString.lowercased())"
        ])
        XCTAssertTrue(inventory.warnings.isEmpty)
    }

    func testDiscoveryDoesNotReadTranscriptContents() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ideRoot = root.appendingPathComponent("ide", isDirectory: true)
        let cliRoot = root.appendingPathComponent("cli", isDirectory: true)
        let ideID = try XCTUnwrap(UUID(uuidString: "99999999-9999-9999-9999-999999999999"))
        try writeTranscript(
            root: ideRoot,
            id: ideID,
            text: #"{"type":"user_input","text":"metadata only"}"#
        )
        try FileManager.default.createDirectory(at: cliRoot, withIntermediateDirectories: true)
        let reads = LockedCounter()
        let adapter = AntigravitySourceAdapter(
            ideBrainRoot: ideRoot,
            cliBrainRoot: cliRoot,
            detectorVersion: "test",
            sourceTool: .antigravity,
            stableReader: { url in
                reads.increment()
                return try Data(contentsOf: url)
            }
        )

        let inventory = try adapter.discover()

        XCTAssertEqual(inventory.records.count, 1)
        XCTAssertEqual(reads.value, 0)
    }

    func testEmptyOrPartialOnlyTranscriptDoesNotReplacePriorState() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ideRoot = root.appendingPathComponent("ide", isDirectory: true)
        let cliRoot = root.appendingPathComponent("cli", isDirectory: true)
        let id = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        try writeTranscript(root: ideRoot, id: id, text: #"{"type":"user_input""#)
        try FileManager.default.createDirectory(at: cliRoot, withIntermediateDirectories: true)
        let adapter = AntigravitySourceAdapter(
            ideBrainRoot: ideRoot,
            cliBrainRoot: cliRoot,
            detectorVersion: "test",
            sourceTool: .antigravity,
            stableReader: { try Data(contentsOf: $0) }
        )
        let record = try XCTUnwrap(adapter.discover().records.first)

        XCTAssertThrowsError(try adapter.parse(record)) { error in
            XCTAssertEqual(error as? ConversationSourceAdapterError, .unsupportedRecord)
        }
    }

    func testPrefixOnlyForksRemainDistinct() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let ideID = try XCTUnwrap(UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
        let cliID = try XCTUnwrap(UUID(uuidString: "88888888-8888-8888-8888-888888888888"))
        let prefix = #"{"type":"user_input","text":"same prefix"}"#
            + "\n"
            + #"{"type":"planner_response","text":"same answer"}"#
            + "\n"
        try writeTranscript(
            root: home.appendingPathComponent(".gemini/antigravity/brain"),
            id: ideID,
            text: prefix
        )
        try writeTranscript(
            root: home.appendingPathComponent(".gemini/antigravity-cli/brain"),
            id: cliID,
            text: prefix + #"{"type":"user_input","text":"different continuation"}"# + "\n"
        )

        let inventory = try makeAdapter(home: home).discover()

        XCTAssertEqual(inventory.records.count, 2)
        XCTAssertTrue(inventory.warnings.isEmpty)
    }

    func testStableReadRetriesOnceWhenFileChangesThenSucceeds() throws {
        let stamps = LockedSequence([
            AntigravityFileStamp(size: 1, modified: Date(timeIntervalSince1970: 1)),
            AntigravityFileStamp(size: 2, modified: Date(timeIntervalSince1970: 2)),
            AntigravityFileStamp(size: 2, modified: Date(timeIntervalSince1970: 2)),
            AntigravityFileStamp(size: 2, modified: Date(timeIntervalSince1970: 2))
        ])
        let reads = LockedSequence([Data("first".utf8), Data("second".utf8)])

        let data = try AntigravityStableReader.read(
            at: URL(fileURLWithPath: "/tmp/trajectory.jsonl"),
            readData: { _ in reads.next() },
            stamp: { _ in stamps.next() }
        )

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "second")
        XCTAssertEqual(reads.count, 2)
    }

    func testStableReadThrowsAfterTheSingleRetryAlsoChanges() throws {
        let stamps = LockedSequence([
            AntigravityFileStamp(size: 1, modified: Date(timeIntervalSince1970: 1)),
            AntigravityFileStamp(size: 2, modified: Date(timeIntervalSince1970: 2)),
            AntigravityFileStamp(size: 3, modified: Date(timeIntervalSince1970: 3)),
            AntigravityFileStamp(size: 4, modified: Date(timeIntervalSince1970: 4))
        ])

        XCTAssertThrowsError(try AntigravityStableReader.read(
            at: URL(fileURLWithPath: "/tmp/trajectory.jsonl"),
            readData: { _ in Data("changing".utf8) },
            stamp: { _ in stamps.next() }
        )) { error in
            XCTAssertEqual(error as? AntigravityReadError, .recordChangedDuringRead)
        }
    }

    private func makeAdapter(
        home: URL,
        ideRoot: URL? = nil,
        cliRoot: URL? = nil
    ) -> AntigravitySourceAdapter {
        AntigravitySourceAdapter(
            home: home,
            ideBrainRoot: ideRoot,
            cliBrainRoot: cliRoot,
            detectorVersion: "test",
            sourceTool: .antigravity
        )
    }

    private func writeTranscript(root: URL, id: UUID, text: String) throws {
        let logs = root
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent(".system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try text.write(to: logs.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("antigravity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class LockedSequence<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value]
    private(set) var count = 0

    init(_ values: [Value]) {
        self.values = values
    }

    func next() -> Value {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return values.removeFirst()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
