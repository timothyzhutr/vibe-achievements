import Foundation

public struct ClaudeCodeSourceAdapter: ConversationSourceAdapter {
    public let sourceTool: SourceTool = .claudeCode
    public let displayName = "Claude Code"

    private let projectsRoot: URL
    private let detectorVersion: String

    public init(projectsRoot: URL, detectorVersion: String) {
        self.projectsRoot = projectsRoot
        self.detectorVersion = detectorVersion
    }

    public func discover() throws -> SourceInventory {
        SourceInventory(
            records: records(in: SourceDiscovery.jsonlFiles(in: projectsRoot)),
            warnings: [],
            detectedRoots: [projectsRoot]
        )
    }

    public func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard record.sourceTool == sourceTool, case let .file(url) = record.locator else {
            throw ConversationSourceAdapterError.invalidRecord
        }
        return try ClaudeCodeParser.parse(fileURL: url)
    }

    private func records(in files: [URL]) -> [ConversationSourceRecord] {
        files.map { url in
            ConversationSourceRecord(
                sourceTool: sourceTool,
                stableID: url.deletingPathExtension().lastPathComponent,
                displayPath: url.path,
                locator: .file(url),
                fingerprint: SourceFileFingerprint.make(for: url, detectorVersion: detectorVersion)
            )
        }
    }
}
