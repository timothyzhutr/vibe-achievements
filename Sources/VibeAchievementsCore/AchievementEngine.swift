import Foundation

public struct AchievementUnlock: Codable, Equatable, Sendable {
    public var achievementID: String
    public var name: String
    public var projectKey: String?
    public var threadID: String?
    public var unlockedAt: Date
    public var triggerSummary: String

    /// Stable identity for an unlock, scoped the way its cooldown implies.
    /// Project-scoped achievements unlock once per project; globally-scoped
    /// achievements (no project) unlock once overall. Must match the key the
    /// store derives from its columns.
    public var unlockKey: String {
        makeUnlockKey(achievementID: achievementID, projectKey: projectKey)
    }
}

/// Single source of truth for unlock identity, shared by the engine and store.
public func makeUnlockKey(achievementID: String, projectKey: String?) -> String {
    guard let projectKey, !projectKey.isEmpty else { return achievementID }
    return "\(achievementID)@\(projectKey)"
}

public enum AchievementEngine {
    public static func evaluate(contracts: [AchievementContract], parsed: ParsedTranscript, events: [ExtractedEvent], existingUnlockKeys: Set<String> = []) -> [AchievementUnlock] {
        var unlocks: [AchievementUnlock] = []
        let activeContracts = contracts.filter { $0.active && $0.status == "keep" }

        unlockFirstAchievementIfNeeded(activeContracts: activeContracts, existingUnlockKeys: existingUnlockKeys, unlocks: &unlocks)
        unlock("actually_wait", if: events.contains { $0.type == .correctionLanguageSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Changed direction mid-thread.")
        unlock("one_more_prompt", if: events.contains { $0.type == .oneMorePromptSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Continued a thread for 10 or more user turns.")
        unlock("rm_rf", if: hasSequence([.destructiveCleanupSeen, .recoverySeen], events) || hasSequence([.destructiveCleanupSeen, .successSeen], events), activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Destructive cleanup was followed by recovery.")
        unlock("it_works_therefore_it_is", if: events.contains { $0.type == .successSeen }, activeContracts: activeContracts, parsed: parsed, unlocks: &unlocks, summary: "Something works now.")

        return unlocks.filter { !existingUnlockKeys.contains($0.unlockKey) }
    }

    private static func unlockFirstAchievementIfNeeded(activeContracts: [AchievementContract], existingUnlockKeys: Set<String>, unlocks: inout [AchievementUnlock]) {
        guard existingUnlockKeys.isEmpty,
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
