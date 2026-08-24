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
        case zeroAmount
    }

    let id: PurchaseItemID
    let name: String
    let category: String
    let amount: Money

    init(id: PurchaseItemID, name: String, category: String, amount: Money) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyName
        }
        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyCategory
        }
        guard amount.minorUnits > 0 else {
            throw ValidationError.zeroAmount
        }

        self.id = id
        self.name = name
        self.category = category
        self.amount = amount
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

    var total: Money {
        switch kind {
        case let .quick(_, amount):
            return amount
        case let .detailed(items):
            return items.dropFirst().reduce(items[0].amount) { partialTotal, item in
                try! partialTotal.adding(item.amount)
            }
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
            kind: .quick(category: category, amount: amount)
        )
    }

    static func detailed(
        id: PurchaseID,
        ownerID: UserID,
        groupID: GroupID?,
        merchant: String,
        items: [PurchaseItem],
        spentAt: Date,
        localDate: Date,
        timeZone: String,
        version: Int64
    ) throws -> Purchase {
        guard let firstItem = items.first else {
            throw ValidationError.emptyDetailedPurchase
        }

        _ = try items.dropFirst().reduce(firstItem.amount) { partialTotal, item in
            try partialTotal.adding(item.amount)
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
            kind: .detailed(items: items)
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
        kind: Kind
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
    }
}

struct PurchaseDraft: Codable, Sendable, Hashable {
    let ownerID: UserID
    let groupID: GroupID?
    let merchant: String
    let spentAt: Date
    let localDate: Date
    let timeZone: String
    let kind: Purchase.Kind
}

