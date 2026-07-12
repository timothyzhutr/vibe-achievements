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

do {
    let contracts = try AchievementContractLoader.load(jsonlURL: contractsURL)
    let store = try SQLiteStore(path: storePath)
    let adapters = Dictionary(grouping: transcriptPaths, by: CLIFileAdapter.sourceTool(for:))
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map { CLIFileAdapter(sourceTool: $0.key, files: $0.value) }
    let result = try Indexer.index(
        adapters: adapters,
        contracts: contracts,
        store: store,
        scanID: UUID().uuidString
    )
    for unlock in result.unlocks {
        print("Unlocked: \(unlock.name) - \(unlock.triggerSummary)")
    }
    for warning in result.warnings {
        fputs("Warning: skipped \(warning.path): \(warning.message)\n", stderr)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

private struct CLIFileAdapter: ConversationSourceAdapter {
    let sourceTool: SourceTool
    let files: [URL]

    var displayName: String { sourceTool == .codex ? "Codex" : "Claude Code" }

    static func sourceTool(for url: URL) -> SourceTool {
        url.path.contains("/.codex/") || url.lastPathComponent.hasPrefix("rollout-") ? .codex : .claudeCode
    }

    func discover() throws -> SourceInventory {
        SourceInventory(
            records: files.map { url in
                ConversationSourceRecord(
                    sourceTool: sourceTool,
                    stableID: url.deletingPathExtension().lastPathComponent,
                    displayPath: url.path,
                    locator: .file(url),
                    fingerprint: SourceFileFingerprint.make(for: url, detectorVersion: "cli-v1")
                )
            },
            warnings: [],
            detectedRoots: [],
            isComplete: false
        )
    }

    func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard case let .file(url) = record.locator else {
            throw ConversationSourceAdapterError.invalidRecord
        }
        switch sourceTool {
        case .claudeCode:
            return try ClaudeCodeParser.parse(fileURL: url)
        case .codex:
            return try CodexParser.parse(fileURL: url)
        case .cursor:
            throw ConversationSourceAdapterError.unsupportedRecord
        case .openCode, .antigravity:
            throw ConversationSourceAdapterError.unsupportedRecord
        }
    }
}
