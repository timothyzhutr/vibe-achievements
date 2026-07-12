import Foundation

/// A source or record problem surfaced during indexing instead of being
/// silently dropped. Structured adapter warning fields are preserved when known.
public struct IndexWarning: Sendable, Equatable {
    public var path: String
    public var message: String
    public var sourceTool: SourceTool?
    public var recordID: String?
    public var code: SourceWarningCode?

    public init(
        path: String,
        message: String,
        sourceTool: SourceTool? = nil,
        recordID: String? = nil,
        code: SourceWarningCode? = nil
    ) {
        self.path = path
        self.message = message
        self.sourceTool = sourceTool
        self.recordID = recordID
        self.code = code
    }
}

/// Outcome of an indexing pass: the achievements unlocked plus any files that
/// were skipped because they could not be parsed.
public struct IndexResult: Sendable {
    public var unlocks: [AchievementUnlock]
    public var warnings: [IndexWarning]
    public var changedRecordCount: Int
    public var sourceStatuses: [ConversationSourceStatus]

    public init(
        unlocks: [AchievementUnlock],
        warnings: [IndexWarning],
        changedRecordCount: Int = 0,
        sourceStatuses: [ConversationSourceStatus] = []
    ) {
        self.unlocks = unlocks
        self.warnings = warnings
        self.changedRecordCount = changedRecordCount
        self.sourceStatuses = sourceStatuses
    }
}

public enum Indexer {
    private static let skippedUnsupportedThreadID = "__vibe_unsupported_source_record__"

    @discardableResult
    public static func index(
        adapters: [any ConversationSourceAdapter],
        contracts: [AchievementContract],
        store: SQLiteStore,
        scanID: String
    ) throws -> IndexResult {
        var unlockedIDs = try store.unlockedAchievementIDs()
        var allUnlocks: [AchievementUnlock] = []
        var warnings: [IndexWarning] = []
        var changedRecordCount = 0
        var sourceStatuses: [ConversationSourceStatus] = []

        for adapter in adapters {
            let inventory: SourceInventory
            do {
                inventory = try adapter.discover()
            } catch {
                warnings.append(IndexWarning(
                    path: adapter.displayName,
                    message: String(describing: error),
                    sourceTool: adapter.sourceTool
                ))
                sourceStatuses.append(ConversationSourceStatus(
                    sourceTool: adapter.sourceTool,
                    displayName: adapter.displayName,
                    state: .needsAttention,
                    recordCount: 0,
                    warningCount: 1
                ))
                continue
            }

            let warningStartCount = warnings.count
            warnings.append(contentsOf: inventory.warnings.map { warning in
                let path = inventory.records.first { $0.stableID == warning.recordID }?.displayPath
                    ?? warning.recordID
                    ?? adapter.displayName
                return IndexWarning(
                    path: path,
                    message: warning.message,
                    sourceTool: warning.sourceTool,
                    recordID: warning.recordID,
                    code: warning.code
                )
            })

            var seenRecordIDs = Set<String>()
            var canReconcileMissingRecords = inventory.isComplete
                && !inventory.warnings.contains { $0.code != .duplicateRecord }
            for record in inventory.records {
                guard record.sourceTool == adapter.sourceTool else {
                    canReconcileMissingRecords = false
                    warnings.append(IndexWarning(
                        path: record.displayPath,
                        message: "Adapter returned a record for \(record.sourceTool.rawValue)"
                    ))
                    continue
                }
                guard seenRecordIDs.insert(record.stableID).inserted else {
                    canReconcileMissingRecords = false
                    warnings.append(IndexWarning(path: record.displayPath, message: "Duplicate source record identity"))
                    continue
                }

                let knownRecord = try store.sourceRecord(identity: record.identity)
                if knownRecord != nil {
                    try store.markSourceRecordSeen(
                        identity: record.identity,
                        displayPath: record.displayPath,
                        scanID: scanID
                    )
                }
                let hasCompleteUnchangedState = knownRecord?.fingerprint == record.fingerprint
                    && !(knownRecord?.threadID.isEmpty ?? true)
                guard !hasCompleteUnchangedState else { continue }
                changedRecordCount += 1

                let parsed: ParsedTranscript
                do {
                    parsed = try adapter.parse(record)
                } catch {
                    warnings.append(IndexWarning(
                        path: record.displayPath,
                        message: String(describing: error),
                        sourceTool: adapter.sourceTool,
                        recordID: record.stableID
                    ))
                    if error as? ConversationSourceAdapterError == .unsupportedRecord,
                       knownRecord == nil || knownRecord?.threadID == skippedUnsupportedThreadID {
                        try store.recordSourceRecord(
                            record: record,
                            threadID: skippedUnsupportedThreadID,
                            scanID: scanID
                        )
                    }
                    continue
                }

                try store.upsert(thread: parsed.thread)
                let remainingContracts = contracts.filter {
                    $0.active && $0.status == "keep" && !unlockedIDs.contains($0.id)
                }
                let events = EventExtractor.extract(from: parsed)
                let unlocks = AchievementEngine.evaluate(
                    contracts: remainingContracts,
                    parsed: parsed,
                    events: events,
                    existingUnlockedIDs: unlockedIDs
                )
                for unlock in unlocks {
                    try store.insert(unlock: unlock)
                    unlockedIDs.insert(unlock.achievementID)
                }
                allUnlocks.append(contentsOf: unlocks)
                try store.recordSourceRecord(
                    record: record,
                    threadID: parsed.thread.id,
                    scanID: scanID
                )
            }

            if canReconcileMissingRecords {
                try store.reconcileMissingSourceRecords(
                    sourceTool: adapter.sourceTool,
                    seenRecordIDs: seenRecordIDs,
                    scanID: scanID
                )
            }
            let adapterWarningCount = warnings.count - warningStartCount
            sourceStatuses.append(ConversationSourceStatus(
                sourceTool: adapter.sourceTool,
                displayName: adapter.displayName,
                state: adapterWarningCount > 0
                    ? .needsAttention
                    : (inventory.records.isEmpty ? .empty : .connected),
                recordCount: inventory.records.count,
                warningCount: adapterWarningCount
            ))
        }

        return IndexResult(
            unlocks: allUnlocks,
            warnings: warnings,
            changedRecordCount: changedRecordCount,
            sourceStatuses: sourceStatuses
        )
    }

}
