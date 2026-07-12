import XCTest
@testable import VibeAchievementsCore

final class OpenCodeLegacyStoreReaderTests: XCTestCase {
    func testReadsReferencedLegacyFilesInStableOrderAndUsesProjectDirectory() throws {
        let fixture = try LegacyFixture()
        defer { fixture.remove() }
        try fixture.writeProject()
        try fixture.writeSession(messageIDs: ["message-b", "message-a"])
        try fixture.writeMessage(id: "message-a", role: "user", time: 1000, partIDs: ["part-b", "part-a"])
        try fixture.writeMessage(id: "message-b", role: "assistant", time: 2000, partIDs: ["part-c"])
        try fixture.writePart(id: "part-a", messageID: "message-a", time: 1000, type: "text", text: "first")
        try fixture.writePart(id: "part-b", messageID: "message-a", time: 1000, type: "text", text: "second")
        try fixture.writePart(id: "part-c", messageID: "message-b", time: 2000, type: "text", text: "answer")

        let parsed = try OpenCodeLegacyStoreReader().parse(
            storageRoot: fixture.storage,
            projectID: fixture.projectID,
            sessionID: fixture.sessionID
        )

        XCTAssertEqual(parsed.thread.projectPath, "/legacy/project")
        XCTAssertEqual(parsed.messages.map(\.sourceMessageID), ["message-a", "message-b"])
        XCTAssertEqual(parsed.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(parsed.messages.map(\.text), ["first\nsecond", "answer"])
        XCTAssertEqual(parsed.thread.id, "opencode:\(fixture.sessionID)")
    }

    func testRetriesWhenReferencedFilesChangeDuringRead() throws {
        let fixture = try LegacyFixture()
        defer { fixture.remove() }
        try fixture.writeProject()
        try fixture.writeSession(messageIDs: ["message-1"])
        try fixture.writeMessage(id: "message-1", role: "user", time: 1000, partIDs: ["part-1"])
        try fixture.writePart(id: "part-1", messageID: "message-1", time: 1000, type: "text", text: "stable")

        let reader = OpenCodeLegacyStoreReader(attemptHook: { attempt in
            guard attempt == 0 else { return }
            try? "{\"id\":\"message-1\",\"role\":\"user\",\"time_created\":1000,\"partIds\":[\"part-1\"],\"changed\":true}".write(
                to: fixture.messageURL("message-1"),
                atomically: true,
                encoding: .utf8
            )
        })

        let parsed = try reader.parse(storageRoot: fixture.storage, projectID: fixture.projectID, sessionID: fixture.sessionID)

        XCTAssertEqual(parsed.messages.count, 1)
    }

    func testThrowsAfterRecordChangesAcrossBothAttempts() throws {
        let fixture = try LegacyFixture()
        defer { fixture.remove() }
        try fixture.writeProject()
        try fixture.writeSession(messageIDs: ["message-1"])
        try fixture.writeMessage(id: "message-1", role: "user", time: 1000, partIDs: ["part-1"])
        try fixture.writePart(id: "part-1", messageID: "message-1", time: 1000, type: "text", text: "unstable")

        let reader = OpenCodeLegacyStoreReader(attemptHook: { _ in
            try? "{\"id\":\"message-1\",\"role\":\"user\",\"time_created\":1000,\"partIds\":[\"part-1\"],\"changed\":\"\(UUID().uuidString)\"}".write(
                to: fixture.messageURL("message-1"),
                atomically: true,
                encoding: .utf8
            )
        })

        XCTAssertThrowsError(
            try reader.parse(storageRoot: fixture.storage, projectID: fixture.projectID, sessionID: fixture.sessionID)
        ) { error in
            XCTAssertEqual(error as? OpenCodeLegacyStoreReader.Error, .recordChangedDuringRead)
        }
    }

    func testUsesLegacyDirectoryLayoutWhenJSONOmitsChildIDLists() throws {
        let fixture = try LegacyFixture()
        defer { fixture.remove() }
        try fixture.writeProject()
        try fixture.writeSessionWithoutMessageIDs()
        try fixture.writeMessageWithoutPartIDs(id: "message-1", role: "user", time: 1000)
        try fixture.writePart(id: "part-1", messageID: "message-1", time: 1000, type: "text", text: "directory linked")

        let parsed = try OpenCodeLegacyStoreReader().parse(
            storageRoot: fixture.storage,
            projectID: fixture.projectID,
            sessionID: fixture.sessionID
        )

        XCTAssertEqual(parsed.messages.map(\.sourceMessageID), ["message-1"])
        XCTAssertEqual(parsed.messages.map(\.text), ["directory linked"])
    }

    func testUnreadableChildContainerDoesNotBecomeAnEmptyTranscript() throws {
        let fixture = try LegacyFixture()
        defer { fixture.remove() }
        try fixture.writeProject()
        try fixture.writeSessionWithoutMessageIDs()
        let messageContainer = fixture.storage.appendingPathComponent(
            "message/\(fixture.sessionID)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: messageContainer.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not-a-directory".write(to: messageContainer, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try OpenCodeLegacyStoreReader().parse(
            storageRoot: fixture.storage,
            projectID: fixture.projectID,
            sessionID: fixture.sessionID
        ))
    }
}

private final class LegacyFixture {
    let root: URL
    let storage: URL
    let projectID = "project-legacy"
    let sessionID = "session-legacy"

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeLegacyTests-\(UUID().uuidString)", isDirectory: true)
        storage = root.appendingPathComponent("storage", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    }

    func writeProject() throws {
        try writeOpenCodeJSON(
            ["id": projectID, "directory": "/legacy/project"],
            to: storage.appendingPathComponent("project/\(projectID).json")
        )
    }

    func writeSession(messageIDs: [String]) throws {
        try writeOpenCodeJSON(
            ["id": sessionID, "directory": "/session/fallback", "messageIds": messageIDs],
            to: storage.appendingPathComponent("session/\(projectID)/\(sessionID).json")
        )
    }

    func writeSessionWithoutMessageIDs() throws {
        try writeOpenCodeJSON(
            ["id": sessionID, "directory": "/session/fallback"],
            to: storage.appendingPathComponent("session/\(projectID)/\(sessionID).json")
        )
    }

    func writeMessage(id: String, role: String, time: Int, partIDs: [String]) throws {
        try writeOpenCodeJSON(
            ["id": id, "role": role, "time_created": time, "partIds": partIDs],
            to: messageURL(id)
        )
    }

    func writeMessageWithoutPartIDs(id: String, role: String, time: Int) throws {
        try writeOpenCodeJSON(
            ["id": id, "role": role, "time_created": time],
            to: messageURL(id)
        )
    }

    func writePart(id: String, messageID: String, time: Int, type: String, text: String) throws {
        try writeOpenCodeJSON(
            ["id": id, "messageId": messageID, "type": type, "time_created": time, "text": text],
            to: storage.appendingPathComponent("part/\(messageID)/\(id).json")
        )
    }

    func messageURL(_ id: String) -> URL {
        storage.appendingPathComponent("message/\(sessionID)/\(id).json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
