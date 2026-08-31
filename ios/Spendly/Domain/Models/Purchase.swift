import Foundation

struct PurchaseID: RawRepresentable, Codable, Sendable, Hashable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct PurchaseItemID: RawRepresentable, Codable, Sendable, Hashable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct PurchaseItem: Codable, Sendable, Hashable {
    enum ValidationError: Error, Equatable {
        case emptyName
        case emptyCategory
        case invalidQuantity
        case zeroAmount
    }

    let id: PurchaseItemID
    let name: String
    let category: String
    let quantity: Int64
    let unitPrice: Money
    let totalPrice: Money

    var amount: Money {
        totalPrice
    }

    init(id: PurchaseItemID, name: String, category: String, amount: Money) throws {
        try self.init(id: id, name: name, category: category, quantity: 1, unitPrice: amount)
    }

    init(id: PurchaseItemID, name: String, category: String, quantity: Int64 = 1, unitPrice: Money) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyName
        }
        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyCategory
        }
        guard quantity > 0 else {
            throw ValidationError.invalidQuantity
        }
        guard unitPrice.minorUnits > 0 else {
            throw ValidationError.zeroAmount
        }
        let multiplied = unitPrice.minorUnits.multipliedReportingOverflow(by: quantity)
        guard !multiplied.overflow else {
            throw Money.ValidationError.overflow
        }

        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.totalPrice = try Money(minorUnits: multiplied.partialValue, currencyCode: unitPrice.currencyCode)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case quantity
        case unitPrice
        case totalPrice
        case amount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(PurchaseItemID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let category = try container.decode(String.self, forKey: .category)
        if let unitPrice = try container.decodeIfPresent(Money.self, forKey: .unitPrice) {
            let quantity = try container.decodeIfPresent(Int64.self, forKey: .quantity) ?? 1
            try self.init(id: id, name: name, category: category, quantity: quantity, unitPrice: unitPrice)
        } else {
            let amount = try container.decode(Money.self, forKey: .amount)
            try self.init(id: id, name: name, category: category, amount: amount)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unitPrice, forKey: .unitPrice)
        try container.encode(totalPrice, forKey: .totalPrice)
        try container.encode(totalPrice, forKey: .amount)
    }
}

enum PurchaseDiscountType: String, Codable, Sendable, Hashable {
    case fixed
    case percentage
}

struct PurchaseDiscount: Codable, Sendable, Hashable {
    let type: PurchaseDiscountType
    let value: Int64

    init(type: PurchaseDiscountType, value: Int64) {
        self.type = type
        self.value = value
    }
}

struct Purchase: Codable, Sendable, Hashable {
    enum ValidationError: Error, Equatable {
        case emptyMerchant
        case emptyCategory
        case emptyDetailedPurchase
        case invalidVersion
        case zeroAmount
    }

    enum Kind: Codable, Sendable, Hashable {
        case quick(category: String, amount: Money)
        case detailed(items: [PurchaseItem])
    }

    let id: PurchaseID
    let ownerID: UserID
    let groupID: GroupID?
    let merchant: String
    let spentAt: Date
    let localDate: Date
    let timeZone: String
    let version: Int64
    let kind: Kind
    let deliveryFee: Money
    let discount: PurchaseDiscount?

    var itemsSubtotal: Money {
        switch kind {
        case let .quick(_, amount):
            return amount
        case let .detailed(items):
            return sum(items.map(\.totalPrice))
        }
    }

    var discountAmount: Money {
        switch kind {
        case .quick:
            return zeroMoney(currencyCode: totalCurrencyCode)
        case .detailed:
            guard let discount else {
                return zeroMoney(currencyCode: totalCurrencyCode)
            }

            switch discount.type {
            case .fixed:
                return (try? Money(minorUnits: discount.value, currencyCode: totalCurrencyCode)) ?? zeroMoney(currencyCode: totalCurrencyCode)
            case .percentage:
                let value = itemsSubtotal.minorUnits * discount.value / 100
                return (try? Money(minorUnits: value, currencyCode: totalCurrencyCode)) ?? zeroMoney(currencyCode: totalCurrencyCode)
            }
        }
    }

    var total: Money {
        switch kind {
        case let .quick(_, amount):
            return amount
        case .detailed:
            let beforeDiscount = try! itemsSubtotal.adding(deliveryFee)
            let totalMinorUnits = max(0, beforeDiscount.minorUnits - discountAmount.minorUnits)
            return try! Money(minorUnits: totalMinorUnits, currencyCode: totalCurrencyCode)
        }
    }

    static func quick(
        id: PurchaseID,
        ownerID: UserID,
        groupID: GroupID?,
        merchant: String,
        category: String,
        amount: Money,
        spentAt: Date,
        localDate: Date,
        timeZone: String,
        version: Int64
    ) throws -> Purchase {
        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyCategory
        }
        guard amount.minorUnits > 0 else {
            throw ValidationError.zeroAmount
        }

        return try Purchase(
            id: id,
            ownerID: ownerID,
            groupID: groupID,
            merchant: merchant,
            spentAt: spentAt,
            localDate: localDate,
            timeZone: timeZone,
            version: version,
            kind: .quick(category: category, amount: amount),
            deliveryFee: try Money(minorUnits: 0, currencyCode: amount.currencyCode),
            discount: nil
        )
    }

    static func detailed(
        id: PurchaseID,
        ownerID: UserID,
        groupID: GroupID?,
        merchant: String,
        items: [PurchaseItem],
        deliveryFee: Money? = nil,
        discount: PurchaseDiscount? = nil,
        spentAt: Date,
        localDate: Date,
        timeZone: String,
        version: Int64
    ) throws -> Purchase {
        guard let firstItem = items.first else {
            throw ValidationError.emptyDetailedPurchase
        }

        let subtotal = try items.dropFirst().reduce(firstItem.totalPrice) { partialTotal, item in
            try partialTotal.adding(item.totalPrice)
        }
        let resolvedDeliveryFee = try deliveryFee ?? Money(minorUnits: 0, currencyCode: firstItem.totalPrice.currencyCode)
        _ = try subtotal.adding(resolvedDeliveryFee)
        if let discount {
            guard discount.value >= 0 else {
                throw ValidationError.zeroAmount
            }
            if discount.type == .percentage {
                guard discount.value <= 100 else {
                    throw ValidationError.zeroAmount
                }
            } else {
                _ = try Money(minorUnits: discount.value, currencyCode: firstItem.totalPrice.currencyCode)
            }
        }

        return try Purchase(
            id: id,
            ownerID: ownerID,
            groupID: groupID,
            merchant: merchant,
            spentAt: spentAt,
            localDate: localDate,
            timeZone: timeZone,
            version: version,
            kind: .detailed(items: items),
            deliveryFee: resolvedDeliveryFee,
            discount: discount
        )
    }

    private init(
        id: PurchaseID,
        ownerID: UserID,
        groupID: GroupID?,
        merchant: String,
        spentAt: Date,
        localDate: Date,
        timeZone: String,
        version: Int64,
        kind: Kind,
        deliveryFee: Money,
        discount: PurchaseDiscount?
    ) throws {
        guard !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyMerchant
        }
        guard version > 0 else {
            throw ValidationError.invalidVersion
        }

        self.id = id
        self.ownerID = ownerID
        self.groupID = groupID
        self.merchant = merchant
        self.spentAt = spentAt
        self.localDate = localDate
        self.timeZone = timeZone
        self.version = version
        self.kind = kind
        self.deliveryFee = deliveryFee
        self.discount = discount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case ownerID
        case groupID
        case merchant
        case spentAt
        case localDate
        case timeZone
        case version
        case kind
        case deliveryFee
        case discount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(PurchaseID.self, forKey: .id)
        let ownerID = try container.decode(UserID.self, forKey: .ownerID)
        let groupID = try container.decodeIfPresent(GroupID.self, forKey: .groupID)
        let merchant = try container.decode(String.self, forKey: .merchant)
        let spentAt = try container.decode(Date.self, forKey: .spentAt)
        let localDate = try container.decode(Date.self, forKey: .localDate)
        let timeZone = try container.decode(String.self, forKey: .timeZone)
        let version = try container.decode(Int64.self, forKey: .version)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let fallbackCurrencyCode: String
        switch kind {
        case let .quick(_, amount):
            fallbackCurrencyCode = amount.currencyCode
        case let .detailed(items):
            fallbackCurrencyCode = items.first?.totalPrice.currencyCode ?? "RUB"
        }
        let deliveryFee = try container.decodeIfPresent(Money.self, forKey: .deliveryFee) ?? Money(minorUnits: 0, currencyCode: fallbackCurrencyCode)
        let discount = try container.decodeIfPresent(PurchaseDiscount.self, forKey: .discount)
        try self.init(
            id: id, ownerID: ownerID, groupID: groupID, merchant: merchant,
            spentAt: spentAt, localDate: localDate, timeZone: timeZone,
            version: version, kind: kind, deliveryFee: deliveryFee, discount: discount
        )
    }

    private var totalCurrencyCode: String {
        switch kind {
        case let .quick(_, amount):
            return amount.currencyCode
        case let .detailed(items):
            return items.first?.totalPrice.currencyCode ?? deliveryFee.currencyCode
        }
    }

    private func sum(_ values: [Money]) -> Money {
        guard let first = values.first else {
            return zeroMoney(currencyCode: deliveryFee.currencyCode)
        }

        return values.dropFirst().reduce(first) { partialTotal, value in
            try! partialTotal.adding(value)
        }
    }

    private func zeroMoney(currencyCode: String) -> Money {
        try! Money(minorUnits: 0, currencyCode: currencyCode)
    }
}

struct PurchaseDraft: Codable, Sendable, Hashable {
    let id: PurchaseID
    let ownerID: UserID
    let groupID: GroupID?
    let merchant: String
    let spentAt: Date
    let localDate: Date
    let timeZone: String
    let kind: Purchase.Kind
    let deliveryFee: Money
    let discount: PurchaseDiscount?

    init(
        id: PurchaseID,
        ownerID: UserID,
        groupID: GroupID?,
        merchant: String,
        spentAt: Date,
        localDate: Date,
        timeZone: String,
        kind: Purchase.Kind,
        deliveryFee: Money? = nil,
        discount: PurchaseDiscount? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.groupID = groupID
        self.merchant = merchant
        self.spentAt = spentAt
        self.localDate = localDate
        self.timeZone = timeZone
        self.kind = kind
        self.deliveryFee = deliveryFee ?? PurchaseDraft.defaultDeliveryFee(for: kind)
        self.discount = discount
    }

    private static func defaultDeliveryFee(for kind: Purchase.Kind) -> Money {
        let currencyCode: String
        switch kind {
        case let .quick(_, amount):
            currencyCode = amount.currencyCode
        case let .detailed(items):
            currencyCode = items.first?.totalPrice.currencyCode ?? "RUB"
        }
        return try! Money(minorUnits: 0, currencyCode: currencyCode)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case ownerID
        case groupID
        case merchant
        case spentAt
        case localDate
        case timeZone
        case kind
        case deliveryFee
        case discount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Purchase.Kind.self, forKey: .kind)
        self.init(
            id: try container.decode(PurchaseID.self, forKey: .id),
            ownerID: try container.decode(UserID.self, forKey: .ownerID),
            groupID: try container.decodeIfPresent(GroupID.self, forKey: .groupID),
            merchant: try container.decode(String.self, forKey: .merchant),
            spentAt: try container.decode(Date.self, forKey: .spentAt),
            localDate: try container.decode(Date.self, forKey: .localDate),
            timeZone: try container.decode(String.self, forKey: .timeZone),
            kind: kind,
            deliveryFee: try container.decodeIfPresent(Money.self, forKey: .deliveryFee),
            discount: try container.decodeIfPresent(PurchaseDiscount.self, forKey: .discount)
        )
    }
}
