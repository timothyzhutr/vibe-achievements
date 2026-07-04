import Foundation

public enum EventType: String, Codable, Equatable, Sendable {
    case correctionLanguageSeen = "correction_language_seen"
    case stackTraceSeen = "stack_trace_seen"
    case destructiveCleanupSeen = "destructive_cleanup_seen"
    case recoverySeen = "recovery_seen"
    case successSeen = "success_seen"
    case oneMorePromptSeen = "one_more_prompt_seen"
    case longMessageSeen = "long_message_seen"
}

public struct ExtractedEvent: Codable, Equatable, Sendable {
    public var type: EventType
    public var sourceTool: SourceTool
    public var projectKey: String
    public var threadID: String
    public var messageID: String?
    public var timestamp: Date?
    public var confidence: String
}

public enum EventExtractor {
    public static func extract(from parsed: ParsedTranscript) -> [ExtractedEvent] {
        var events: [ExtractedEvent] = []

        if parsed.thread.userTurnCount >= 10 {
            events.append(threadEvent(.oneMorePromptSeen, parsed: parsed))
        }

        for message in parsed.messages {
            let lowered = message.text.lowercased()
            if message.charCount >= 2_000 {
                events.append(messageEvent(.longMessageSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if containsAny(lowered, ["actually", "wait", "never mind", "scratch that", "instead"]) && message.role == .user {
                events.append(messageEvent(.correctionLanguageSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if containsAny(message.text, ["Traceback", "Exception", "TypeError", "ReferenceError", "SyntaxError", "exit code"]) {
                events.append(messageEvent(.stackTraceSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if containsAny(lowered, ["rm -rf", "delete node_modules", "wipe", "nuke", "start over", "clean slate"]) {
                events.append(messageEvent(.destructiveCleanupSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if containsAny(lowered, ["reinstall", "rebuild", "regenerate", "restore"]) {
                events.append(messageEvent(.recoverySeen, parsed: parsed, message: message, confidence: "medium"))
            }
            if containsAny(lowered, ["it works", "fixed", "passing", "solved", "works now"]) {
                events.append(messageEvent(.successSeen, parsed: parsed, message: message, confidence: "high"))
            }
        }

        return events
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func threadEvent(_ type: EventType, parsed: ParsedTranscript) -> ExtractedEvent {
        ExtractedEvent(type: type, sourceTool: parsed.thread.sourceTool, projectKey: parsed.thread.projectKey, threadID: parsed.thread.id, messageID: nil, timestamp: parsed.thread.updatedAt, confidence: "high")
    }

    private static func messageEvent(_ type: EventType, parsed: ParsedTranscript, message: NormalizedMessage, confidence: String) -> ExtractedEvent {
        ExtractedEvent(type: type, sourceTool: parsed.thread.sourceTool, projectKey: parsed.thread.projectKey, threadID: parsed.thread.id, messageID: message.id, timestamp: message.timestamp, confidence: confidence)
    }
}
