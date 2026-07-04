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

        var userTurnCount = 0
        for message in parsed.messages {
            let lowered = message.text.lowercased()
            let isUserTurn = message.role == .user
            if isUserTurn { userTurnCount += 1 }
            if message.charCount >= 2_000 {
                events.append(messageEvent(.longMessageSeen, parsed: parsed, message: message, confidence: "high"))
            }
            // A course-correction requires an existing direction to change, so
            // only count corrections after the first user turn (the contract's
            // `same_thread_after_first_user_turn` window).
            if isUserTurn, userTurnCount > 1,
               containsAny(lowered, ["actually", "wait", "never mind", "scratch that", "instead"]) {
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
            if mentionsAffirmativeSuccess(lowered) {
                events.append(messageEvent(.successSeen, parsed: parsed, message: message, confidence: "high"))
            }
        }

        return events
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static let successTerms = ["it works", "works now", "fixed", "passing", "solved"]

    /// True when the text claims success without a nearby negation. Guards
    /// against "still not fixed" / "tests are not passing" substring-matching a
    /// success term, and against terms embedded in larger words ("unfixed",
    /// "surpassing"). `text` is expected lowercased.
    private static func mentionsAffirmativeSuccess(_ text: String) -> Bool {
        for term in successTerms {
            var searchStart = text.startIndex
            while let range = text.range(of: term, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound

                // Reject matches inside a larger word: "unfixed", "prefixed".
                if range.lowerBound > text.startIndex,
                   text[text.index(before: range.lowerBound)].isLetter {
                    continue
                }

                let windowStart = text.index(range.lowerBound, offsetBy: -18, limitedBy: text.startIndex) ?? text.startIndex
                let preceding = " " + text[windowStart..<range.lowerBound] + " "
                let negated = [" not ", " no ", " never ", " cannot ", " without ", "n't "].contains { preceding.contains($0) }
                if !negated { return true }
            }
        }
        return false
    }

    private static func threadEvent(_ type: EventType, parsed: ParsedTranscript) -> ExtractedEvent {
        ExtractedEvent(type: type, sourceTool: parsed.thread.sourceTool, projectKey: parsed.thread.projectKey, threadID: parsed.thread.id, messageID: nil, timestamp: parsed.thread.updatedAt, confidence: "high")
    }

    private static func messageEvent(_ type: EventType, parsed: ParsedTranscript, message: NormalizedMessage, confidence: String) -> ExtractedEvent {
        ExtractedEvent(type: type, sourceTool: parsed.thread.sourceTool, projectKey: parsed.thread.projectKey, threadID: parsed.thread.id, messageID: message.id, timestamp: message.timestamp, confidence: confidence)
    }
}
