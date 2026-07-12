import Foundation

enum CursorConversationNormalizer {
    static func parse(
        composer: [String: Any],
        bubbles: [[String: Any]],
        stableID: String,
        sourcePath: String,
        sourceThreadID: String,
        fallbackProjectPath: String?,
        rawType: String = "cursor.bubble"
    ) -> ParsedTranscript {
        let messages = bubbles.enumerated().compactMap { index, bubble -> NormalizedMessage? in
            guard let role = role(from: bubble["type"]) else { return nil }
            let text = firstText(from: [bubble["text"], bubble["rawText"], bubble["richText"]])
            guard !text.isEmpty else { return nil }
            let bubbleID = bubble["bubbleId"] as? String
            let fallbackID = bubble["messageID"] as? String
            return NormalizedMessage(
                id: bubbleID ?? fallbackID ?? "\(stableID):\(index)",
                threadID: stableID,
                sourceTool: .cursor,
                sourceMessageID: bubbleID,
                role: role,
                timestamp: date(from: bubble["createdAt"]),
                text: text,
                rawType: rawType
            )
        }

        let createdAt = date(from: composer["createdAt"])
        let updatedAt = [
            createdAt,
            date(from: composer["lastUpdatedAt"]),
            messages.compactMap(\.timestamp).max()
        ].compactMap { $0 }.max()
        let resolvedProjectPath = projectPath(from: composer) ?? fallbackProjectPath
        let thread = NormalizedThread(
            id: stableID,
            sourceTool: .cursor,
            sourceThreadID: sourceThreadID,
            sourcePath: sourcePath,
            projectPath: resolvedProjectPath,
            projectKey: projectKey(for: resolvedProjectPath),
            title: composer["name"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messages.count,
            userTurnCount: messages.filter { $0.role == .user }.count,
            assistantTurnCount: messages.filter { $0.role == .assistant }.count,
            estimatedTokens: messages.reduce(0) { $0 + $1.estimatedTokens },
            rawTokenCount: nil
        )
        return ParsedTranscript(thread: thread, messages: messages)
    }

    static func role(from value: Any?) -> MessageRole? {
        if let number = value as? NSNumber {
            switch number.intValue {
            case 1: return .user
            case 2: return .assistant
            default: return nil
            }
        }
        switch value as? String {
        case "user", "human": return .user
        case "assistant", "model": return .assistant
        default: return nil
        }
    }

    static func firstText(from values: [Any?]) -> String {
        for value in values {
            let text = TextContent.extract(from: value)
            if !text.isEmpty { return text }
        }
        return ""
    }

    static func date(from value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let timestamp = number.doubleValue
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp)
        }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    static func projectPath(from composer: [String: Any]) -> String? {
        let candidates: [Any?] = [
            composer["workspaceIdentifier"],
            composer["attachedFoldersNew"],
            (composer["context"] as? [String: Any])?["folderSelections"]
        ]
        return candidates.compactMap(firstPath).first
    }

    private static func firstPath(_ value: Any?) -> String? {
        if let string = value as? String {
            if string.hasPrefix("/") { return string }
            if let url = URL(string: string), url.isFileURL {
                return url.standardizedFileURL.path
            }
        }
        if let dictionary = value as? [String: Any] {
            for key in ["uri", "path", "folder", "workspaceFolder"] {
                if let path = firstPath(dictionary[key]) { return path }
            }
        }
        if let array = value as? [Any] {
            for item in array {
                if let path = firstPath(item) { return path }
            }
        }
        return nil
    }
}
