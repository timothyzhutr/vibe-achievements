import Foundation

public struct SourceRecordIdentity: Hashable, Sendable {
    public let sourceTool: SourceTool
    public let stableID: String

    public init(sourceTool: SourceTool, stableID: String) {
        self.sourceTool = sourceTool
        self.stableID = stableID
    }
}

public enum SourceWarningCode: String, Sendable {
    case permissionDenied
    case sourceBusy
    case schemaUnsupported
    case malformedRecord
    case recordChangedDuringRead
    case duplicateRecord
}

public struct SourceWarning: Equatable, Sendable {
    public let sourceTool: SourceTool
    public let recordID: String?
    public let code: SourceWarningCode
    public let message: String

    public init(sourceTool: SourceTool, recordID: String? = nil, code: SourceWarningCode, message: String) {
        self.sourceTool = sourceTool
        self.recordID = recordID
        self.code = code
        self.message = message
    }
}

public struct SourceInventory: Sendable {
    public let records: [ConversationSourceRecord]
    public let warnings: [SourceWarning]
    public let detectedRoots: [URL]
    public let isComplete: Bool

    public init(
        records: [ConversationSourceRecord],
        warnings: [SourceWarning],
        detectedRoots: [URL],
        isComplete: Bool = true
    ) {
        self.records = records
        self.warnings = warnings
        self.detectedRoots = detectedRoots
        self.isComplete = isComplete
    }
}

public enum SourceRecordLocator: Hashable, Sendable {
    case file(URL)
    case directory(root: URL, recordID: String)
    case database(database: URL, recordID: String)
}

public struct ConversationSourceRecord: Hashable, Sendable {
    public let sourceTool: SourceTool
    public let stableID: String
    public let displayPath: String
    public let locator: SourceRecordLocator
    public let fingerprint: String

    public var identity: SourceRecordIdentity {
        SourceRecordIdentity(sourceTool: sourceTool, stableID: stableID)
    }

    public init(
        sourceTool: SourceTool,
        stableID: String,
        displayPath: String,
        locator: SourceRecordLocator,
        fingerprint: String
    ) {
        self.sourceTool = sourceTool
        self.stableID = stableID
        self.displayPath = displayPath
        self.locator = locator
        self.fingerprint = fingerprint
    }
}

public protocol ConversationSourceAdapter: Sendable {
    var sourceTool: SourceTool { get }
    var displayName: String { get }

    func discover() throws -> SourceInventory
    func parse(_ record: ConversationSourceRecord) throws -> ParsedTranscript
}

public enum ConversationSourceAdapterError: Error, Equatable {
    case invalidRecord
    case unsupportedRecord
}
