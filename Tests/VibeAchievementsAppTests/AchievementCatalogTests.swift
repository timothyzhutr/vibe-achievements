import XCTest
@testable import VibeAchievementsApp
@testable import VibeAchievementsCore

final class AchievementCatalogTests: XCTestCase {
    func testBuildsCatalogInContractOrderWithUnlockState() {
        let contracts = [
            contract(id: "first", number: 1, name: "First"),
            contract(id: "dropped", number: 2, name: "Dropped", active: false),
            contract(id: "second", number: 3, name: "Second")
        ]
        let unlocks = [
            unlock(id: "second", name: "Second")
        ]

        let items = AchievementCatalog.items(contracts: contracts, unlocks: unlocks, filter: .all)

        XCTAssertEqual(items.map(\.id), ["first", "second"])
        XCTAssertFalse(items[0].isUnlocked)
        XCTAssertTrue(items[1].isUnlocked)
        XCTAssertEqual(items[1].unlock?.achievementID, "second")
    }

    func testFiltersUnlockedAndLockedItems() {
        let contracts = [
            contract(id: "first", number: 1, name: "First"),
            contract(id: "second", number: 2, name: "Second")
        ]
        let unlocks = [unlock(id: "second", name: "Second")]

        XCTAssertEqual(AchievementCatalog.items(contracts: contracts, unlocks: unlocks, filter: .unlocked).map(\.id), ["second"])
        XCTAssertEqual(AchievementCatalog.items(contracts: contracts, unlocks: unlocks, filter: .locked).map(\.id), ["first"])
    }

    func testProgressCountsActiveKeepContracts() {
        let contracts = [
            contract(id: "first", number: 1, name: "First"),
            contract(id: "second", number: 2, name: "Second"),
            contract(id: "future", number: 3, name: "Future", status: "future", active: false)
        ]
        let unlocks = [unlock(id: "second", name: "Second")]

        let progress = AchievementCatalog.progress(contracts: contracts, unlocks: unlocks)

        XCTAssertEqual(progress.unlocked, 1)
        XCTAssertEqual(progress.total, 2)
    }

    func testDuplicateUnlockRowsUseLatestUnlock() {
        let contracts = [contract(id: "first", number: 1, name: "First")]
        let unlocks = [
            unlock(id: "first", name: "First", unlockedAt: Date(timeIntervalSince1970: 1_000)),
            unlock(id: "first", name: "First", unlockedAt: Date(timeIntervalSince1970: 2_000))
        ]

        let item = AchievementCatalog.items(contracts: contracts, unlocks: unlocks, filter: .all).first

        XCTAssertEqual(item?.unlock?.unlockedAt, Date(timeIntervalSince1970: 2_000))
    }

    private func contract(id: String, number: Int, name: String, status: String = "keep", active: Bool = true) -> AchievementContract {
        AchievementContract(
            id: id,
            number: number,
            name: name,
            category: "test",
            definition: "\(name) definition",
            detectionClass: "keyword",
            signals: [],
            window: "all_time",
            exclusions: [],
            cooldown: "once_per_user",
            confidence: "high",
            status: status,
            difficulty: "starter",
            expectedFrequency: "weekly",
            active: active
        )
    }

    private func unlock(id: String, name: String, unlockedAt: Date = Date(timeIntervalSince1970: 1_000)) -> AchievementUnlock {
        AchievementUnlock(
            achievementID: id,
            name: name,
            projectKey: "/tmp/project",
            threadID: "claude_code:thread",
            unlockedAt: unlockedAt,
            triggerSummary: "\(name) unlocked"
        )
    }
}
