import Foundation

internal struct AntigravityFileStamp: Equatable, Sendable {
    let size: Int64
    let modified: Date?

    init(size: Int64, modified: Date?) {
        self.size = size
        self.modified = modified
    }
}

internal enum AntigravityReadError: Error, Equatable, Sendable {
    case recordChangedDuringRead
}

internal enum AntigravityStableReader {
    static func data(at url: URL) throws -> Data {
        try read(
            at: url,
            readData: { try Data(contentsOf: $0, options: .mappedIfSafe) },
            stamp: stamp(at:)
        )
    }

    static func read(
        at url: URL,
        readData: @escaping @Sendable (URL) throws -> Data,
        stamp: @escaping @Sendable (URL) throws -> AntigravityFileStamp
    ) throws -> Data {
        for _ in 0..<2 {
            let before = try stamp(url)
            let data = try readData(url)
            let after = try stamp(url)
            if before == after {
                return data
            }
        }
        throw AntigravityReadError.recordChangedDuringRead
    }

    private static func stamp(at url: URL) throws -> AntigravityFileStamp {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return AntigravityFileStamp(
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate
        )
    }
}

public struct AntigravityRoots: Equatable, Sendable {
    public let ideBrain: URL
    public let cliBrain: URL

    public init(ideBrain: URL, cliBrain: URL) {
        self.ideBrain = ideBrain
        self.cliBrain = cliBrain
    }
}

public struct AntigravitySourceAdapter: ConversationSourceAdapter {
    public let sourceTool: SourceTool
    public let displayName = "Antigravity"

    private let roots: [Root]
    private let detectorVersion: String
    private let stableReader: @Sendable (URL) throws -> Data

    public static func defaultRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        homeOverride: URL? = nil
    ) -> AntigravityRoots {
        let base = homeOverride ?? home.appendingPathComponent(".gemini", isDirectory: true)
        return AntigravityRoots(
            ideBrain: base.appendingPathComponent("antigravity/brain", isDirectory: true),
            cliBrain: base.appendingPathComponent("antigravity-cli/brain", isDirectory: true)
        )
    }

    public init(roots: AntigravityRoots, detectorVersion: String) {
        self.init(
            ideBrainRoot: roots.ideBrain,
            cliBrainRoot: roots.cliBrain,
            detectorVersion: detectorVersion,
            sourceTool: .antigravity
        )
    }

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        ideBrainRoot: URL? = nil,
        cliBrainRoot: URL? = nil,
        detectorVersion: String = "antigravity-v1",
        sourceTool: SourceTool = .antigravity
    ) {
        self.init(
            ideBrainRoot: ideBrainRoot ?? home.appendingPathComponent(".gemini/antigravity/brain"),
            cliBrainRoot: cliBrainRoot ?? home.appendingPathComponent(".gemini/antigravity-cli/brain"),
            detectorVersion: detectorVersion,
            sourceTool: sourceTool,
            stableReader: AntigravityStableReader.data(at:)
        )
    }

    internal init(
        ideBrainRoot: URL,
        cliBrainRoot: URL,
        detectorVersion: String,
        sourceTool: SourceTool,
        stableReader: @escaping @Sendable (URL) throws -> Data
    ) {
        self.roots = [
            Root(surface: .ide, url: ideBrainRoot),
            Root(surface: .cli, url: cliBrainRoot)
        ]
        self.detectorVersion = detectorVersion
        self.sourceTool = sourceTool
        self.stableReader = stableReader
    }

    public func discover() throws -> SourceInventory {
        var candidateRecords: [Candidate] = []
        var detectedRoots: [URL] = []
        var isComplete = true
        var warnings: [SourceWarning] = []

        for root in roots {
            guard isDirectory(root.url) else {
                isComplete = false
                continue
            }
            detectedRoots.append(root.url)
            candidateRecords.append(contentsOf: try candidates(in: root))
        }

        var selected: [Candidate] = []
        var digestOwners: [String: Candidate] = [:]
        for candidate in candidateRecords.sorted(by: candidateSort) {
            let digest: String?
            var shouldKeepRecord = true
            do {
                let data = try stableReader(candidate.url)
                let result = try AntigravityParser.parse(
                    data: data,
                    sourceTool: sourceTool,
                    threadID: candidate.record.stableID,
                    sourcePath: candidate.url.path
                )
                shouldKeepRecord = !result.transcript.messages.isEmpty
                digest = result.transcript.messages.isEmpty
                    ? nil
                    : AntigravityParser.normalizedDigest(for: result.transcript)
                warnings.append(contentsOf: result.warnings.map { warning in
                    SourceWarning(
                        sourceTool: sourceTool,
                        recordID: candidate.record.stableID,
                        code: .malformedRecord,
                        message: "Ignored Antigravity trajectory content near line \(warning.lineNumber)"
                    )
                })
            } catch AntigravityReadError.recordChangedDuringRead {
                digest = nil
                warnings.append(SourceWarning(
                    sourceTool: sourceTool,
                    recordID: candidate.record.stableID,
                    code: .recordChangedDuringRead,
                    message: "Antigravity transcript changed while it was being read"
                ))
            } catch {
                digest = nil
                warnings.append(SourceWarning(
                    sourceTool: sourceTool,
                    recordID: candidate.record.stableID,
                    code: .malformedRecord,
                    message: "Could not inspect Antigravity transcript"
                ))
            }

            guard shouldKeepRecord else { continue }
            if let digest, let owner = digestOwners[digest] {
                warnings.append(SourceWarning(
                    sourceTool: sourceTool,
                    recordID: candidate.record.stableID,
                    code: .duplicateRecord,
                    message: "Ignored CLI duplicate of IDE transcript \(owner.record.stableID)"
                ))
                continue
            }
            selected.append(candidate)
            if let digest {
                digestOwners[digest] = candidate
            }
        }

        return SourceInventory(
            records: selected.map(\.record),
            warnings: warnings,
            detectedRoots: detectedRoots,
            isComplete: isComplete
        )
    }

    public func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript {
        guard record.sourceTool == sourceTool, case let .file(url) = record.locator else {
            throw ConversationSourceAdapterError.invalidRecord
        }
        let data = try stableReader(url)
        return try AntigravityParser.parse(
            data: data,
            sourceTool: sourceTool,
            threadID: record.stableID,
            sourcePath: url.path
        ).transcript
    }

    private func candidates(in root: Root) throws -> [Candidate] {
        let children = try FileManager.default.contentsOfDirectory(
            at: root.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.path < $1.path }

        return children.compactMap { directory in
            guard isDirectory(directory),
                  let uuid = UUID(uuidString: directory.lastPathComponent)
            else { return nil }
            let url = directory.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard isRegularFile(url) else { return nil }
            let stableID = "antigravity:\(root.surface.rawValue):\(uuid.uuidString.lowercased())"
            return Candidate(
                surface: root.surface,
                url: url,
                record: ConversationSourceRecord(
                    sourceTool: sourceTool,
                    stableID: stableID,
                    displayPath: url.path,
                    locator: .file(url),
                    fingerprint: SourceFileFingerprint.make(for: url, detectorVersion: detectorVersion)
                )
            )
        }
    }

    private func candidateSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.surface != rhs.surface {
            return lhs.surface == .ide
        }
        return lhs.url.path < rhs.url.path
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private struct Root: Sendable {
        let surface: Surface
        let url: URL
    }

    private struct Candidate: Sendable {
        let surface: Surface
        let url: URL
        let record: ConversationSourceRecord
    }

    private enum Surface: String, Sendable {
        case ide
        case cli
    }
}
