import Foundation

public struct CodexSourceAdapter: ConversationSourceAdapter {
    public let sourceTool: SourceTool = .codex
    public let displayName = "Codex"

    private let sessionsRoot: URL?
    private let archivedSessionsRoot: URL?
    private let detectorVersion: String

    public init(sessionsRoot: URL?, archivedSessionsRoot: URL?, detectorVersion: String) {
        self.sessionsRoot = sessionsRoot
        self.archivedSessionsRoot = archivedSessionsRoot
        self.detectorVersion = detectorVersion
    }

    public func discover() throws -> SourceInventory {
        let roots = [sessionsRoot, archivedSessionsRoot].compactMap { $0 }
        let files = roots.flatMap(SourceDiscovery.jsonlFiles(in:)).sorted { $0.path < $1.path }
        var seen = Set<String>()
        var records: [ConversationSourceRecord] = []
        var warnings: [SourceWarning] = []

        for url in files {
            let stableID = url.deletingPathExtension().lastPathComponent
            guard seen.insert(stableID).inserted else {
                warnings.append(SourceWarning(
                    sourceTool: sourceTool,
                    recordID: stableID,
                    code: .duplicateRecord,
                    message: "Ignored duplicate Codex record at \(url.path)"
                ))
                continue
            }
            records.append(ConversationSourceRecord(
                sourceTool: sourceTool,
                stableID: stableID,
                displayPath: url.path,
                locator: .file(url),
                fingerprint: SourceFileFingerprint.make(for: url, detectorVersion: detectorVersion)
            ))
        }

        return SourceInventory(records: records, warnings: warnings, detectedRoots: roots)
    }

    public func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard record.sourceTool == sourceTool, case let .file(url) = record.locator else {
            throw ConversationSourceAdapterError.invalidRecord
        }
        return try CodexParser.parse(fileURL: url)
    }
}
