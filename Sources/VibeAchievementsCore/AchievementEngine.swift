import Foundation

public struct AchievementUnlock: Codable, Equatable, Sendable {
    public var achievementID: String
    public var name: String
    /// Where the unlock first happened. Achievements are global (once per user,
    /// ever), so these are kept for display/diagnostics only.
    public var projectKey: String?
    public var threadID: String?
    public var unlockedAt: Date
    public var triggerSummary: String

    public init(achievementID: String, name: String, projectKey: String?, threadID: String?, unlockedAt: Date, triggerSummary: String) {
        self.achievementID = achievementID
        self.name = name
        self.projectKey = projectKey
        self.threadID = threadID
        self.unlockedAt = unlockedAt
        self.triggerSummary = triggerSummary
    }
}

public enum AchievementEngine {
    /// Evaluates a single transcript. `existingUnlockedIDs` are the achievement
    /// ids already unlocked (globally); they are never re-emitted.
    public static func evaluate(contracts: [AchievementContract], parsed: ParsedTranscript, events: [ExtractedEvent], existingUnlockedIDs: Set<String> = []) -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        let activeContracts = contracts.filter { $0.active && $0.status == "keep" && !existingUnlockedIDs.contains($0.id) }

        unlock("actually_wait", if: events.contains { $0.type == .correctionLanguageSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Changed direction mid-thread.")
        unlock("one_more_prompt", if: events.contains { $0.type == .oneMorePromptSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Continued a thread for 10 or more user turns.")
        unlock("rm_rf", if: hasSequence([.destructiveCleanupSeen, .recoverySeen], events) || hasSequence([.destructiveCleanupSeen, .successSeen], events), activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Destructive cleanup was followed by recovery.")
        unlock("it_works_therefore_it_is", if: hasSequence([.implementationOrFixSeen, .successSeen], events), activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Implementation or fix work was followed by success.")
        unlockFirstAchievementIfNeeded(activeContracts: activeContracts, existingUnlockedIDs: existingUnlockedIDs, unlocks: &unlocks)

        return unlocks
    }

    private static func unlockFirstAchievementIfNeeded(activeContracts: [AchievementContract], existingUnlockedIDs: Set<String>, unlocks: inout [AchievementUnlock]) {
        guard existingUnlockedIDs.isEmpty,
              !unlocks.isEmpty,
              let contract = activeContracts.first(where: { $0.id == "achievement_unlocked_unlocking_achievement" })
        else { return }
        unlocks.append(AchievementUnlock(achievementID: contract.id, name: contract.name, projectKey: nil, threadID: nil, unlockedAt: Date(), triggerSummary: "Unlocked the first achievement."))
    }

    private static func unlock(_ id: String, if condition: Bool, activeContracts: [AchievementContract], parsed: ParsedTranscript, unlocks: inout [AchievementUnlock], summary: String) {
        guard condition, let contract = activeContracts.first(where: { $0.id == id }) else { return }
        unlocks.append(AchievementUnlock(
            achievementID: contract.id,
            name: contract.name,
            projectKey: parsed.thread.projectKey,
            threadID: parsed.thread.id,
            unlockedAt: Date(),
            triggerSummary: summary
        ))
    }

    private static func hasSequence(_ sequence: [EventType], _ events: [ExtractedEvent]) -> Bool {
        // Swift's sort is not stable, so tie-break equal (or missing) timestamps
        // by extraction order — events are extracted in transcript order.
        let ordered = events.enumerated()
            .sorted { ($0.element.timestamp ?? .distantPast, $0.offset) < ($1.element.timestamp ?? .distantPast, $1.offset) }
            .map(\.element)

        var index = 0
        for event in ordered {
            if event.type == sequence[index] {
                index += 1
                if index == sequence.count { return true }
            }
        }
        return false
    }
}
