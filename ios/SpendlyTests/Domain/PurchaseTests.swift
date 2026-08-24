import XCTest
@testable import Spendly

final class PurchaseTests: XCTestCase {
    private let ownerID = UserID(rawValue: UUID())
    private let spentAt = Date(timeIntervalSince1970: 1_724_501_800)

    func testQuickPurchaseTotalUsesEnteredAmount() throws {
        let amount = try Money(minorUnits: 35_500, currencyCode: "RUB")
        let purchase = try Purchase.quick(
            id: PurchaseID(rawValue: UUID()),
            ownerID: ownerID,
            groupID: nil,
            merchant: "Кофейня",
            category: "Кафе",
            amount: amount,
            spentAt: spentAt,
            localDate: spentAt,
            timeZone: "Europe/Moscow",
            version: 1
        )

        XCTAssertEqual(purchase.total, amount)
    }

    func testDetailedPurchaseTotalIsDerivedFromItems() throws {
        let purchase = try Purchase.detailed(
            id: PurchaseID(rawValue: UUID()),
            ownerID: ownerID,
            groupID: nil,
            merchant: "Магазин",
            items: [
                try PurchaseItem(
                    id: PurchaseItemID(rawValue: UUID()),
                    name: "Продукты",
                    category: "Еда",
                    amount: Money(minorUnits: 35_500, currencyCode: "RUB")
                ),
                try PurchaseItem(
                    id: PurchaseItemID(rawValue: UUID()),
                    name: "Доставка",
                    category: "Доставка",
                    amount: Money(minorUnits: 12_900, currencyCode: "RUB")
                ),
            ],
            spentAt: spentAt,
            localDate: spentAt,
            timeZone: "Europe/Moscow",
            version: 1
        )

        XCTAssertEqual(purchase.total.minorUnits, 48_400)
    }

    func testDetailedPurchaseRejectsEmptyItems() {
        XCTAssertThrowsError(
            try Purchase.detailed(
                id: PurchaseID(rawValue: UUID()),
                ownerID: ownerID,
                groupID: nil,
                merchant: "Магазин",
                items: [],
                spentAt: spentAt,
                localDate: spentAt,
                timeZone: "Europe/Moscow",
                version: 1
            )
        ) { error in
            XCTAssertEqual(error as? Purchase.ValidationError, .emptyDetailedPurchase)
        }
    }

    func testDetailedPurchaseRejectsOverflowingTotal() throws {
        let items = [
            try PurchaseItem(
                id: PurchaseItemID(rawValue: UUID()),
                name: "Первая позиция",
                category: "Другое",
                amount: Money(minorUnits: .max, currencyCode: "RUB")
            ),
            try PurchaseItem(
                id: PurchaseItemID(rawValue: UUID()),
                name: "Вторая позиция",
                category: "Другое",
                amount: Money(minorUnits: 1, currencyCode: "RUB")
            ),
        ]

        XCTAssertThrowsError(
            try Purchase.detailed(
                id: PurchaseID(rawValue: UUID()),
                ownerID: ownerID,
                groupID: nil,
                merchant: "Магазин",
                items: items,
                spentAt: spentAt,
                localDate: spentAt,
                timeZone: "Europe/Moscow",
                version: 1
            )
        ) { error in
            XCTAssertEqual(error as? Money.ValidationError, .overflow)
        }
    }
}

