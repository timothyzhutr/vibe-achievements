import Foundation

public struct EventSummary: Sendable {
    private let counts: [EventType: Int]
    private let ordered: [ExtractedEvent]

    public init(events: [ExtractedEvent]) {
        self.counts = Dictionary(grouping: events, by: \.type).mapValues(\.count)
        self.ordered = events.enumerated()
            .sorted { lhs, rhs in
                (lhs.element.timestamp ?? .distantPast, lhs.offset) < (rhs.element.timestamp ?? .distantPast, rhs.offset)
            }
            .map(\.element)
    }

    public func has(_ type: EventType) -> Bool {
        count(type) > 0
    }

    public func count(_ type: EventType) -> Int {
        counts[type] ?? 0
    }

    public func sequence(_ sequence: [EventType]) -> Bool {
        guard !sequence.isEmpty else { return true }
        var index = 0
        for event in ordered where event.type == sequence[index] {
            index += 1
            if index == sequence.count { return true }
        }
        return false
    }
}
