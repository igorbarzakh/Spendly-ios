import Foundation

protocol StatisticsRepository: Sendable {
    func statistics(in context: ExpenseContext, interval: DateInterval) async throws -> StatisticsSnapshot
}
