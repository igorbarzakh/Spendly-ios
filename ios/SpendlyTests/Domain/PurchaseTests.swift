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

    func testDetailedPurchaseTotalIncludesDeliveryAndFixedDiscount() throws {
        let purchase = try Purchase.detailed(
            id: PurchaseID(rawValue: UUID()),
            ownerID: ownerID,
            groupID: nil,
            merchant: "Магазин",
            items: cartItems(),
            deliveryFee: Money(minorUnits: 9_900, currencyCode: "RUB"),
            discount: PurchaseDiscount(type: .fixed, value: 5_000),
            spentAt: spentAt,
            localDate: spentAt,
            timeZone: "Europe/Moscow",
            version: 1
        )

        XCTAssertEqual(purchase.itemsSubtotal.minorUnits, 43_500)
        XCTAssertEqual(purchase.discountAmount.minorUnits, 5_000)
        XCTAssertEqual(purchase.total.minorUnits, 48_400)
    }

    func testDetailedPurchasePercentageDiscountUsesItemsSubtotalOnly() throws {
        let purchase = try Purchase.detailed(
            id: PurchaseID(rawValue: UUID()),
            ownerID: ownerID,
            groupID: nil,
            merchant: "Магазин",
            items: cartItems(),
            deliveryFee: Money(minorUnits: 9_900, currencyCode: "RUB"),
            discount: PurchaseDiscount(type: .percentage, value: 10),
            spentAt: spentAt,
            localDate: spentAt,
            timeZone: "Europe/Moscow",
            version: 1
        )

        XCTAssertEqual(purchase.discountAmount.minorUnits, 4_350)
        XCTAssertEqual(purchase.total.minorUnits, 49_050)
    }

    func testDetailedPurchaseTotalIsClampedToZero() throws {
        let purchase = try Purchase.detailed(
            id: PurchaseID(rawValue: UUID()),
            ownerID: ownerID,
            groupID: nil,
            merchant: "Магазин",
            items: cartItems(),
            discount: PurchaseDiscount(type: .fixed, value: 99_999),
            spentAt: spentAt,
            localDate: spentAt,
            timeZone: "Europe/Moscow",
            version: 1
        )

        XCTAssertEqual(purchase.total.minorUnits, 0)
    }

    func testPurchaseItemTotalIsQuantityTimesUnitPrice() throws {
        let item = try PurchaseItem(
            id: PurchaseItemID(rawValue: UUID()),
            name: "Молоко",
            category: "Продукты",
            quantity: 2,
            unitPrice: Money(minorUnits: 9_500, currencyCode: "RUB")
        )

        XCTAssertEqual(item.totalPrice.minorUnits, 19_000)
        XCTAssertEqual(item.amount, item.totalPrice)
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

    private func cartItems() throws -> [PurchaseItem] {
        [
            try PurchaseItem(
                id: PurchaseItemID(rawValue: UUID()),
                name: "Молоко",
                category: "Продукты",
                quantity: 2,
                unitPrice: Money(minorUnits: 9_500, currencyCode: "RUB")
            ),
            try PurchaseItem(
                id: PurchaseItemID(rawValue: UUID()),
                name: "Хлеб",
                category: "Продукты",
                quantity: 1,
                unitPrice: Money(minorUnits: 8_900, currencyCode: "RUB")
            ),
            try PurchaseItem(
                id: PurchaseItemID(rawValue: UUID()),
                name: "Бананы",
                category: "Продукты",
                quantity: 1,
                unitPrice: Money(minorUnits: 15_600, currencyCode: "RUB")
            ),
        ]
    }
}
