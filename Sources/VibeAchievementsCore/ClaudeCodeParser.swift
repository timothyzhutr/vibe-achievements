import Foundation

public enum ClaudeCodeParser {
    public static func parse(fileURL: URL) throws -> ParsedTranscript {
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        var messages: [NormalizedMessage] = []
        var sessionID = fileURL.deletingPathExtension().lastPathComponent
        var cwd: String?
        var createdAt: Date?
        var updatedAt: Date?
        var rawTokens = 0

        for (index, line) in text.split(separator: "\n").enumerated() {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "user" || type == "assistant"
            else { continue }

            sessionID = object["sessionId"] as? String ?? sessionID
            cwd = object["cwd"] as? String ?? cwd
            let timestamp = parseISODate(object["timestamp"] as? String)
            createdAt = minDate(createdAt, timestamp)
            updatedAt = maxDate(updatedAt, timestamp)

            let messageObject = object["message"] as? [String: Any]
            let role = parseRole(messageObject?["role"] as? String ?? type)
            let content = TextContent.extract(from: messageObject?["content"])

            if let usage = messageObject?["usage"] as? [String: Any] {
                rawTokens += usage["input_tokens"] as? Int ?? 0
                rawTokens += usage["output_tokens"] as? Int ?? 0
                rawTokens += usage["cache_read_input_tokens"] as? Int ?? 0
                rawTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
            }

            messages.append(NormalizedMessage(
                id: "\(sessionID)-\(index)",
                threadID: sessionID,
                sourceTool: .claudeCode,
                sourceMessageID: object["uuid"] as? String,
                role: role,
                timestamp: timestamp,
                text: content,
                rawType: type
            ))
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
            rawTokenCount: rawTokens == 0 ? nil : rawTokens
        )

        return ParsedTranscript(thread: thread, messages: messages)
    }
}

func parseISODate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return ISO8601DateFormatter().date(from: value)
}

func parseRole(_ value: String) -> MessageRole {
    MessageRole(rawValue: value) ?? .unknown
}

func minDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    guard let rhs else { return lhs }
    guard let lhs else { return rhs }
    return min(lhs, rhs)
}

func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    guard let rhs else { return lhs }
    guard let lhs else { return rhs }
    return max(lhs, rhs)
}
