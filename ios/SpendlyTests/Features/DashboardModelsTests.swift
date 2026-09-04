import XCTest
@testable import Spendly

final class DashboardModelsTests: XCTestCase {
    func testDashboardUsesFixedDemoMonthlyLimit() {
        XCTAssertEqual(DashboardSamples.currentMonthLimitMinorUnits, 10_000_000)
    }

    func testRecentTransactionsAreLimitedToRequestedCount() {
        let snapshot = DashboardSamples.snapshot(for: .month)

        XCTAssertEqual(snapshot.recentTransactions(limit: 5).count, 5)
        XCTAssertEqual(
            snapshot.recentTransactions(limit: 5).map(\.id),
            Array(snapshot.transactions.prefix(5)).map(\.id)
        )
    }

    func testCurrentMonthTotalIsIndependentDashboardMetric() {
        XCTAssertEqual(
            DashboardSamples.currentMonthTotalMinorUnits,
            DashboardSamples.snapshot(for: .month).totalMinorUnits
        )
    }

    func testBudgetProgressCalculatesRemainingAmountAndFraction() {
        let progress = DashboardBudgetProgress(
            spentMinorUnits: 8_432_000,
            limitMinorUnits: 10_000_000
        )

        XCTAssertEqual(progress.fraction, 0.8432, accuracy: 0.0001)
        XCTAssertEqual(progress.remainingMinorUnits, 1_568_000)
        XCTAssertEqual(progress.overageMinorUnits, 0)
        XCTAssertFalse(progress.isOverLimit)
    }

    func testBudgetProgressCapsVisualFractionAndReportsOverage() {
        let progress = DashboardBudgetProgress(
            spentMinorUnits: 12_500_000,
            limitMinorUnits: 10_000_000
        )

        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remainingMinorUnits, 0)
        XCTAssertEqual(progress.overageMinorUnits, 2_500_000)
        XCTAssertTrue(progress.isOverLimit)
    }

    func testBudgetProgressNormalizesInvalidAmounts() {
        let progress = DashboardBudgetProgress(
            spentMinorUnits: -1,
            limitMinorUnits: 0
        )

        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.remainingMinorUnits, 0)
        XCTAssertEqual(progress.overageMinorUnits, 0)
        XCTAssertFalse(progress.isOverLimit)
    }

    func testPeriodsHaveStableDisplayOrderAndTitles() {
        XCTAssertEqual(DashboardPeriod.allCases, [.day, .month, .year])
        XCTAssertEqual(DashboardPeriod.allCases.map(\.title), ["День", "Месяц", "Год"])
    }

    func testEveryPeriodProvidesCompleteSampleSnapshot() {
        for period in DashboardPeriod.allCases {
            let snapshot = DashboardSamples.snapshot(for: period)

            XCTAssertEqual(snapshot.period, period)
            XCTAssertGreaterThan(snapshot.totalMinorUnits, 0)
            XCTAssertFalse(snapshot.transactions.isEmpty)
        }
    }

    func testTransactionsUseCategorySymbolsInsteadOfMerchantArtwork() {
        for period in DashboardPeriod.allCases {
            let transactions = DashboardSamples.snapshot(for: period).transactions

            XCTAssertTrue(transactions.allSatisfy { !$0.category.symbolName.isEmpty })
        }
    }

    func testPeriodSummaryTitlesDescribeSelectedRange() {
        XCTAssertEqual(DashboardPeriod.day.summaryTitle, "Потрачено сегодня")
        XCTAssertEqual(DashboardPeriod.month.summaryTitle, "Потрачено в этом месяце")
        XCTAssertEqual(DashboardPeriod.year.summaryTitle, "Потрачено за год")
    }

    func testDashboardFormattingUsesRublesAndTypographicMinus() {
        XCTAssertEqual(DashboardFormatting.amount(8_432_000), "84 320 ₽")
        XCTAssertEqual(DashboardFormatting.expense(124_700), "−1 247 ₽")
    }

    func testTransactionDetailsShowItemCountOnlyForBasketPurchases() {
        let transactions = DashboardSamples.snapshot(for: .month).transactions

        XCTAssertEqual(transactions[0].detailsText, "Продукты · 5 товаров")
        XCTAssertEqual(transactions[1].detailsText, "Транспорт")
        XCTAssertEqual(transactions[4].detailsText, "Покупки · 2 товара")
    }

    func testItemCountFormattingUsesRussianPluralForms() {
        XCTAssertEqual(DashboardFormatting.itemCount(1), "1 товар")
        XCTAssertEqual(DashboardFormatting.itemCount(2), "2 товара")
        XCTAssertEqual(DashboardFormatting.itemCount(5), "5 товаров")
        XCTAssertEqual(DashboardFormatting.itemCount(11), "11 товаров")
        XCTAssertEqual(DashboardFormatting.itemCount(21), "21 товар")
    }
}
