import Foundation

public enum EventType: String, Codable, Equatable, Sendable {
    case correctionLanguageSeen = "correction_language_seen"
    case implementationOrFixSeen = "implementation_or_fix_seen"
    case stackTraceSeen = "stack_trace_seen"
    case destructiveCleanupSeen = "destructive_cleanup_seen"
    case recoverySeen = "recovery_seen"
    case successSeen = "success_seen"
    case oneMorePromptSeen = "one_more_prompt_seen"
    case longMessageSeen = "long_message_seen"
    case longThreadSeen = "long_thread_seen"
    case creationRequestSeen = "creation_request_seen"
    case mvpLanguageSeen = "mvp_language_seen"
    case contextLimitSeen = "context_limit_seen"
    case tokenBudgetSeen = "token_budget_seen"
    case uncertainSuccessSeen = "uncertain_success_seen"
    case uncertaintySeen = "uncertainty_seen"
    case doNotTouchSeen = "do_not_touch_seen"
    case approvalLanguageSeen = "approval_language_seen"
    case productionLanguageSeen = "production_language_seen"
    case uiControlSeen = "ui_control_seen"
    case cacheRitualSeen = "cache_ritual_seen"
    case shipLanguageSeen = "ship_language_seen"
    case assistantPushbackSeen = "assistant_pushback_seen"
    case userTurnSeen = "user_turn_seen"
    case backgroundContextSeen = "background_context_seen"
    case reasoningSeen = "reasoning_seen"
    case conclusionSeen = "conclusion_seen"
    case codeChangeRequestSeen = "code_change_request_seen"
    case iterationTermSeen = "iteration_term_seen"
    case verificationFailureSeen = "verification_failure_seen"
    case verificationSuccessSeen = "verification_success_seen"
    case failureSeen = "failure_seen"
    case styleAdjustmentSeen = "style_adjustment_seen"
    case frontendContextSeen = "frontend_context_seen"
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
    private static let longThreadTurns = 8
    private static let longMessageCharacters = 2_000

    public static func extract(from parsed: ParsedTranscript) -> [ExtractedEvent] {
        var events: [ExtractedEvent] = []

        if parsed.thread.userTurnCount >= 10 {
            events.append(threadEvent(.oneMorePromptSeen, parsed: parsed))
        }
        if parsed.thread.userTurnCount >= longThreadTurns {
            events.append(threadEvent(.longThreadSeen, parsed: parsed))
        }

        var userTurnCount = 0
        for message in parsed.messages {
            let lowered = message.text.lowercased()
            let isUserTurn = message.role == .user
            let isConversationTurn = isUserTurn || message.role == .assistant
            guard isConversationTurn else { continue }

            if isUserTurn {
                userTurnCount += 1
                events.append(messageEvent(.userTurnSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if message.charCount >= longMessageCharacters {
                events.append(messageEvent(.longMessageSeen, parsed: parsed, message: message, confidence: "high"))
            }
            // A course-correction requires an existing direction to change, so
            // only count corrections after the first user turn (the contract's
            // `same_thread_after_first_user_turn` window).
            if isUserTurn, userTurnCount > 1,
               containsAnyPhrase(lowered, ["actually", "wait", "never mind", "scratch that", "instead"]) {
                events.append(messageEvent(.correctionLanguageSeen, parsed: parsed, message: message, confidence: "high"))
            }
            for rule in keywordRules where rule.matches(message: message, lowered: lowered) {
                events.append(messageEvent(rule.event, parsed: parsed, message: message, confidence: rule.confidence))
            }
            for _ in matchingPhraseStarts(in: lowered, phrases: iterationTerms) {
                events.append(messageEvent(.iterationTermSeen, parsed: parsed, message: message, confidence: "medium"))
            }
            if mentionsDestructiveCleanup(lowered) {
                events.append(messageEvent(.destructiveCleanupSeen, parsed: parsed, message: message, confidence: "high"))
            }
            for _ in matchingPhraseStarts(in: lowered, phrases: styleAdjustmentTerms) {
                events.append(messageEvent(.styleAdjustmentSeen, parsed: parsed, message: message, confidence: "medium"))
            }
            if isUserTurn, hasCreationIntent(in: lowered) {
                events.append(messageEvent(.creationRequestSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if mentionsAffirmativeSuccess(lowered) {
                events.append(messageEvent(.successSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if hasVerificationFailure(in: lowered) {
                events.append(messageEvent(.verificationFailureSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if hasVerificationSuccess(in: lowered) {
                events.append(messageEvent(.verificationSuccessSeen, parsed: parsed, message: message, confidence: "high"))
            }
            if mentionsFailure(lowered) {
                events.append(messageEvent(.failureSeen, parsed: parsed, message: message, confidence: "medium"))
            }
        }

        return events
    }

    private struct KeywordRule {
        var event: EventType
        var phrases: [String]
        var role: MessageRole?
        var caseSensitive: Bool = false
        var confidence: String = "medium"

        func matches(message: NormalizedMessage, lowered: String) -> Bool {
            if let role, message.role != role { return false }
            let text = caseSensitive ? message.text : lowered
            let phrases = caseSensitive ? phrases : phrases.map { $0.lowercased() }
            return containsAnyPhrase(text, phrases)
        }
    }

    private static let keywordRules: [KeywordRule] = [
        KeywordRule(event: .stackTraceSeen, phrases: ["Traceback", "Exception", "TypeError", "ReferenceError", "SyntaxError", "Error:", "exit code", "panic", "fatal"], caseSensitive: true, confidence: "high"),
        KeywordRule(event: .implementationOrFixSeen, phrases: ["implement", "implemented", "build", "built", "fix", "fixed", "patch", "code", "scaffold", "create files"], confidence: "high"),
        KeywordRule(event: .recoverySeen, phrases: ["reinstall", "rebuild", "regenerate", "restore"], confidence: "medium"),
        KeywordRule(event: .mvpLanguageSeen, phrases: ["mvp", "prototype", "quick build", "side project", "weekend project", "hackathon", "poc", "proof of concept"], confidence: "high"),
        KeywordRule(event: .contextLimitSeen, phrases: ["context window", "context limit", "compaction", "compacted", "token limit", "out of context", "running out of context", "summarize before"], confidence: "high"),
        KeywordRule(event: .tokenBudgetSeen, phrases: ["tokens", "cost", "usage limit", "rate limit", "budget", "context management", "remaining context"], confidence: "medium"),
        KeywordRule(event: .uncertainSuccessSeen, phrases: ["not sure why this works", "somehow it works", "somehow passing", "no idea why it works", "inexplicably"], confidence: "medium"),
        KeywordRule(event: .uncertaintySeen, phrases: ["i don't know why", "not sure why", "somehow this fixed", "unclear why", "beats me"], confidence: "medium"),
        KeywordRule(event: .doNotTouchSeen, phrases: ["don't touch", "leave it", "don't change", "no refactor", "stop here", "ship it as is"], confidence: "medium"),
        KeywordRule(event: .approvalLanguageSeen, phrases: ["lgtm", "looks good", "ship it", "approved", "good to merge", "ready to merge"], confidence: "high"),
        KeywordRule(event: .productionLanguageSeen, phrases: ["production", "deploy", "in prod", "real users", "go live", "launch it"], confidence: "medium"),
        KeywordRule(event: .uiControlSeen, phrases: ["button", "modal", "sidebar", "dropdown", "toggle", "checkbox", "settings panel", "menu bar", "tab"], confidence: "high"),
        KeywordRule(event: .cacheRitualSeen, phrases: ["clear cache", "restart server", "reinstall", "delete node_modules", "clean build", "remove dist", "wipe cache"], confidence: "high"),
        KeywordRule(event: .shipLanguageSeen, phrases: ["commit", "pr", "pull request", "merge", "release", "deploy", "publish", "shipped", "send it"], confidence: "high"),
        KeywordRule(event: .assistantPushbackSeen, phrases: ["i'd avoid", "i would avoid", "i recommend against", "that's risky", "a safer approach", "instead i'd suggest", "instead i suggest", "i wouldn't"], role: .assistant, confidence: "medium"),
        KeywordRule(event: .backgroundContextSeen, phrases: ["for context", "background", "some history", "to explain", "the situation is"], role: .user, confidence: "medium"),
        KeywordRule(event: .reasoningSeen, phrases: ["let me think", "reasoning", "the tradeoff", "on one hand", "considering"], confidence: "medium"),
        KeywordRule(event: .conclusionSeen, phrases: ["so the answer", "conclusion", "therefore", "in that case i'd", "makes sense to"], confidence: "medium"),
        KeywordRule(event: .codeChangeRequestSeen, phrases: ["edit", "patch", "apply", "write the code", "change the file", "implement", "refactor"], confidence: "medium"),
        KeywordRule(event: .frontendContextSeen, phrases: ["css", "ui", "layout", "component", "styling", "front end", "tailwind", "flexbox"], confidence: "medium")
    ]

    private static let creationIntentTerms = ["build", "create", "make", "scaffold", "generate", "spin up"]
    private static let creationTargetTerms = ["app", "tool", "site", "feature", "component", "script", "plugin"]
    private static let iterationTerms = ["fix", "run", "retry", "again", "still failing", "try once more", "adjust"]
    private static let styleAdjustmentTerms = ["margin", "padding", "spacing", "align", "color", "font", "css", "layout", "pixel"]
    private static let verificationTerms = ["test", "tests", "build", "lint", "ci", "suite"]
    private static let verificationFailureTerms = ["fails", "failing", "red", "broken"]
    private static let verificationSuccessTerms = ["passes", "passing", "green", "all pass"]
    private static let failureTerms = ["broken", "failing", "doesn't work", "stuck", "error", "blew up", "crash"]
    private static let destructiveCleanupTerms = ["rm -rf", "delete node_modules", "wipe", "nuke", "start over", "clean slate"]

    private static func mentionsDestructiveCleanup(_ text: String) -> Bool {
        for term in destructiveCleanupTerms {
            var searchStart = text.startIndex
            while let range = text.range(of: term, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound
                let windowStart = text.index(range.lowerBound, offsetBy: -32, limitedBy: text.startIndex) ?? text.startIndex
                let preceding = " " + text[windowStart..<range.lowerBound] + " "
                let warned = [" do not ", " don't ", " dont ", " never ", " avoid ", " warning ", " no "].contains { preceding.contains($0) }
                if !warned { return true }
            }
        }
        return false
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

    private static func hasCreationIntent(in text: String) -> Bool {
        containsAnyPhrase(text, creationIntentTerms) && containsAnyPhrase(text, creationTargetTerms)
    }

    private static func hasVerificationFailure(in text: String) -> Bool {
        containsAnyPhrase(text, verificationTerms) && containsAnyPhrase(text, verificationFailureTerms)
    }

    private static func hasVerificationSuccess(in text: String) -> Bool {
        containsAnyPhrase(text, verificationTerms) && containsAnyPhrase(text, verificationSuccessTerms)
    }

    private static func mentionsFailure(_ text: String) -> Bool {
        containsAnyPhrase(text, failureTerms)
    }

    private static func containsAnyPhrase(_ text: String, _ phrases: [String]) -> Bool {
        !matchingPhraseStarts(in: text, phrases: phrases).isEmpty
    }

    private static func matchingPhraseStarts(in text: String, phrases: [String]) -> [String.Index] {
        var starts: [String.Index] = []
        for phrase in phrases {
            var searchStart = text.startIndex
            while let range = text.range(of: phrase, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound
                // Whole-word match: the token must be bounded on both sides, so
                // short tokens ("pr", "tab", "ci") don't match as prefixes of
                // unrelated words ("project", "table", "city").
                if startsAtWordishBoundary(range.lowerBound, in: text),
                   endsAtWordishBoundary(range.upperBound, in: text) {
                    starts.append(range.lowerBound)
                }
            }
        }
        return starts
    }

    private static func startsAtWordishBoundary(_ index: String.Index, in text: String) -> Bool {
        index == text.startIndex || !text[text.index(before: index)].isLetter
    }

    private static func endsAtWordishBoundary(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || !text[index].isLetter
    }

    private static func threadEvent(_ type: EventType, parsed: ParsedTranscript) -> ExtractedEvent {
        ExtractedEvent(type: type, sourceTool: parsed.thread.sourceTool, projectKey: parsed.thread.projectKey, threadID: parsed.thread.id, messageID: nil, timestamp: parsed.thread.updatedAt, confidence: "high")
    }

    private static func messageEvent(_ type: EventType, parsed: ParsedTranscript, message: NormalizedMessage, confidence: String) -> ExtractedEvent {
        ExtractedEvent(type: type, sourceTool: parsed.thread.sourceTool, projectKey: parsed.thread.projectKey, threadID: parsed.thread.id, messageID: message.id, timestamp: message.timestamp, confidence: confidence)
    }
}
