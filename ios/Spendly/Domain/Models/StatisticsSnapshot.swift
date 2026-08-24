import Foundation

struct StatisticsSnapshot: Sendable, Equatable {
    let totalMinor: Int64
    let byDay: [String: Int64]
    let byCategory: [String: Int64]
}
