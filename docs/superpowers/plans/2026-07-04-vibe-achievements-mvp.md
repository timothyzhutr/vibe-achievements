# Vibe Achievements MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working local macOS MVP loop: detect Claude Code/Codex history, parse transcripts, store normalized data, extract lightweight events, unlock achievements, and display unlocks in a minimal app shell.

**Architecture:** Implement the core as a testable Swift package, then wrap it in a small SwiftUI macOS menu bar app. The core owns source discovery, parsing, storage, event extraction, and achievement evaluation; the app owns menu bar controls, notifications, and the achievement shelf.

**Tech Stack:** Swift 6-compatible package, XCTest, Foundation, SQLite3, SwiftUI, UserNotifications, AppKit status item.

---

## File Structure

Create a Swift package first so parser/rule work is fast and testable:

```text
Package.swift
Sources/VibeAchievementsCore/
  Models.swift
  SourceDiscovery.swift
  TextContent.swift
  ClaudeCodeParser.swift
  CodexParser.swift
  AchievementContract.swift
  EventExtractor.swift
  AchievementEngine.swift
  SQLiteStore.swift
  Indexer.swift
Sources/vibe-achievements-cli/
  main.swift
Sources/vibe-achievements-app/
  main.swift
  AppDelegate.swift
  AchievementShelfView.swift
  SettingsView.swift
  NotificationController.swift
Tests/VibeAchievementsCoreTests/
  Fixtures/
    claude-sample.jsonl
    codex-sample.jsonl
    achievements-sample.jsonl
  ClaudeCodeParserTests.swift
  CodexParserTests.swift
  EventExtractorTests.swift
  AchievementEngineTests.swift
  SQLiteStoreTests.swift
```

The first app shell is a SwiftPM executable that starts an AppKit/SwiftUI macOS status bar app. A polished `.app` bundle or Xcode project can come after the core loop works.

## Task 1: Initialize Swift Package Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/VibeAchievementsCore/Models.swift`
- Create: `Sources/vibe-achievements-cli/main.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/.keep`
- Create: `Tests/VibeAchievementsCoreTests/ModelSmokeTests.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vibe-achievements",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibeAchievementsCore", targets: ["VibeAchievementsCore"]),
        .executable(name: "vibe-achievements-cli", targets: ["VibeAchievementsCLI"])
    ],
    targets: [
        .target(
            name: "VibeAchievementsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "VibeAchievementsCLI", dependencies: ["VibeAchievementsCore"], path: "Sources/vibe-achievements-cli"),
        .testTarget(
            name: "VibeAchievementsCoreTests",
            dependencies: ["VibeAchievementsCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: Create core models**

```swift
import Foundation

public enum SourceTool: String, Codable, Sendable {
    case claudeCode = "claude_code"
    case codex = "codex"
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
```

- [ ] **Step 3: Create fixture directory marker**

```text

```

- [ ] **Step 4: Create CLI smoke entry**

```swift
import Foundation
import VibeAchievementsCore

print("vibe-achievements core ready")
```

- [ ] **Step 5: Create smoke test**

```swift
import XCTest
@testable import VibeAchievementsCore

final class ModelSmokeTests: XCTestCase {
    func testProjectKeyNormalizesPath() {
        XCTAssertEqual(
            projectKey(for: "/Users/Timothy/Documents/Cross Platform LLM App"),
            "/users/timothy/documents/cross-platform-llm-app"
        )
    }
}
```

- [ ] **Step 6: Run test**

Run: `swift test`

Expected: test suite passes.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "Add Swift package skeleton"
```

## Task 2: Parse Claude Code JSONL

**Files:**
- Create: `Sources/VibeAchievementsCore/TextContent.swift`
- Create: `Sources/VibeAchievementsCore/ClaudeCodeParser.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/claude-sample.jsonl`
- Create: `Tests/VibeAchievementsCoreTests/ClaudeCodeParserTests.swift`

- [ ] **Step 1: Add fixture**

```jsonl
{"type":"user","timestamp":"2026-07-04T01:00:00.000Z","sessionId":"claude-session-1","uuid":"u1","cwd":"/tmp/vibe-app","gitBranch":"main","message":{"role":"user","content":"Can you build a quick MVP app?"}}
{"type":"assistant","timestamp":"2026-07-04T01:00:10.000Z","sessionId":"claude-session-1","uuid":"a1","cwd":"/tmp/vibe-app","gitBranch":"main","message":{"role":"assistant","content":[{"type":"text","text":"Yes. I will scaffold the app."}],"usage":{"input_tokens":100,"output_tokens":40}}}
{"type":"user","timestamp":"2026-07-04T01:01:00.000Z","sessionId":"claude-session-1","uuid":"u2","cwd":"/tmp/vibe-app","gitBranch":"main","message":{"role":"user","content":[{"type":"text","text":"Actually, wait. Make it a menu bar app."}]}}
```

- [ ] **Step 2: Implement text extraction helpers**

```swift
import Foundation

enum TextContent {
    static func extract(from value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let array = value as? [Any] {
            return array.compactMap { item in
                guard let object = item as? [String: Any] else { return nil }
                return object["text"] as? String
            }.joined(separator: "\n")
        }
        return ""
    }
}
```

- [ ] **Step 3: Implement Claude parser**

```swift
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
```

- [ ] **Step 4: Add parser tests**

```swift
import XCTest
@testable import VibeAchievementsCore

final class ClaudeCodeParserTests: XCTestCase {
    func testParsesClaudeCodeTranscript() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let parsed = try ClaudeCodeParser.parse(fileURL: url)

        XCTAssertEqual(parsed.thread.sourceTool, .claudeCode)
        XCTAssertEqual(parsed.thread.sourceThreadID, "claude-session-1")
        XCTAssertEqual(parsed.thread.projectPath, "/tmp/vibe-app")
        XCTAssertEqual(parsed.thread.messageCount, 3)
        XCTAssertEqual(parsed.thread.userTurnCount, 2)
        XCTAssertEqual(parsed.thread.assistantTurnCount, 1)
        XCTAssertEqual(parsed.thread.rawTokenCount, 140)
        XCTAssertTrue(parsed.messages.map(\.text).joined(separator: "\n").contains("Actually, wait"))
    }
}
```

- [ ] **Step 5: Run test**

Run: `swift test --filter ClaudeCodeParserTests`

Expected: Claude parser tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeAchievementsCore Tests/VibeAchievementsCoreTests
git commit -m "Add Claude Code transcript parser"
```

## Task 3: Parse Codex JSONL

**Files:**
- Create: `Sources/VibeAchievementsCore/CodexParser.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/codex-sample.jsonl`
- Create: `Tests/VibeAchievementsCoreTests/CodexParserTests.swift`

- [ ] **Step 1: Add fixture**

```jsonl
{"type":"session_meta","timestamp":"2026-07-04T02:00:00.000Z","payload":{"id":"codex-session-1","cwd":"/tmp/vibe-app","source":"vscode","model_provider":"openai"}}
{"type":"response_item","timestamp":"2026-07-04T02:00:01.000Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"rm -rf node_modules and reinstall?"}]}}
{"type":"response_item","timestamp":"2026-07-04T02:00:10.000Z","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"That can work if you rebuild afterwards."}]}}
{"type":"event_msg","timestamp":"2026-07-04T02:00:11.000Z","payload":{"type":"token_count","info":{"model_context_window":258400,"total_token_usage":{"input_tokens":120,"output_tokens":30}}}}
{"type":"response_item","timestamp":"2026-07-04T02:01:00.000Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"It works now after reinstall."}]}}
```

- [ ] **Step 2: Implement Codex parser**

```swift
import Foundation

public enum CodexParser {
    public static func parse(fileURL: URL) throws -> ParsedTranscript {
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        var messages: [NormalizedMessage] = []
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
                rawTokens += tokenCount(from: payload["info"])
                continue
            }

            guard type == "response_item",
                  payload["type"] as? String == "message",
                  payload["encrypted_content"] == nil
            else { continue }

            let role = parseRole(payload["role"] as? String ?? "unknown")
            let content = TextContent.extract(from: payload["content"])
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
}
```

- [ ] **Step 3: Add parser tests**

```swift
import XCTest
@testable import VibeAchievementsCore

final class CodexParserTests: XCTestCase {
    func testParsesCodexTranscript() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let parsed = try CodexParser.parse(fileURL: url)

        XCTAssertEqual(parsed.thread.sourceTool, .codex)
        XCTAssertEqual(parsed.thread.sourceThreadID, "codex-session-1")
        XCTAssertEqual(parsed.thread.projectPath, "/tmp/vibe-app")
        XCTAssertEqual(parsed.thread.messageCount, 3)
        XCTAssertEqual(parsed.thread.userTurnCount, 2)
        XCTAssertEqual(parsed.thread.assistantTurnCount, 1)
        XCTAssertEqual(parsed.thread.rawTokenCount, 150)
        XCTAssertTrue(parsed.messages.map(\.text).joined(separator: "\n").contains("rm -rf"))
    }
}
```

- [ ] **Step 4: Run test**

Run: `swift test --filter CodexParserTests`

Expected: Codex parser tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeAchievementsCore/CodexParser.swift Tests/VibeAchievementsCoreTests
git commit -m "Add Codex transcript parser"
```

## Task 4: Load Achievement Contracts

**Files:**
- Create: `Sources/VibeAchievementsCore/AchievementContract.swift`
- Create: `Tests/VibeAchievementsCoreTests/Fixtures/achievements-sample.jsonl`
- Create: `Tests/VibeAchievementsCoreTests/AchievementContractTests.swift`

- [ ] **Step 1: Add fixture**

```jsonl
{"id":"actually_wait","number":12,"name":"Actually, Wait","category":"prompting_and_context","definition":"The user changes direction mid-thread.","detection_class":"keyword","signals":["correction_terms: actually, wait, never mind"],"window":"same_thread_after_first_user_turn","exclusions":["assistant text only"],"cooldown":"once_per_thread","confidence":"high","status":"keep","difficulty":"starter","expected_frequency":"weekly","active":true}
{"id":"rm_rf","number":38,"name":"rm -rf","category":"vibe_coding_memes","definition":"The conversation includes destructive cleanup followed by recovery.","detection_class":"sequence","signals":["destructive_cleanup_seen","recovery_terms_seen_later"],"window":"same_thread_or_project_24h","exclusions":["warning only"],"cooldown":"once_per_project_per_7_days","confidence":"high","status":"keep","difficulty":"uncommon","expected_frequency":"monthly","active":true}
```

- [ ] **Step 2: Implement contract loader**

```swift
import Foundation

public struct AchievementContract: Codable, Equatable, Sendable {
    public var id: String
    public var number: Int
    public var name: String
    public var category: String
    public var definition: String
    public var detectionClass: String
    public var signals: [String]
    public var window: String
    public var exclusions: [String]
    public var cooldown: String
    public var confidence: String
    public var status: String
    public var difficulty: String
    public var expectedFrequency: String
    public var active: Bool

    enum CodingKeys: String, CodingKey {
        case id, number, name, category, definition, signals, window, exclusions, cooldown, confidence, status, difficulty, active
        case detectionClass = "detection_class"
        case expectedFrequency = "expected_frequency"
    }
}

public enum AchievementContractLoader {
    public static func load(jsonlURL: URL) throws -> [AchievementContract] {
        let data = try Data(contentsOf: jsonlURL)
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").map { line in
            try decoder.decode(AchievementContract.self, from: Data(line.utf8))
        }
    }
}
```

- [ ] **Step 3: Add tests**

```swift
import XCTest
@testable import VibeAchievementsCore

final class AchievementContractTests: XCTestCase {
    func testLoadsJSONLContracts() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: url)

        XCTAssertEqual(contracts.count, 2)
        XCTAssertEqual(contracts.first?.id, "actually_wait")
        XCTAssertEqual(contracts.last?.name, "rm -rf")
        XCTAssertTrue(contracts.allSatisfy(\.active))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AchievementContractTests`

Expected: contract tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeAchievementsCore/AchievementContract.swift Tests/VibeAchievementsCoreTests
git commit -m "Add achievement contract loader"
```

## Task 5: Extract Lightweight Events

**Files:**
- Create: `Sources/VibeAchievementsCore/EventExtractor.swift`
- Create: `Tests/VibeAchievementsCoreTests/EventExtractorTests.swift`

- [ ] **Step 1: Implement event model and extractor**

```swift
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
```

- [ ] **Step 2: Add tests**

```swift
import XCTest
@testable import VibeAchievementsCore

final class EventExtractorTests: XCTestCase {
    func testExtractsCorrectionAndCleanupEvents() throws {
        let claudeURL = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let codexURL = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))

        let claudeEvents = EventExtractor.extract(from: try ClaudeCodeParser.parse(fileURL: claudeURL))
        let codexEvents = EventExtractor.extract(from: try CodexParser.parse(fileURL: codexURL))

        XCTAssertTrue(claudeEvents.contains { $0.type == .correctionLanguageSeen })
        XCTAssertTrue(codexEvents.contains { $0.type == .destructiveCleanupSeen })
        XCTAssertTrue(codexEvents.contains { $0.type == .recoverySeen || $0.type == .successSeen })
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter EventExtractorTests`

Expected: event extraction tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/VibeAchievementsCore/EventExtractor.swift Tests/VibeAchievementsCoreTests/EventExtractorTests.swift
git commit -m "Add lightweight event extraction"
```

## Task 6: Evaluate First Achievement Rules

**Files:**
- Create: `Sources/VibeAchievementsCore/AchievementEngine.swift`
- Create: `Tests/VibeAchievementsCoreTests/AchievementEngineTests.swift`

- [ ] **Step 1: Implement unlock model and engine**

```swift
import Foundation

public struct AchievementUnlock: Codable, Equatable, Sendable {
    public var achievementID: String
    public var name: String
    public var projectKey: String?
    public var threadID: String?
    public var unlockedAt: Date
    public var triggerSummary: String
}

public enum AchievementEngine {
    public static func evaluate(contracts: [AchievementContract], parsed: ParsedTranscript, events: [ExtractedEvent], existingUnlockIDs: Set<String> = []) -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        let activeContracts = contracts.filter { $0.active && $0.status == "keep" }

        unlockFirstAchievementIfNeeded(activeContracts: activeContracts, existingUnlockIDs: existingUnlockIDs, unlocks: &unlocks)
        unlock("actually_wait", if: events.contains { $0.type == .correctionLanguageSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Changed direction mid-thread.")
        unlock("one_more_prompt", if: events.contains { $0.type == .oneMorePromptSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Continued a thread for 10 or more user turns.")
        unlock("rm_rf", if: hasSequence([.destructiveCleanupSeen, .recoverySeen], events) || hasSequence([.destructiveCleanupSeen, .successSeen], events), activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Destructive cleanup was followed by recovery.")
        unlock("it_works_therefore_it_is", if: events.contains { $0.type == .successSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Something works now.")

        return unlocks.filter { !existingUnlockIDs.contains($0.achievementID) }
    }

    private static func unlockFirstAchievementIfNeeded(activeContracts: [AchievementContract], existingUnlockIDs: Set<String>, unlocks: inout [AchievementUnlock]) {
        guard existingUnlockIDs.isEmpty,
              let contract = activeContracts.first(where: { $0.id == "achievement_unlocked_unlocking_achievement" })
        else { return }
        unlocks.append(AchievementUnlock(achievementID: contract.id, name: contract.name, projectKey: nil, threadID: nil, unlockedAt: Date(), triggerSummary: "Unlocked the first achievement."))
    }

    private static func unlock(_ id: String, if condition: Bool, activeContracts: [AchievementContract], parsed: ParsedTranscript, unlocks: inout [AchievementUnlock], summary: String) {
        guard condition, let contract = activeContracts.first(where: { $0.id == id }) else { return }
        unlocks.append(AchievementUnlock(achievementID: contract.id, name: contract.name, projectKey: parsed.thread.projectKey, threadID: parsed.thread.id, unlockedAt: Date(), triggerSummary: summary))
    }

    private static func hasSequence(_ sequence: [EventType], _ events: [ExtractedEvent]) -> Bool {
        var index = 0
        for event in events.sorted(by: { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }) {
            if event.type == sequence[index] {
                index += 1
                if index == sequence.count { return true }
            }
        }
        return false
    }
}
```

- [ ] **Step 2: Add tests**

```swift
import XCTest
@testable import VibeAchievementsCore

final class AchievementEngineTests: XCTestCase {
    func testUnlocksActuallyWaitAndRmRf() throws {
        let contractsURL = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)

        let claudeURL = try XCTUnwrap(Bundle.module.url(forResource: "claude-sample", withExtension: "jsonl"))
        let claude = try ClaudeCodeParser.parse(fileURL: claudeURL)
        let claudeUnlocks = AchievementEngine.evaluate(contracts: contracts, parsed: claude, events: EventExtractor.extract(from: claude), existingUnlockIDs: ["achievement_unlocked_unlocking_achievement"])

        let codexURL = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let codex = try CodexParser.parse(fileURL: codexURL)
        let codexUnlocks = AchievementEngine.evaluate(contracts: contracts, parsed: codex, events: EventExtractor.extract(from: codex), existingUnlockIDs: ["achievement_unlocked_unlocking_achievement"])

        XCTAssertTrue(claudeUnlocks.contains { $0.achievementID == "actually_wait" })
        XCTAssertTrue(codexUnlocks.contains { $0.achievementID == "rm_rf" })
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter AchievementEngineTests`

Expected: achievement engine tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/VibeAchievementsCore/AchievementEngine.swift Tests/VibeAchievementsCoreTests/AchievementEngineTests.swift
git commit -m "Add initial achievement rule engine"
```

## Task 7: Add Local SQLite Store

**Files:**
- Create: `Sources/VibeAchievementsCore/SQLiteStore.swift`
- Create: `Tests/VibeAchievementsCoreTests/SQLiteStoreTests.swift`

- [ ] **Step 1: Implement minimal SQLite store**

```swift
import Foundation
import SQLite3

public final class SQLiteStore {
    private var db: OpaquePointer?

    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StoreError.openFailed
        }
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func upsert(thread: NormalizedThread) throws {
        let sql = """
        INSERT OR REPLACE INTO threads
        (id, source_tool, source_thread_id, source_path, project_path, project_key, title, created_at, updated_at, message_count, user_turn_count, assistant_turn_count, estimated_tokens, raw_token_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try execute(sql, [
            thread.id, thread.sourceTool.rawValue, thread.sourceThreadID, thread.sourcePath, thread.projectPath ?? "", thread.projectKey, thread.title ?? "",
            iso(thread.createdAt), iso(thread.updatedAt), thread.messageCount, thread.userTurnCount, thread.assistantTurnCount, thread.estimatedTokens, thread.rawTokenCount ?? 0
        ])
    }

    public func insert(unlock: AchievementUnlock) throws {
        let sql = """
        INSERT OR IGNORE INTO achievement_unlocks
        (achievement_id, name, project_key, thread_id, unlocked_at, trigger_summary)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        try execute(sql, [unlock.achievementID, unlock.name, unlock.projectKey ?? "", unlock.threadID ?? "", iso(unlock.unlockedAt), unlock.triggerSummary])
    }

    public func unlockCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM achievement_unlocks;")
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS threads (
            id TEXT PRIMARY KEY,
            source_tool TEXT NOT NULL,
            source_thread_id TEXT NOT NULL,
            source_path TEXT NOT NULL,
            project_path TEXT NOT NULL,
            project_key TEXT NOT NULL,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            message_count INTEGER NOT NULL,
            user_turn_count INTEGER NOT NULL,
            assistant_turn_count INTEGER NOT NULL,
            estimated_tokens INTEGER NOT NULL,
            raw_token_count INTEGER NOT NULL
        );
        """, [])
        try execute("""
        CREATE TABLE IF NOT EXISTS achievement_unlocks (
            achievement_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            project_key TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            unlocked_at TEXT NOT NULL,
            trigger_summary TEXT NOT NULL
        );
        """, [])
    }

    private func execute(_ sql: String, _ values: [Any]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            if let value = value as? String {
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            } else if let value = value as? Int {
                sqlite3_bind_int(statement, position, Int32(value))
            } else {
                sqlite3_bind_null(statement, position)
            }
        }

        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.stepFailed }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.prepareFailed }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func iso(_ date: Date?) -> String {
        guard let date else { return "" }
        return ISO8601DateFormatter().string(from: date)
    }

    public enum StoreError: Error {
        case openFailed
        case prepareFailed
        case stepFailed
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
```

- [ ] **Step 2: Add store tests**

```swift
import XCTest
@testable import VibeAchievementsCore

final class SQLiteStoreTests: XCTestCase {
    func testStoresThreadAndUnlock() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
        let store = try SQLiteStore(path: path)
        let url = try XCTUnwrap(Bundle.module.url(forResource: "codex-sample", withExtension: "jsonl"))
        let parsed = try CodexParser.parse(fileURL: url)

        try store.upsert(thread: parsed.thread)
        try store.insert(unlock: AchievementUnlock(
            achievementID: "rm_rf",
            name: "rm -rf",
            projectKey: parsed.thread.projectKey,
            threadID: parsed.thread.id,
            unlockedAt: Date(),
            triggerSummary: "Destructive cleanup was followed by recovery."
        ))

        XCTAssertEqual(try store.unlockCount(), 1)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter SQLiteStoreTests`

Expected: SQLite store tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/VibeAchievementsCore/SQLiteStore.swift Tests/VibeAchievementsCoreTests/SQLiteStoreTests.swift
git commit -m "Add local SQLite store"
```

## Task 8: Add Source Discovery And CLI Indexer

**Files:**
- Create: `Sources/VibeAchievementsCore/SourceDiscovery.swift`
- Create: `Sources/VibeAchievementsCore/Indexer.swift`
- Modify: `Sources/vibe-achievements-cli/main.swift`

- [ ] **Step 1: Implement source discovery**

```swift
import Foundation

public struct SourceLocations: Equatable, Sendable {
    public var claudeProjects: URL?
    public var codexSessions: URL?
    public var codexArchivedSessions: URL?

    public init(claudeProjects: URL?, codexSessions: URL?, codexArchivedSessions: URL?) {
        self.claudeProjects = claudeProjects
        self.codexSessions = codexSessions
        self.codexArchivedSessions = codexArchivedSessions
    }
}

public enum SourceDiscovery {
    public static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SourceLocations {
        let claude = home.appendingPathComponent(".claude/projects")
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:)) ?? home.appendingPathComponent(".codex")
        let sessions = codexHome.appendingPathComponent("sessions")
        let archived = codexHome.appendingPathComponent("archived_sessions")
        return SourceLocations(
            claudeProjects: exists(claude) ? claude : nil,
            codexSessions: exists(sessions) ? sessions : nil,
            codexArchivedSessions: exists(archived) ? archived : nil
        )
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
```

- [ ] **Step 2: Implement indexer**

```swift
import Foundation

public enum Indexer {
    public static func index(paths: [URL], contractsURL: URL, storePath: String) throws -> [AchievementUnlock] {
        let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)
        let store = try SQLiteStore(path: storePath)
        var allUnlocks: [AchievementUnlock] = []

        for path in paths where path.pathExtension == "jsonl" {
            let parsed: ParsedTranscript
            if path.path.contains("/.claude/projects/") {
                parsed = try ClaudeCodeParser.parse(fileURL: path)
            } else {
                parsed = try CodexParser.parse(fileURL: path)
            }

            try store.upsert(thread: parsed.thread)
            let events = EventExtractor.extract(from: parsed)
            let unlocks = AchievementEngine.evaluate(contracts: contracts, parsed: parsed, events: events)
            for unlock in unlocks {
                try store.insert(unlock: unlock)
            }
            allUnlocks.append(contentsOf: unlocks)
        }

        return allUnlocks
    }
}
```

- [ ] **Step 3: Update CLI**

```swift
import Foundation
import VibeAchievementsCore

let args = CommandLine.arguments.dropFirst()
guard args.count >= 2 else {
    print("Usage: vibe-achievements-cli <contracts.jsonl> <store.sqlite> [transcript.jsonl ...]")
    exit(2)
}

let contractsURL = URL(fileURLWithPath: String(args[args.startIndex]))
let storePath = String(args[args.index(after: args.startIndex)])
let transcriptPaths = args.dropFirst(2).map { URL(fileURLWithPath: String($0)) }

let unlocks = try Indexer.index(paths: transcriptPaths, contractsURL: contractsURL, storePath: storePath)
for unlock in unlocks {
    print("Unlocked: \(unlock.name) - \(unlock.triggerSummary)")
}
```

- [ ] **Step 4: Run CLI against fixtures**

Run:

```bash
swift run vibe-achievements-cli \
  Tests/VibeAchievementsCoreTests/Fixtures/achievements-sample.jsonl \
  /tmp/vibe-achievements-test.sqlite \
  Tests/VibeAchievementsCoreTests/Fixtures/claude-sample.jsonl \
  Tests/VibeAchievementsCoreTests/Fixtures/codex-sample.jsonl
```

Expected output includes:

```text
Unlocked: Actually, Wait - Changed direction mid-thread.
Unlocked: rm -rf - Destructive cleanup was followed by recovery.
```

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeAchievementsCore/SourceDiscovery.swift Sources/VibeAchievementsCore/Indexer.swift Sources/vibe-achievements-cli/main.swift
git commit -m "Add source discovery and CLI indexer"
```

## Task 9: Create Minimal macOS Menu Bar App Shell

**Files:**
- Modify: `Package.swift`
- Create: `Sources/vibe-achievements-app/main.swift`
- Create: `Sources/vibe-achievements-app/AppDelegate.swift`
- Create: `Sources/vibe-achievements-app/AchievementShelfView.swift`
- Create: `Sources/vibe-achievements-app/SettingsView.swift`
- Create: `Sources/vibe-achievements-app/NotificationController.swift`

- [ ] **Step 1: Add app executable target to `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vibe-achievements",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibeAchievementsCore", targets: ["VibeAchievementsCore"]),
        .executable(name: "vibe-achievements-cli", targets: ["VibeAchievementsCLI"]),
        .executable(name: "vibe-achievements-app", targets: ["VibeAchievementsApp"])
    ],
    targets: [
        .target(
            name: "VibeAchievementsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "VibeAchievementsCLI", dependencies: ["VibeAchievementsCore"], path: "Sources/vibe-achievements-cli"),
        .executableTarget(name: "VibeAchievementsApp", dependencies: ["VibeAchievementsCore"], path: "Sources/vibe-achievements-app"),
        .testTarget(
            name: "VibeAchievementsCoreTests",
            dependencies: ["VibeAchievementsCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: Create `main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 3: Create app delegate with status item**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var shelfWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "Vibe"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Achievements", action: #selector(openAchievements), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        NotificationController.requestAuthorization()
    }

    @objc private func openAchievements() {
        if shelfWindow == nil {
            shelfWindow = NSWindow(contentViewController: NSHostingController(rootView: AchievementShelfView()))
            shelfWindow?.title = "Vibe Achievements"
            shelfWindow?.setContentSize(NSSize(width: 560, height: 420))
        }
        NSApp.activate(ignoringOtherApps: true)
        shelfWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            settingsWindow?.title = "Settings"
            settingsWindow?.setContentSize(NSSize(width: 460, height: 220))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 4: Create initial achievement shelf**

```swift
import SwiftUI

struct AchievementShelfView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vibe Achievements")
                .font(.title2)
            Text("Local Claude Code and Codex achievements will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }
}
```

- [ ] **Step 5: Create initial settings view**

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Sources")
            Text("Claude Code and Codex source detection will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 460)
    }
}
```

- [ ] **Step 6: Create notification helper**

```swift
import Foundation
import UserNotifications

enum NotificationController {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(unlockName: String, summary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked"
        content.body = "\(unlockName): \(summary)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 7: Build app**

Run: `swift build --product vibe-achievements-app`

Expected: app executable builds.

- [ ] **Step 8: Launch app smoke test**

Run: `swift run vibe-achievements-app`

Expected: a `Vibe` menu bar item appears. Use the menu to open Achievements and Settings, then quit from the menu.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/vibe-achievements-app
git commit -m "Add minimal macOS menu bar app shell"
```

## Task 10: Connect App Shell To Core Smoke Flow

**Files:**
- Create: `Sources/vibe-achievements-app/AppState.swift`
- Modify: `Sources/vibe-achievements-app/AchievementShelfView.swift`
- Modify: `Sources/vibe-achievements-app/SettingsView.swift`
- Modify: `Sources/vibe-achievements-app/AppDelegate.swift`

- [ ] **Step 1: Add app state object**

```swift
import Foundation
import VibeAchievementsCore

final class AppState: ObservableObject {
    @Published var sourceSummary: String = "Not indexed yet"
    @Published var recentUnlocks: [AchievementUnlock] = []

    func refresh() {
        let locations = SourceDiscovery.discover()
        var parts: [String] = []
        if locations.claudeProjects != nil { parts.append("Claude Code") }
        if locations.codexSessions != nil { parts.append("Codex") }
        sourceSummary = parts.isEmpty ? "No sources detected" : "Detected: " + parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: Use state in shelf**

```swift
import SwiftUI

struct AchievementShelfView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vibe Achievements")
                .font(.title2)
            Text(state.sourceSummary)
                .foregroundStyle(.secondary)
            List(state.recentUnlocks, id: \.achievementID) { unlock in
                VStack(alignment: .leading) {
                    Text(unlock.name).font(.headline)
                    Text(unlock.triggerSummary).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { state.refresh() }
    }
}
```

- [ ] **Step 3: Use state in settings**

```swift
import SwiftUI

struct SettingsView: View {
    @StateObject private var state = AppState()

    var body: some View {
        Form {
            Text("Sources")
            Text(state.sourceSummary)
                .foregroundStyle(.secondary)
            Button("Refresh Sources") {
                state.refresh()
            }
        }
        .padding()
        .frame(width: 460)
        .onAppear { state.refresh() }
    }
}
```

- [ ] **Step 4: Build app**

Run: `swift build --product vibe-achievements-app`

Expected: app builds, shelf/settings show detected Claude Code/Codex sources.

- [ ] **Step 5: Commit**

```bash
git add Sources/vibe-achievements-app
git commit -m "Connect app shell to source discovery"
```

## Task 11: Final Verification

**Files:**
- No planned file changes.

- [ ] **Step 1: Run package tests**

Run: `swift test`

Expected: all package tests pass.

- [ ] **Step 2: Validate achievement contract JSONL**

Run: `jq -c . docs/achievement-trigger-contracts-v1.jsonl >/dev/null`

Expected: exit code 0.

- [ ] **Step 3: Run CLI fixture flow**

Run:

```bash
rm -f /tmp/vibe-achievements-test.sqlite
swift run vibe-achievements-cli \
  Tests/VibeAchievementsCoreTests/Fixtures/achievements-sample.jsonl \
  /tmp/vibe-achievements-test.sqlite \
  Tests/VibeAchievementsCoreTests/Fixtures/claude-sample.jsonl \
  Tests/VibeAchievementsCoreTests/Fixtures/codex-sample.jsonl
```

Expected: output includes `Actually, Wait` and `rm -rf`.

- [ ] **Step 4: Build macOS app**

Run: `swift build --product vibe-achievements-app`

Expected: build succeeds.
