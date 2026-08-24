import Foundation

enum RepositoryMapping {
    private static func localDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func purchase(from dto: PurchaseDTO) throws -> Purchase {
        guard let ownerID = dto.ownerId, let version = dto.version,
              let localDate = localDateFormatter().date(from: dto.localDate) else {
            throw APIError.decoding
        }
        if dto.kind == "quick", let category = dto.category, let amount = dto.amountMinor {
            return try Purchase.quick(
                id: PurchaseID(rawValue: dto.id), ownerID: UserID(rawValue: ownerID),
                groupID: dto.groupId.map(GroupID.init(rawValue:)), merchant: dto.merchant,
                category: category, amount: Money(minorUnits: amount, currencyCode: dto.currencyCode),
                spentAt: dto.spentAt, localDate: localDate, timeZone: dto.timeZone, version: version
            )
        }
        guard dto.kind == "detailed" else { throw APIError.decoding }
        let items = try dto.items.sorted { $0.position < $1.position }.map {
            try PurchaseItem(
                id: PurchaseItemID(rawValue: $0.id), name: $0.name, category: $0.category,
                amount: Money(minorUnits: $0.amountMinor, currencyCode: dto.currencyCode)
            )
        }
        return try Purchase.detailed(
            id: PurchaseID(rawValue: dto.id), ownerID: UserID(rawValue: ownerID),
            groupID: dto.groupId.map(GroupID.init(rawValue:)), merchant: dto.merchant,
            items: items, spentAt: dto.spentAt, localDate: localDate,
            timeZone: dto.timeZone, version: version
        )
    }

    static func dto(from draft: PurchaseDraft) -> PurchaseDraftDTO {
        let category: String?
        let amount: Int64?
        let currency: String
        let items: [PurchaseItemDraftDTO]
        let kind: String
        switch draft.kind {
        case let .quick(value, money):
            kind = "quick"; category = value; amount = money.minorUnits
            currency = money.currencyCode; items = []
        case let .detailed(values):
            kind = "detailed"; category = nil; amount = nil
            currency = values.first?.amount.currencyCode ?? "RUB"
            items = values.enumerated().map { index, item in
                PurchaseItemDraftDTO(
                    id: item.id.rawValue, position: index, name: item.name,
                    category: item.category, amountMinor: item.amount.minorUnits
                )
            }
        }
        return PurchaseDraftDTO(
            id: draft.id.rawValue, groupId: draft.groupID?.rawValue, kind: kind,
            merchant: draft.merchant, category: category, amountMinor: amount,
            currencyCode: currency, spentAt: draft.spentAt,
            localDate: localDateFormatter().string(from: draft.localDate),
            timeZone: draft.timeZone, items: items
        )
    }

    static func dto(from purchase: Purchase) -> PurchaseDTO {
        makeDTO(
            id: purchase.id, ownerID: purchase.ownerID, groupID: purchase.groupID,
            merchant: purchase.merchant, spentAt: purchase.spentAt, localDate: purchase.localDate,
            timeZone: purchase.timeZone, version: purchase.version, kind: purchase.kind
        )
    }

    static func optimisticPurchase(from draft: PurchaseDraft) throws -> Purchase {
        switch draft.kind {
        case let .quick(category, amount):
            return try Purchase.quick(
                id: draft.id, ownerID: draft.ownerID, groupID: draft.groupID,
                merchant: draft.merchant, category: category, amount: amount,
                spentAt: draft.spentAt, localDate: draft.localDate,
                timeZone: draft.timeZone, version: 1
            )
        case let .detailed(items):
            return try Purchase.detailed(
                id: draft.id, ownerID: draft.ownerID, groupID: draft.groupID,
                merchant: draft.merchant, items: items, spentAt: draft.spentAt,
                localDate: draft.localDate, timeZone: draft.timeZone, version: 1
            )
        }
    }

    static func group(from dto: GroupDTO) -> Group {
        Group(
            id: GroupID(rawValue: dto.id), name: dto.name, ownerID: UserID(rawValue: dto.ownerId),
            archivedAt: dto.archivedAt, createdAt: dto.createdAt, updatedAt: dto.updatedAt
        )
    }

    static func failure(from error: Error) -> Error {
        guard let apiError = error as? APIError else { return error }
        switch apiError {
        case .network: return AppFailure.network
        case let .server(status, code, _, _):
            switch (status, code) {
            case (401, _): return AppFailure.unauthenticated
            case (403, _): return AppFailure.forbidden
            case (404, _): return AppFailure.notFound
            case (409, _): return AppFailure.conflict
            case (429, _): return AppFailure.rateLimited(retryAfter: nil)
            case (400, _), (422, _): return AppFailure.validation(fields: [:])
            case (500..., _): return AppFailure.server
            default: return AppFailure.unknown
            }
        default: return AppFailure.unknown
        }
    }

    static func queryItems(context: ExpenseContext, interval: DateInterval) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: interval.start)),
            URLQueryItem(name: "to", value: ISO8601DateFormatter().string(from: interval.end))
        ]
        if case let .group(groupID) = context {
            items.append(URLQueryItem(name: "group_id", value: groupID.rawValue.uuidString.lowercased()))
        }
        return items
    }

    private static func makeDTO(
        id: PurchaseID, ownerID: UserID, groupID: GroupID?, merchant: String,
        spentAt: Date, localDate: Date, timeZone: String, version: Int64?, kind: Purchase.Kind
    ) -> PurchaseDTO {
        let category: String?
        let amount: Int64?
        let currency: String
        let items: [PurchaseItemDTO]
        switch kind {
        case let .quick(value, money):
            category = value; amount = money.minorUnits; currency = money.currencyCode; items = []
        case let .detailed(values):
            category = nil; amount = nil; currency = values.first?.amount.currencyCode ?? "RUB"
            items = values.enumerated().map { index, item in
                PurchaseItemDTO(id: item.id.rawValue, position: index, name: item.name, category: item.category, amountMinor: item.amount.minorUnits, createdAt: nil, updatedAt: nil)
            }
        }
        return PurchaseDTO(
            id: id.rawValue, groupId: groupID?.rawValue, kind: kindName(kind), merchant: merchant,
            category: category, amountMinor: amount, currencyCode: currency, spentAt: spentAt,
            localDate: localDateFormatter().string(from: localDate), timeZone: timeZone, items: items,
            ownerId: ownerID.rawValue, version: version, totalAmountMinor: nil,
            createdAt: nil, updatedAt: nil, deletedAt: nil
        )
    }

    private static func kindName(_ kind: Purchase.Kind) -> String {
        switch kind { case .quick: "quick"; case .detailed: "detailed" }
    }
}
