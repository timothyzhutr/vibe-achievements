import Foundation

public struct CursorTranscriptParser: Sendable {
    public init() {}

    public func parse(
        fileURL: URL,
        stableID: String,
        projectPath: String?
    ) throws -> ParsedTranscript {
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        var bubbles: [[String: Any]] = []
        for (lineIndex, line) in text.split(separator: "\n").enumerated() {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["type"] as? String != "turn_ended",
                  let role = object["role"] as? String,
                  role == "user" || role == "assistant" || role == "model"
            else { continue }
            let message = object["message"] as? [String: Any]
            let content = message?["content"] ?? object["content"] ?? object["text"]
            let textValue = TextContent.extract(from: content)
            guard !textValue.isEmpty else { continue }
            var bubble: [String: Any] = [
                "type": role,
                "text": textValue
            ]
            if let timestamp = object["timestamp"] ?? message?["timestamp"] {
                bubble["createdAt"] = timestamp
            }
            if let sourceID = object["bubbleId"] as? String ?? object["id"] as? String {
                bubble["bubbleId"] = sourceID
            } else {
                bubble["messageID"] = "\(stableID):\(lineIndex)"
            }
            bubbles.append(bubble)
        }

        return CursorConversationNormalizer.parse(
            composer: [:],
            bubbles: bubbles,
            stableID: stableID,
            sourcePath: fileURL.path,
            sourceThreadID: stableID,
            fallbackProjectPath: projectPath,
            rawType: "cursor.transcript"
        )
    }
}
