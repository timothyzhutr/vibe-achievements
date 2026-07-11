import Foundation
import CryptoKit

public struct OpenCodeLegacyStoreReader {
    public enum Error: Swift.Error, Equatable {
        case missingSession
        case malformedJSON(path: String)
        case recordChangedDuringRead
    }

    private let attemptHook: ((Int) -> Void)?

    public init() {
        attemptHook = nil
    }

    init(attemptHook: @escaping (Int) -> Void) {
        self.attemptHook = attemptHook
    }

    public func parse(storageRoot: URL, projectID: String, sessionID: String) throws -> ParsedTranscript {
        let sessionURL = sessionURL(storageRoot: storageRoot, projectID: projectID, sessionID: sessionID)
        for attempt in 0...1 {
            let sessionData = try readJSON(at: sessionURL)
            let messageIDs = referencedIDs(from: sessionData, keys: ["messageIds", "messageIDs", "messages"])
            let messageURLs = messageIDs.map { messageURL(storageRoot: storageRoot, sessionID: sessionID, messageID: $0) }
            var messageObjects: [(id: String, object: [String: Any], url: URL)] = []
            var partURLs: [URL] = []
            for (messageID, messageURL) in zip(messageIDs, messageURLs) {
                let message = try readJSON(at: messageURL)
                messageObjects.append((messageID, message, messageURL))
                let partIDs = referencedIDs(from: message, keys: ["partIds", "partIDs", "parts"])
                partURLs.append(contentsOf: partIDs.map { partURL(storageRoot: storageRoot, messageID: messageID, partID: $0) })
            }

            let projectURL = storageRoot.appendingPathComponent("project/\(projectID).json")
            let project = (try? readJSON(at: projectURL)) ?? [:]
            let allPaths = [sessionURL, projectURL] + messageURLs + partURLs
            let before = signatures(for: allPaths)
            var partsByMessage: [String: [[String: Any]]] = [:]
            for (messageID, _) in zip(messageIDs, messageURLs) {
                let message = messageObjects.first { $0.id == messageID }?.object ?? [:]
                let partIDs = referencedIDs(from: message, keys: ["partIds", "partIDs", "parts"])
                partsByMessage[messageID] = try partIDs.map { try readJSON(at: partURL(storageRoot: storageRoot, messageID: messageID, partID: $0)) }
                    .sorted { lhs, rhs in
                        let leftDate = OpenCodeSupport.date(lhs, keys: ["time_created", "timeCreated", "timestamp"])
                        let rightDate = OpenCodeSupport.date(rhs, keys: ["time_created", "timeCreated", "timestamp"])
                        let leftID = OpenCodeSupport.string(lhs, keys: ["id"]) ?? ""
                        let rightID = OpenCodeSupport.string(rhs, keys: ["id"]) ?? ""
                        return (leftDate ?? .distantPast, leftID) < (rightDate ?? .distantPast, rightID)
                    }
            }
            attemptHook?(attempt)
            let after = signatures(for: allPaths)
            guard before == after else {
                if attempt == 1 { throw Error.recordChangedDuringRead }
                continue
            }

            let projectPath = OpenCodeSupport.string(project, keys: ["worktree", "directory", "path"])
            let sessionPath = OpenCodeSupport.string(sessionData, keys: ["worktree", "directory", "projectDirectory"])
            let drafts = messageObjects
                .sorted { lhs, rhs in
                    let leftDate = OpenCodeSupport.date(lhs.object, keys: ["time_created", "timeCreated", "timestamp"])
                    let rightDate = OpenCodeSupport.date(rhs.object, keys: ["time_created", "timeCreated", "timestamp"])
                    return (leftDate ?? .distantPast, lhs.id) < (rightDate ?? .distantPast, rhs.id)
                }
                .compactMap { message -> OpenCodeMessageDraft? in
                    guard let role = OpenCodeSupport.role(from: OpenCodeSupport.string(message.object, keys: ["role", "type"])) else {
                        return nil
                    }
                    let parts = partsByMessage[message.id] ?? []
                    let partText = parts.compactMap { part -> String? in
                        guard OpenCodeSupport.string(part, keys: ["type"]) == "text" else { return nil }
                        let text = OpenCodeSupport.text(from: part["text"] ?? part["content"])
                        return text.isEmpty ? nil : text
                    }.joined(separator: "\n")
                    let text = partText.isEmpty
                        ? OpenCodeSupport.text(from: message.object["text"] ?? message.object["content"])
                        : partText
                    guard !text.isEmpty else { return nil }
                    let tokenCount = OpenCodeSupport.tokens(from: message.object)
                        + parts.reduce(0) { $0 + OpenCodeSupport.tokens(from: $1) }
                    return OpenCodeMessageDraft(
                        id: message.id,
                        role: role,
                        timestamp: OpenCodeSupport.date(message.object, keys: ["time_created", "timeCreated", "timestamp"]),
                        text: text,
                        rawType: "legacy.\(OpenCodeSupport.string(message.object, keys: ["type", "role"]) ?? "unknown")",
                        tokenCount: tokenCount
                    )
                }
            let rawTokens = drafts.filter { $0.role == .assistant }.reduce(0) { $0 + $1.tokenCount }
            return OpenCodeSupport.transcript(
                sessionID: sessionID,
                sourcePath: sessionURL.path,
                projectPath: projectPath ?? sessionPath,
                title: OpenCodeSupport.string(sessionData, keys: ["title", "name"]),
                createdAt: OpenCodeSupport.date(sessionData, keys: ["time_created", "timeCreated", "createdAt"]),
                updatedAt: OpenCodeSupport.date(sessionData, keys: ["time_updated", "timeUpdated", "updatedAt"]),
                drafts: drafts,
                rawTokenCount: rawTokens > 0 ? rawTokens : nil
            )
        }
        throw Error.recordChangedDuringRead
    }

    func fingerprint(storageRoot: URL, projectID: String, sessionID: String, detectorVersion: String) throws -> String {
        let sessionURL = sessionURL(storageRoot: storageRoot, projectID: projectID, sessionID: sessionID)
        let sessionData = try readJSON(at: sessionURL)
        let messageIDs = referencedIDs(from: sessionData, keys: ["messageIds", "messageIDs", "messages"])
        var paths = [sessionURL, storageRoot.appendingPathComponent("project/\(projectID).json")]
        for messageID in messageIDs {
            let messageURL = messageURL(storageRoot: storageRoot, sessionID: sessionID, messageID: messageID)
            paths.append(messageURL)
            if let message = try? readJSON(at: messageURL) {
                let partIDs = referencedIDs(from: message, keys: ["partIds", "partIDs", "parts"])
                paths.append(contentsOf: partIDs.map { partURL(storageRoot: storageRoot, messageID: messageID, partID: $0) })
            }
        }
        return "\(detectorVersion)-legacy-" + signatures(for: paths).map { "\($0.path):\($0.size):\($0.modified)" }.joined(separator: "|")
    }

    private struct FileSignature: Equatable {
        let path: String
        let size: Int
        let modified: TimeInterval
        let digest: String
    }

    private func signatures(for urls: [URL]) -> [FileSignature] {
        urls.sorted { $0.path < $1.path }.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return FileSignature(
                path: url.path,
                size: values?.fileSize ?? -1,
                modified: values?.contentModificationDate?.timeIntervalSince1970 ?? -1,
                digest: (try? SHA256.hash(data: Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()) ?? "missing"
            )
        }
    }

    private func readJSON(at url: URL) throws -> [String: Any] {
        guard let object = OpenCodeSupport.jsonObject(data: try Data(contentsOf: url)) else {
            if FileManager.default.fileExists(atPath: url.path) {
                throw Error.malformedJSON(path: url.path)
            }
            throw Error.missingSession
        }
        return object
    }

    private func referencedIDs(from object: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let values = object[key] as? [String] { return values }
            if let values = object[key] as? [[String: Any]] {
                return values.compactMap { OpenCodeSupport.string($0, keys: ["id", "messageId", "partId"]) }
            }
        }
        return []
    }

    private func sessionURL(storageRoot: URL, projectID: String, sessionID: String) -> URL {
        storageRoot.appendingPathComponent("session/\(projectID)/\(sessionID).json")
    }

    private func messageURL(storageRoot: URL, sessionID: String, messageID: String) -> URL {
        storageRoot.appendingPathComponent("message/\(sessionID)/\(messageID).json")
    }

    private func partURL(storageRoot: URL, messageID: String, partID: String) -> URL {
        storageRoot.appendingPathComponent("part/\(messageID)/\(partID).json")
    }
}
