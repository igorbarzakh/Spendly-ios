import Observation
import SwiftUI

struct AllTransactionsSection: Identifiable, Equatable {
    let id: Date
    let title: String
    let purchases: [Purchase]

    static let localDateCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func make(
        from purchases: [Purchase],
        now: Date = .now,
        calendar: Calendar = localDateCalendar,
        currentCalendar: Calendar = .current
    ) -> [AllTransactionsSection] {
        let grouped = Dictionary(grouping: purchases) {
            calendar.startOfDay(for: $0.localDate)
        }
        return grouped.keys.sorted(by: >).map { date in
            AllTransactionsSection(
                id: date,
                title: title(for: date, now: now, calendar: calendar, currentCalendar: currentCalendar),
                purchases: grouped[date, default: []].sorted {
                    if $0.spentAt == $1.spentAt {
                        return $0.id.rawValue.uuidString > $1.id.rawValue.uuidString
                    }
                    return $0.spentAt > $1.spentAt
                }
            )
        }
    }

    private static func title(for date: Date, now: Date, calendar: Calendar, currentCalendar: Calendar) -> String {
        let today = localDate(from: now, calendar: currentCalendar)
        if calendar.isDate(date, inSameDayAs: today) {
            return "Сегодня"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? "d MMMM"
            : "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func localDate(from date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return localDateCalendar.date(from: components) ?? date
    }
}

@MainActor
@Observable
final class AllTransactionsModel {
    private(set) var purchases: [Purchase] = []
    private(set) var hasMore = true
    private(set) var isLoading = false
    private(set) var failure: AppFailure?

    private let repository: any PurchaseRepository
    private let context: ExpenseContext
    private let pageSize: Int
    private var nextCursor: String?
    private var didLoadInitialPage = false

    init(
        repository: any PurchaseRepository,
        context: ExpenseContext,
        pageSize: Int = 50
    ) {
        self.repository = repository
        self.context = context
        self.pageSize = pageSize
    }

    func loadInitial() async {
        guard !didLoadInitialPage else { return }
        await loadPage()
    }

    func loadMoreIfNeeded(current purchase: Purchase) async {
        guard hasMore,
              let index = purchases.firstIndex(where: { $0.id == purchase.id }),
              index >= max(0, purchases.count - 5) else {
            return
        }
        await loadPage()
    }

    func retry() async {
        await loadPage()
    }

    func applyUpdatedPurchase(_ purchase: Purchase) {
        guard let index = purchases.firstIndex(where: { $0.id == purchase.id }) else { return }
        purchases[index] = purchase
    }

    func removeDeletedPurchase(id: PurchaseID) {
        purchases.removeAll { $0.id == id }
    }

    private func loadPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let page = try await repository.purchasePage(
                in: context,
                after: nextCursor,
                limit: pageSize
            )
            let existingIDs = Set(purchases.map(\.id))
            purchases.append(contentsOf: page.purchases.filter { !existingIDs.contains($0.id) })
            nextCursor = page.nextCursor
            hasMore = page.hasMore && page.nextCursor != nil
            didLoadInitialPage = true
        } catch is CancellationError {
            return
        } catch {
            failure = error as? AppFailure ?? .unknown
        }
    }
}

struct AllTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AllTransactionsModel
    @State private var selectedPurchase: Purchase?
    private let onAddTransaction: () -> Void
    private let onTransactionsChanged: (PurchaseMutationEvent) -> Void

    init(
        repository: any PurchaseRepository,
        context: ExpenseContext,
        onAddTransaction: @escaping () -> Void = {},
        onTransactionsChanged: @escaping (PurchaseMutationEvent) -> Void = { _ in }
    ) {
        _model = State(initialValue: AllTransactionsModel(repository: repository, context: context))
        self.onAddTransaction = onAddTransaction
        self.onTransactionsChanged = onTransactionsChanged
        self.repository = repository
        self.context = context
    }

    private let repository: any PurchaseRepository
    private let context: ExpenseContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(AppColor.dashboardBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await model.loadInitial()
        }
        .sheet(item: $selectedPurchase) { purchase in
            AddExpenseView(
                repository: repository,
                context: context,
                scope: categoryScope,
                purchase: purchase,
                onSave: { updatedPurchase in
                    model.applyUpdatedPurchase(updatedPurchase)
                    onTransactionsChanged(.updated(from: purchase, to: updatedPurchase))
                },
                onDelete: { purchaseID in
                    model.removeDeletedPurchase(id: purchaseID)
                    onTransactionsChanged(.deleted(purchase))
                }
            )
            .presentationDetents([.large])
        }
    }

    private var categoryScope: AddExpenseCategoryScope {
        switch context {
        case .personal: .personal
        case .group: .family
        }
    }

    private var header: some View {
        ZStack {
            Text("Все операции")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColor.dashboardPrimaryText)

            HStack {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppColor.dashboardPrimaryText)
                        .frame(width: 44, height: 44)
                        .background(AppColor.dashboardSurface, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var content: some View {
        if model.purchases.isEmpty, model.isLoading {
            Spacer()
            ProgressView()
                .tint(AppColor.dashboardAccent)
            Spacer()
        } else if model.purchases.isEmpty, model.failure != nil {
            ContentUnavailableView {
                Label("Не удалось загрузить операции", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            } description: {
                Text("Проверьте соединение и попробуйте ещё раз.")
            } actions: {
                Button("Повторить") {
                    Task { await model.retry() }
                }
            }
        } else if model.purchases.isEmpty {
            emptyState
        } else {
            transactionList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "receipt.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppColor.dashboardAccent)
                .frame(width: 72, height: 72)
                .background(
                    AppColor.dashboardAccentSoft,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .accessibilityHidden(true)

            Text("Операций пока нет")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColor.dashboardPrimaryText)
                .padding(.top, 20)

            Text("Добавьте свою первую транзакцию")
                .font(.subheadline)
                .foregroundStyle(AppColor.dashboardSecondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 290)
                .padding(.top, 8)

            Button(action: onAddTransaction) {
                Label("Добавить транзакцию", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(height: 50)
                    .padding(.horizontal, 20)
                    .background(
                        AppColor.dashboardAccent,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .shadow(color: AppColor.dashboardAccent.opacity(0.18), radius: 12, x: 0, y: 6)
            .padding(.top, 24)
            .accessibilityHint("Открывает форму создания расхода")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 44)
    }

    private var transactionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(AllTransactionsSection.make(from: model.purchases)) { section in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(AppColor.dashboardPrimaryText)
                            .padding(.horizontal, 4)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(section.purchases.enumerated()), id: \.element.id) { index, purchase in
                                Button {
                                    guard case .quick = purchase.kind else { return }
                                    selectedPurchase = purchase
                                } label: {
                                    PurchaseTransactionRow(purchase: purchase)
                                }
                                .buttonStyle(.plain)
                                .disabled(!purchase.isQuick)
                                .task(id: purchase.id) {
                                    await model.loadMoreIfNeeded(current: purchase)
                                }

                                if index < section.purchases.count - 1 {
                                    Divider()
                                        .overlay(AppColor.dashboardSeparator.opacity(0.45))
                                        .padding(.leading, 54)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            AppColor.dashboardSurface,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                        .shadow(color: Color.black.opacity(0.055), radius: 24, x: 0, y: 10)
                    }
                }

                if model.isLoading {
                    ProgressView()
                        .tint(AppColor.dashboardAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if model.failure != nil {
                    Button("Не удалось загрузить ещё. Повторить") {
                        Task { await model.retry() }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColor.dashboardAccent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
    }
}

private extension Purchase {
    var isQuick: Bool {
        guard case .quick = kind else { return false }
        return true
    }
}

private struct PurchaseTransactionRow: View {
    let purchase: Purchase

    private var categoryName: String {
        switch purchase.kind {
        case let .quick(category, _):
            return category
        case let .detailed(items):
            let categories = Set(items.map(\.category))
            return categories.count == 1 ? (categories.first ?? "Покупки") : "Покупки"
        }
    }

    private var category: AddExpenseCategory {
        AddExpenseCategoryStore.defaultCategories.first { $0.name == categoryName }
            ?? AddExpenseCategory(id: "transaction-category", name: categoryName, kind: .userCreated)
    }

    private var detailsText: String {
        return switch purchase.kind {
        case .quick:
            categoryName
        case let .detailed(items):
            "\(categoryName) · \(DashboardFormatting.itemCount(items.count))"
        }
    }

    var body: some View {
        TransactionListRow(
            merchant: purchase.merchant,
            details: detailsText,
            amountMinorUnits: purchase.total.minorUnits,
            symbolName: category.symbolName,
            tint: category.tint
        )
    }
}
