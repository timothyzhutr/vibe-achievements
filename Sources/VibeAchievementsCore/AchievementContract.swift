import Foundation

public struct AchievementContract: Codable, Equatable, Sendable {
    public var id: String
    public var number: Int
    public var name: String
    public var category: String
    public var definition: String
    public var detectionClass: String
    public var signals: [String]
    public var window: String
    public var exclusions: [String]
    public var cooldown: String
    public var confidence: String
    public var status: String
    public var difficulty: String
    public var expectedFrequency: String
    public var active: Bool

    enum CodingKeys: String, CodingKey {
        case id, number, name, category, definition, signals, window, exclusions, cooldown, confidence, status, difficulty, active
        case detectionClass = "detection_class"
        case expectedFrequency = "expected_frequency"
    }
}

public enum AchievementContractLoader {
    public static func load(jsonlURL: URL) throws -> [AchievementContract] {
        let data = try Data(contentsOf: jsonlURL)
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").map { line in
            try decoder.decode(AchievementContract.self, from: Data(line.utf8))
        }
    }
}
