import Foundation

public enum ClaudeCodeParser {
    private static let iso8601Formatter = SharedISO8601DateFormatter()

    public static func parse(fileURL: URL) throws -> ParsedTranscript {
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        var messages: [NormalizedMessage] = []
        var messageLineIndexes: [Int] = []
        let fallbackSessionID = fileURL.deletingPathExtension().lastPathComponent
        var lockedSessionID: String?
        var cwd: String?
        var createdAt: Date?
        var updatedAt: Date?
        var rawTokens = 0
        var sawUsage = false

        for (index, line) in text.split(separator: "\n").enumerated() {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "user" || type == "assistant"
            else { continue }

            let entrySessionID = object["sessionId"] as? String
            if let entrySessionID, !entrySessionID.isEmpty {
                if let lockedSessionID, lockedSessionID != entrySessionID {
                    continue
                }
                lockedSessionID = entrySessionID
            }

            cwd = object["cwd"] as? String ?? cwd
            let timestamp = parseISODate(object["timestamp"] as? String)
            createdAt = minDate(createdAt, timestamp)
            updatedAt = maxDate(updatedAt, timestamp)

            let messageObject = object["message"] as? [String: Any]
            let role = parseRole(messageObject?["role"] as? String ?? type)
            let content = TextContent.extract(from: messageObject?["content"])

            // Claude Code records tool results as top-level `user` entries whose
            // content is only tool_result blocks. They are not human turns, so
            // skip them to avoid inflating user-turn/message/token counts.
            if type == "user", isToolResultOnly(messageObject?["content"]) {
                continue
            }

            if let usage = messageObject?["usage"] as? [String: Any] {
                sawUsage = true
                rawTokens += usage["input_tokens"] as? Int ?? 0
                rawTokens += usage["output_tokens"] as? Int ?? 0
                rawTokens += usage["cache_read_input_tokens"] as? Int ?? 0
                rawTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
            }

            let currentSessionID = lockedSessionID ?? fallbackSessionID
            messages.append(NormalizedMessage(
                id: "\(currentSessionID)-\(index)",
                threadID: currentSessionID,
                sourceTool: .claudeCode,
                sourceMessageID: object["uuid"] as? String,
                role: role,
                timestamp: timestamp,
                text: content,
                rawType: type
            ))
            messageLineIndexes.append(index)
        }

        let sessionID = lockedSessionID ?? fallbackSessionID
        for index in messages.indices {
            messages[index].id = "\(sessionID)-\(messageLineIndexes[index])"
            messages[index].threadID = sessionID
        }

        let estimatedTokens = messages.reduce(0) { $0 + $1.estimatedTokens }
        let thread = NormalizedThread(
            id: "claude_code:\(sessionID)",
            sourceTool: .claudeCode,
            sourceThreadID: sessionID,
            sourcePath: fileURL.path,
            projectPath: cwd,
            projectKey: projectKey(for: cwd),
            title: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messages.count,
            userTurnCount: messages.filter { $0.role == .user }.count,
            assistantTurnCount: messages.filter { $0.role == .assistant }.count,
            estimatedTokens: estimatedTokens,
            rawTokenCount: sawUsage ? rawTokens : nil
        )

        return ParsedTranscript(thread: thread, messages: messages)
    }

    /// True when a message's content is an array made up solely of tool_result
    /// blocks (no human text). A string or mixed/text content returns false.
    private static func isToolResultOnly(_ content: Any?) -> Bool {
        guard let array = content as? [Any], !array.isEmpty else { return false }
        return array.allSatisfy { item in
            (item as? [String: Any])?["type"] as? String == "tool_result"
        }
    }

    private static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return iso8601Formatter.date(from: value)
    }

    private static func parseRole(_ value: String) -> MessageRole {
        MessageRole(rawValue: value) ?? .unknown
    }

    private static func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        return min(lhs, rhs)
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }

    private final class SharedISO8601DateFormatter: @unchecked Sendable {
        private let lock = NSLock()
        private let formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func date(from value: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            return formatter.date(from: value)
        }
    }

}
