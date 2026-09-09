import Foundation
import Observation

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case day
    case month
    case year

    static let defaultSelection: DashboardPeriod = .day

    var id: Self { self }

    var title: String {
        switch self {
        case .day:
            "День"
        case .month:
            "Месяц"
        case .year:
            "Год"
        }
    }

    var summaryTitle: String {
        switch self {
        case .day:
            "Потрачено сегодня"
        case .month:
            "Потрачено в этом месяце"
        case .year:
            "Потрачено за год"
        }
    }
}

struct DashboardSnapshot: Equatable {
    let period: DashboardPeriod
    let totalMinorUnits: Int64
    let transactions: [DashboardTransaction]

    func recentTransactions(limit: Int) -> [DashboardTransaction] {
        Array(transactions.prefix(max(0, limit)))
    }
}

struct DashboardBudgetProgress: Equatable {
    let spentMinorUnits: Int64
    let limitMinorUnits: Int64

    init(spentMinorUnits: Int64, limitMinorUnits: Int64) {
        self.spentMinorUnits = max(0, spentMinorUnits)
        self.limitMinorUnits = max(0, limitMinorUnits)
    }

    var fraction: Double {
        guard limitMinorUnits > 0 else { return 0 }
        return min(Double(spentMinorUnits) / Double(limitMinorUnits), 1)
    }

    var remainingMinorUnits: Int64 {
        max(limitMinorUnits - spentMinorUnits, 0)
    }

    var overageMinorUnits: Int64 {
        guard limitMinorUnits > 0 else { return 0 }
        return max(spentMinorUnits - limitMinorUnits, 0)
    }

    var isOverLimit: Bool {
        overageMinorUnits > 0
    }
}

@MainActor
@Observable
final class DashboardSummaryModel {
    private(set) var totalMinorUnits: Int64 = 0
    private(set) var isLoading = false
    private(set) var failure: AppFailure?

    private let repository: any PurchaseRepository
    private let context: ExpenseContext

    init(
        repository: any PurchaseRepository,
        context: ExpenseContext
    ) {
        self.repository = repository
        self.context = context
    }

    func load(
        period: DashboardPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) async {
        guard !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let purchases = try await repository.purchases(
                in: context,
                interval: period.interval(containing: now, calendar: calendar)
            )
            totalMinorUnits = purchases.reduce(Int64(0)) { $0 + $1.total.minorUnits }
        } catch is CancellationError {
            return
        } catch {
            failure = error as? AppFailure ?? .unknown
        }
    }

    func applyUpdate(
        from previous: Purchase,
        to current: Purchase,
        period: DashboardPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let interval = period.interval(containing: now, calendar: calendar)
        let previousAmount = interval.contains(previous.spentAt) ? previous.total.minorUnits : 0
        let currentAmount = interval.contains(current.spentAt) ? current.total.minorUnits : 0
        totalMinorUnits = max(0, totalMinorUnits - previousAmount + currentAmount)
    }

    func applyDeletion(
        _ purchase: Purchase,
        period: DashboardPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard period.interval(containing: now, calendar: calendar).contains(purchase.spentAt) else { return }
        totalMinorUnits = max(0, totalMinorUnits - purchase.total.minorUnits)
    }
}

@MainActor
@Observable
final class DashboardMonthlyBudgetModel {
    private(set) var spentMinorUnits: Int64 = 0
    private(set) var isLoading = false
    private(set) var failure: AppFailure?

    private let repository: any PurchaseRepository
    private let context: ExpenseContext

    init(repository: any PurchaseRepository, context: ExpenseContext) {
        self.repository = repository
        self.context = context
    }

    func load(now: Date = .now, calendar: Calendar = .current) async {
        guard !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let interval = DashboardPeriod.month.interval(containing: now, calendar: calendar)
            let purchases = try await repository.purchases(in: context, interval: interval)
            spentMinorUnits = purchases.reduce(Int64(0)) { $0 + $1.total.minorUnits }
        } catch is CancellationError {
            return
        } catch {
            failure = error as? AppFailure ?? .unknown
        }
    }

    func applyUpdate(
        from previous: Purchase,
        to current: Purchase,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let interval = DashboardPeriod.month.interval(containing: now, calendar: calendar)
        let previousAmount = interval.contains(previous.spentAt) ? previous.total.minorUnits : 0
        let currentAmount = interval.contains(current.spentAt) ? current.total.minorUnits : 0
        spentMinorUnits = max(0, spentMinorUnits - previousAmount + currentAmount)
    }

    func applyDeletion(
        _ purchase: Purchase,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let interval = DashboardPeriod.month.interval(containing: now, calendar: calendar)
        guard interval.contains(purchase.spentAt) else { return }
        spentMinorUnits = max(0, spentMinorUnits - purchase.total.minorUnits)
    }
}

struct PurchaseMutationEvent: Equatable {
    let id = UUID()
    let previous: Purchase
    let current: Purchase?

    static func updated(from previous: Purchase, to current: Purchase) -> PurchaseMutationEvent {
        PurchaseMutationEvent(previous: previous, current: current)
    }

    static func deleted(_ purchase: Purchase) -> PurchaseMutationEvent {
        PurchaseMutationEvent(previous: purchase, current: nil)
    }
}

struct DashboardTransaction: Identifiable, Equatable {
    let id: String
    let merchant: String
    let category: DashboardCategory
    let itemCount: Int?
    let amountMinorUnits: Int64
    let purchase: Purchase?

    init(
        id: String,
        merchant: String,
        category: DashboardCategory,
        itemCount: Int?,
        amountMinorUnits: Int64,
        purchase: Purchase? = nil
    ) {
        self.id = id
        self.merchant = merchant
        self.category = category
        self.itemCount = itemCount
        self.amountMinorUnits = amountMinorUnits
        self.purchase = purchase
    }

    var detailsText: String {
        guard let itemCount, itemCount > 0 else {
            return category.title
        }
        return "\(category.title) · \(DashboardFormatting.itemCount(itemCount))"
    }
}

extension DashboardPeriod {
    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        switch self {
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
            return DateInterval(start: start, end: end)
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, end: date)
        case .year:
            return calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, end: date)
        }
    }
}

struct DashboardCategory: Equatable {
    static let groceries = DashboardCategory(name: "Продукты")
    static let transport = DashboardCategory(name: "Транспорт")
    static let dining = DashboardCategory(name: "Кафе")
    static let subscriptions = DashboardCategory(name: "Подписки")
    static let shopping = DashboardCategory(name: "Покупки")

    let title: String
    let symbolName: String
    let tintHex: UInt32

    init(name: String) {
        let presentation = ExpenseCategoryPresentation.resolved(for: name)
        title = presentation.name.isEmpty ? "Покупки" : presentation.name
        symbolName = presentation.symbolName
        tintHex = presentation.tintHex
    }
}

@MainActor
@Observable
final class DashboardRecentTransactionsModel {
    private(set) var transactions: [DashboardTransaction] = []
    private(set) var isLoading = false
    private(set) var failure: AppFailure?

    private let repository: any PurchaseRepository
    private let context: ExpenseContext
    private let limit: Int
    private var didLoad = false

    init(
        repository: any PurchaseRepository,
        context: ExpenseContext,
        limit: Int = 5
    ) {
        self.repository = repository
        self.context = context
        self.limit = limit
    }

    func load() async {
        guard !didLoad, !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let page = try await repository.purchasePage(in: context, after: nil, limit: limit)
            transactions = page.purchases.map(DashboardTransaction.init(purchase:))
            didLoad = true
        } catch is CancellationError {
            return
        } catch {
            failure = error as? AppFailure ?? .unknown
        }
    }

    func retry() async {
        didLoad = false
        await load()
    }

    func refresh() async {
        didLoad = false
        await load()
    }

    func applyUpdatedPurchase(_ purchase: Purchase) {
        guard let index = transactions.firstIndex(where: { $0.purchase?.id == purchase.id }) else { return }
        transactions[index] = DashboardTransaction(purchase: purchase)
    }

    func removeDeletedPurchase(id: PurchaseID) {
        transactions.removeAll { $0.purchase?.id == id }
    }

    func replenishIfNeeded() async {
        guard transactions.count < limit, !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let page = try await repository.purchasePage(in: context, after: nil, limit: limit)
            transactions = page.purchases
                .prefix(limit)
                .map(DashboardTransaction.init(purchase:))
        } catch is CancellationError {
            return
        } catch {
            failure = error as? AppFailure ?? .unknown
        }
    }
}

extension DashboardTransaction {
    init(purchase: Purchase) {
        self.id = purchase.id.rawValue.uuidString
        self.merchant = purchase.merchant
        self.amountMinorUnits = purchase.total.minorUnits
        self.purchase = purchase

        switch purchase.kind {
        case let .quick(category, _):
            self.category = DashboardCategory(name: category)
            self.itemCount = nil
        case let .detailed(items):
            let categories = Set(items.map(\.category))
            let categoryName = categories.count == 1 ? (categories.first ?? "Покупки") : "Покупки"
            self.category = DashboardCategory(name: categoryName)
            self.itemCount = items.count
        }
    }
}

enum DashboardSamples {
    static let currentMonthLimitMinorUnits: Int64 = 10_000_000

    static func snapshot(for period: DashboardPeriod) -> DashboardSnapshot {
        switch period {
        case .day:
            DashboardSnapshot(
                period: .day,
                totalMinorUnits: 265_500,
                transactions: recentTransactions
            )
        case .month:
            DashboardSnapshot(
                period: .month,
                totalMinorUnits: 8_432_000,
                transactions: recentTransactions
            )
        case .year:
            DashboardSnapshot(
                period: .year,
                totalMinorUnits: 74_286_000,
                transactions: recentTransactions
            )
        }
    }

    private static let recentTransactions = [
        DashboardTransaction(
            id: "groceries-perekrestok",
            merchant: "Перекрёсток",
            category: .groceries,
            itemCount: 5,
            amountMinorUnits: 124_700
        ),
        DashboardTransaction(
            id: "transport-yandex",
            merchant: "Яндекс Такси",
            category: .transport,
            itemCount: nil,
            amountMinorUnits: 56_000
        ),
        DashboardTransaction(
            id: "dining-surf",
            merchant: "Surf Coffee",
            category: .dining,
            itemCount: nil,
            amountMinorUnits: 45_900
        ),
        DashboardTransaction(
            id: "subscription-music",
            merchant: "Музыка",
            category: .subscriptions,
            itemCount: nil,
            amountMinorUnits: 16_900
        ),
        DashboardTransaction(
            id: "shopping-marketplace",
            merchant: "Маркетплейс",
            category: .shopping,
            itemCount: 2,
            amountMinorUnits: 234_100
        ),
        DashboardTransaction(
            id: "groceries-delivery",
            merchant: "Доставка продуктов",
            category: .groceries,
            itemCount: 4,
            amountMinorUnits: 87_300
        )
    ]
}

enum DashboardFormatting {
    static func amount(_ minorUnits: Int64) -> String {
        MoneyFormatter.rublesMinorUnits(minorUnits)
    }

    static func expense(_ minorUnits: Int64) -> String {
        "−" + amount(abs(minorUnits))
    }

    static func itemCount(_ count: Int) -> String {
        let normalizedCount = max(0, count)
        let lastTwoDigits = normalizedCount % 100
        let lastDigit = normalizedCount % 10

        let noun: String
        if 11...14 ~= lastTwoDigits {
            noun = "товаров"
        } else {
            switch lastDigit {
            case 1:
                noun = "товар"
            case 2...4:
                noun = "товара"
            default:
                noun = "товаров"
            }
        }

        return "\(normalizedCount) \(noun)"
    }
}
