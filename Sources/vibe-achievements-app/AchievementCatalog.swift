import Foundation
import VibeAchievementsCore

enum AchievementFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case unlocked
    case locked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .unlocked: "Unlocked"
        case .locked: "Locked"
        }
    }
}

struct AchievementCatalogItem: Identifiable, Equatable {
    var contract: AchievementContract
    var unlock: AchievementUnlock?

    var id: String { contract.id }
    var isUnlocked: Bool { unlock != nil }
}

struct AchievementProgress: Equatable {
    var unlocked: Int
    var total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(unlocked) / Double(total)
    }
}

enum AchievementCatalog {
    static func items(contracts: [AchievementContract], unlocks: [AchievementUnlock], filter: AchievementFilter) -> [AchievementCatalogItem] {
        let unlocksByID = Dictionary(unlocks.map { ($0.achievementID, $0) }, uniquingKeysWith: { existing, replacement in
            existing.unlockedAt >= replacement.unlockedAt ? existing : replacement
        })
        let allItems = displayContracts(from: contracts).map { contract in
            AchievementCatalogItem(contract: contract, unlock: unlocksByID[contract.id])
        }

        switch filter {
        case .all:
            return allItems
        case .unlocked:
            return allItems.filter(\.isUnlocked)
        case .locked:
            return allItems.filter { !$0.isUnlocked }
        }
    }

    static func progress(contracts: [AchievementContract], unlocks: [AchievementUnlock]) -> AchievementProgress {
        let items = items(contracts: contracts, unlocks: unlocks, filter: .all)
        return AchievementProgress(
            unlocked: items.filter(\.isUnlocked).count,
            total: items.count
        )
    }

    private static func displayContracts(from contracts: [AchievementContract]) -> [AchievementContract] {
        contracts
            .filter { $0.active && $0.status == "keep" }
            .sorted { $0.number < $1.number }
    }
}
