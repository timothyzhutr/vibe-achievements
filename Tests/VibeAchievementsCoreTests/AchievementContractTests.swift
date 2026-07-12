import XCTest
@testable import VibeAchievementsCore

final class AchievementContractTests: XCTestCase {
    func testLoadsJSONLContracts() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "achievements-sample", withExtension: "jsonl"))
        let contracts = try AchievementContractLoader.load(jsonlURL: url)

        XCTAssertEqual(contracts.count, 2)
        XCTAssertEqual(contracts.first?.id, "actually_wait")
        XCTAssertEqual(contracts.last?.name, "rm -rf")
        XCTAssertTrue(contracts.allSatisfy(\.active))
    }

    func testLoadsBundledV1Contracts() throws {
        let contracts = try AchievementContractLoader.loadBundledV1()

        XCTAssertEqual(contracts.count, 50)
        XCTAssertTrue(contracts.contains { $0.id == "achievement_unlocked_unlocking_achievement" })
        XCTAssertTrue(contracts.contains { $0.id == "rm_rf" })
    }

    func testLoadsPackagedContractsFromMainBundleResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("packaged-contracts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent(
            "vibe-achievements_VibeAchievementsCore.bundle",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let packagedURL = bundle.appendingPathComponent("achievement-trigger-contracts-v1.jsonl")
        let sample = #"{"id":"packaged","number":1,"name":"Packaged","category":"test","definition":"Loaded from the app bundle.","detection_class":"metadata","signals":[],"window":"all_time","exclusions":[],"cooldown":"once","confidence":"high","status":"keep","difficulty":"starter","expected_frequency":"once","active":true}"#
        try (sample + "\n").write(to: packagedURL, atomically: true, encoding: .utf8)

        let contracts = try AchievementContractLoader.loadBundledV1(mainResourceURL: root)

        XCTAssertEqual(contracts.map(\.id), ["packaged"])
    }
}
