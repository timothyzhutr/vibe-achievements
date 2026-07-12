import CryptoKit
import Foundation

public enum AntigravityParseWarningKind: String, Sendable {
    case malformedLine
    case unknownVariant
}

public struct AntigravityParseWarning: Equatable, Sendable {
    public let lineNumber: Int
    public let kind: AntigravityParseWarningKind

    public init(lineNumber: Int, kind: AntigravityParseWarningKind) {
        self.lineNumber = lineNumber
        self.kind = kind
    }
}

public struct AntigravityParseResult: Equatable, Sendable {
    public let transcript: ParsedTranscript
    public let warnings: [AntigravityParseWarning]

    public init(transcript: ParsedTranscript, warnings: [AntigravityParseWarning]) {
        self.transcript = transcript
        self.warnings = warnings
    }
}

public enum AntigravityParser {
    public static func parse(
        fileURL: URL,
        sourceTool: SourceTool,
        stableID: String? = nil
    ) throws -> ParsedTranscript {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let threadID = stableID ?? fileURL.deletingPathExtension().lastPathComponent
        return try parse(
            data: data,
            sourceTool: sourceTool,
            threadID: threadID,
            sourcePath: fileURL.path
        ).transcript
    }

    public static func parse(
        data: Data,
        sourceTool: SourceTool,
        threadID: String,
        sourcePath: String,
        projectPathHint: String? = nil
    ) throws -> AntigravityParseResult {
        let text = String(decoding: data, as: UTF8.self)
        var messages: [NormalizedMessage] = []
        var warnings: [AntigravityParseWarning] = []
        var projectPath = projectPathHint

        for (lineIndex, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let isFinalLine = lineIndex == text.components(separatedBy: "\n").count - 1
            let hasTrailingNewline = text.last == "\n"
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            guard let lineData = line.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: lineData)
            else {
                // A writer can leave an incomplete final JSON object. It is not
                // a malformed historical record until it has a line terminator.
                if isFinalLine && !hasTrailingNewline { continue }
                warnings.append(AntigravityParseWarning(lineNumber: lineIndex + 1, kind: .malformedLine))
                continue
            }

            guard let object = value.objectValue else {
                warnings.append(AntigravityParseWarning(lineNumber: lineIndex + 1, kind: .unknownVariant))
                continue
            }

            projectPath = projectPath ?? Self.projectPath(in: object)
            switch decodeStep(object) {
            case .message(let message):
                let timestamp = timestamp(in: object)
                messages.append(NormalizedMessage(
                    id: "\(threadID)-\(lineIndex)",
                    threadID: threadID,
                    sourceTool: sourceTool,
                    sourceMessageID: identifier(in: object),
                    role: message.role,
                    timestamp: timestamp,
                    text: message.text,
                    rawType: message.rawType
                ))
            case .ignored:
                continue
            case .unknown:
                warnings.append(AntigravityParseWarning(lineNumber: lineIndex + 1, kind: .unknownVariant))
            }
        }

        let timestamps = messages.compactMap(\.timestamp)
        let transcript = ParsedTranscript(
            thread: NormalizedThread(
                id: "\(sourceTool.rawValue):\(threadID)",
                sourceTool: sourceTool,
                sourceThreadID: threadID,
                sourcePath: sourcePath,
                projectPath: projectPath,
                projectKey: projectKey(for: projectPath),
                title: nil,
                createdAt: timestamps.min(),
                updatedAt: timestamps.max(),
                messageCount: messages.count,
                userTurnCount: messages.filter { $0.role == .user }.count,
                assistantTurnCount: messages.filter { $0.role == .assistant }.count,
                estimatedTokens: messages.reduce(0) { $0 + $1.estimatedTokens },
                rawTokenCount: nil
            ),
            messages: messages
        )
        return AntigravityParseResult(transcript: transcript, warnings: warnings)
    }

    public static func normalizedDigest(for transcript: ParsedTranscript) -> String {
        let normalized = transcript.messages.map { message in
            let text = message.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(message.role.rawValue)\u{1f}\(text)"
        }.joined(separator: "\u{1e}")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private enum Step {
        case message(Message)
        case ignored
        case unknown
    }

    private struct Message {
        let role: MessageRole
        let text: String
        let rawType: String
    }

    private static func decodeStep(_ object: [String: JSONValue]) -> Step {
        let type = firstString(in: object, keys: ["type", "kind", "event", "variant"])?.lowercased()
        let role = firstString(in: object, keys: ["role", "sender", "author"])?.lowercased()
        let combined = [type, role].compactMap { $0 }.joined(separator: " ")

        if isToolVariant(combined) {
            return .ignored
        }
        if isIgnoredVariant(combined) {
            return .ignored
        }
        if type == nil && role == nil && projectPath(in: object) != nil {
            return .ignored
        }

        let messageRole: MessageRole
        if isUserVariant(combined) || role == "human" {
            messageRole = .user
        } else if isAssistantVariant(combined) || role == "model" {
            messageRole = .assistant
        } else {
            return .unknown
        }

        let payload = object["payload"]?.objectValue
            ?? object["data"]?.objectValue
            ?? object
        let text = visibleText(in: payload).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .ignored }
        return .message(Message(
            role: messageRole,
            text: text,
            rawType: type ?? role ?? "message"
        ))
    }

    private static func visibleText(in object: [String: JSONValue]) -> String {
        for key in ["text", "content", "message", "response", "output", "markdown", "body"] {
            if let text = textValue(object[key]), !text.isEmpty {
                return text
            }
        }
        return ""
    }

    private static func textValue(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(string):
            return string
        case let .array(array):
            let values = array.compactMap { item -> String? in
                if case let .object(object) = item,
                   let type = firstString(in: object, keys: ["type"])?.lowercased(),
                   type.contains("tool") || type == "image" {
                    return nil
                }
                return textValue(item)
            }
            return values.isEmpty ? nil : values.joined(separator: "\n")
        case let .object(object):
            return visibleText(in: object)
        case .number, .bool, .null:
            return nil
        }
    }

    private static func firstString(in object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func identifier(in object: [String: JSONValue]) -> String? {
        firstString(in: object, keys: ["id", "messageId", "message_id", "eventId", "event_id"])
    }

    private static func projectPath(in object: [String: JSONValue]) -> String? {
        for key in [
            "workspace", "workspacePath", "workspace_path", "currentDirectory",
            "current_directory", "cwd", "projectPath", "project_path"
        ] {
            if let path = pathValue(object[key]), !path.isEmpty {
                return path
            }
        }
        for key in ["payload", "data", "context", "metadata"] {
            if let nested = object[key]?.objectValue, let path = projectPath(in: nested) {
                return path
            }
        }
        return nil
    }

    private static func pathValue(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = value.stringValue { return string }
        guard let object = value.objectValue else { return nil }
        return firstString(in: object, keys: ["path", "uri", "fsPath", "fs_path"])
    }

    private static func timestamp(in object: [String: JSONValue]) -> Date? {
        for key in ["timestamp", "createdAt", "created_at", "time", "ts"] {
            if let date = dateValue(object[key]) { return date }
        }
        for key in ["payload", "data", "metadata"] {
            if let nested = object[key]?.objectValue, let date = timestamp(in: nested) {
                return date
            }
        }
        return nil
    }

    private static func dateValue(_ value: JSONValue?) -> Date? {
        if let string = value?.stringValue {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: string) ?? {
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: string)
            }()
        }
        guard case let .number(number) = value else { return nil }
        return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
    }

    private static func isToolVariant(_ value: String) -> Bool {
        ["tool", "function_call", "function_result", "command", "shell", "file_read", "file_write"]
            .contains { value.contains($0) }
    }

    private static func isIgnoredVariant(_ value: String) -> Bool {
        ["system", "ephemeral", "status", "heartbeat", "metadata", "session"].contains { value.contains($0) }
    }

    private static func isUserVariant(_ value: String) -> Bool {
        ["user_input", "user_message", "user", "human", "input"].contains { value.contains($0) }
    }

    private static func isAssistantVariant(_ value: String) -> Bool {
        ["planner_response", "planner", "assistant", "model_response", "model", "agent_message", "response"].contains { value.contains($0) }
    }
}
