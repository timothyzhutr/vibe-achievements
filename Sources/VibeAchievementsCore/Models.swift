import Foundation

public enum SourceTool: String, Codable, CaseIterable, Hashable, Sendable {
    case claudeCode = "claude_code"
    case codex = "codex"
    case cursor = "cursor"
    case openCode = "open_code"
    case antigravity = "antigravity"
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case developer
    case system
    case tool
    case unknown
}

public struct NormalizedThread: Codable, Equatable, Sendable {
    public var id: String
    public var sourceTool: SourceTool
    public var sourceThreadID: String
    public var sourcePath: String
    public var projectPath: String?
    public var projectKey: String
    public var title: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var messageCount: Int
    public var userTurnCount: Int
    public var assistantTurnCount: Int
    public var estimatedTokens: Int
    public var rawTokenCount: Int?

    public init(id: String, sourceTool: SourceTool, sourceThreadID: String, sourcePath: String, projectPath: String?, projectKey: String, title: String?, createdAt: Date?, updatedAt: Date?, messageCount: Int, userTurnCount: Int, assistantTurnCount: Int, estimatedTokens: Int, rawTokenCount: Int?) {
        self.id = id
        self.sourceTool = sourceTool
        self.sourceThreadID = sourceThreadID
        self.sourcePath = sourcePath
        self.projectPath = projectPath
        self.projectKey = projectKey
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.userTurnCount = userTurnCount
        self.assistantTurnCount = assistantTurnCount
        self.estimatedTokens = estimatedTokens
        self.rawTokenCount = rawTokenCount
    }
}

public struct NormalizedMessage: Codable, Equatable, Sendable {
    public var id: String
    public var threadID: String
    public var sourceTool: SourceTool
    public var sourceMessageID: String?
    public var role: MessageRole
    public var timestamp: Date?
    public var text: String
    public var charCount: Int
    public var estimatedTokens: Int
    public var rawType: String

    public init(id: String, threadID: String, sourceTool: SourceTool, sourceMessageID: String?, role: MessageRole, timestamp: Date?, text: String, rawType: String) {
        self.id = id
        self.threadID = threadID
        self.sourceTool = sourceTool
        self.sourceMessageID = sourceMessageID
        self.role = role
        self.timestamp = timestamp
        self.text = text
        self.charCount = text.count
        self.estimatedTokens = max(1, text.count / 4)
        self.rawType = rawType
    }
}

public struct ParsedTranscript: Equatable, Sendable {
    public var thread: NormalizedThread
    public var messages: [NormalizedMessage]

    public init(thread: NormalizedThread, messages: [NormalizedMessage]) {
        self.thread = thread
        self.messages = messages
    }
}

public func projectKey(for path: String?) -> String {
    guard let path, !path.isEmpty else { return "unknown-project" }
    return path.replacingOccurrences(of: " ", with: "-").lowercased()
}
