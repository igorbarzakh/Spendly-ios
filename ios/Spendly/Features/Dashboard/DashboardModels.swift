import Foundation

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case day
    case month
    case year

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

struct DashboardTransaction: Identifiable, Equatable {
    let id: String
    let merchant: String
    let category: DashboardCategory
    let itemCount: Int?
    let amountMinorUnits: Int64

    var detailsText: String {
        guard let itemCount, itemCount > 0 else {
            return category.title
        }
        return "\(category.title) · \(DashboardFormatting.itemCount(itemCount))"
    }
}

enum DashboardCategory: String, Equatable {
    case groceries
    case transport
    case dining
    case subscriptions
    case shopping

    var title: String {
        switch self {
        case .groceries:
            "Продукты"
        case .transport:
            "Транспорт"
        case .dining:
            "Кафе и рестораны"
        case .subscriptions:
            "Подписки"
        case .shopping:
            "Покупки"
        }
    }

    var symbolName: String {
        switch self {
        case .groceries:
            "basket.fill"
        case .transport:
            "car.fill"
        case .dining:
            "cup.and.saucer.fill"
        case .subscriptions:
            "music.note"
        case .shopping:
            "bag.fill"
        }
    }
}

enum DashboardSamples {
    static let currentMonthLimitMinorUnits: Int64 = 10_000_000

    static var currentMonthTotalMinorUnits: Int64 {
        snapshot(for: .month).totalMinorUnits
    }

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
