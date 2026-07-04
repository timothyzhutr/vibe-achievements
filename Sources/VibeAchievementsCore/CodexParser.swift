import Foundation

public enum CodexParser {
    private static let iso8601Formatter = SharedISO8601DateFormatter()

    public static func parse(fileURL: URL) throws -> ParsedTranscript {
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        var messages: [NormalizedMessage] = []
        var messageLineIndexes: [Int] = []
        var threadID = fileURL.deletingPathExtension().lastPathComponent
        var cwd: String?
        var createdAt: Date?
        var updatedAt: Date?
        var rawTokens = 0

        for (index, line) in text.split(separator: "\n").enumerated() {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }

            let timestamp = parseISODate(object["timestamp"] as? String)
            createdAt = minDate(createdAt, timestamp)
            updatedAt = maxDate(updatedAt, timestamp)

            guard let payload = object["payload"] as? [String: Any] else { continue }

            if type == "session_meta" {
                threadID = payload["id"] as? String ?? threadID
                cwd = payload["cwd"] as? String ?? cwd
                continue
            }

            if type == "event_msg", payload["type"] as? String == "token_count" {
                // `total_token_usage` is cumulative for the session and can be
                // reported by several events; summing them overcounts. Keep the
                // largest total seen instead.
                rawTokens = max(rawTokens, tokenCount(from: payload["info"]))
                continue
            }

            guard type == "response_item",
                  payload["type"] as? String == "message"
            else { continue }

            let role = parseRole(payload["role"] as? String ?? "unknown")
            let content = TextContent.extract(from: payload["content"])
            if payload["encrypted_content"] != nil, content.isEmpty {
                continue
            }
            messages.append(NormalizedMessage(
                id: "\(threadID)-\(index)",
                threadID: threadID,
                sourceTool: .codex,
                sourceMessageID: nil,
                role: role,
                timestamp: timestamp,
                text: content,
                rawType: "response_item.message"
            ))
            messageLineIndexes.append(index)
        }

        // Re-key messages with the final thread id, in case session_meta
        // appeared after the first response items.
        for index in messages.indices {
            messages[index].id = "\(threadID)-\(messageLineIndexes[index])"
            messages[index].threadID = threadID
        }

        let estimatedTokens = messages.reduce(0) { $0 + $1.estimatedTokens }
        let thread = NormalizedThread(
            id: "codex:\(threadID)",
            sourceTool: .codex,
            sourceThreadID: threadID,
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
            rawTokenCount: rawTokens == 0 ? nil : rawTokens
        )

        return ParsedTranscript(thread: thread, messages: messages)
    }

    private static func tokenCount(from value: Any?) -> Int {
        guard let info = value as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any]
        else { return 0 }
        return (total["input_tokens"] as? Int ?? 0) + (total["output_tokens"] as? Int ?? 0)
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
