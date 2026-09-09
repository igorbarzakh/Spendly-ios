import SwiftUI

struct DashboardView: View {
    let refreshToken: UUID
    let purchaseMutationEvent: PurchaseMutationEvent?
    let onAddTransaction: () -> Void
    let onViewAllTransactions: () -> Void
    let onEditTransaction: (Purchase) -> Void

    @State private var summaryModel: DashboardSummaryModel
    @State private var monthlyBudgetModel: DashboardMonthlyBudgetModel
    @State private var recentTransactionsModel: DashboardRecentTransactionsModel
    @State private var selectedPeriod: DashboardPeriod = DashboardPeriod.defaultSelection
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 44

    init(
        repository: any PurchaseRepository = DashboardPreviewPurchaseRepository(),
        statisticsRepository: any StatisticsRepository = DashboardPreviewStatisticsRepository(),
        context: ExpenseContext = .personal(UserID(rawValue: UUID())),
        refreshToken: UUID = UUID(),
        purchaseMutationEvent: PurchaseMutationEvent? = nil,
        onAddTransaction: @escaping () -> Void = {},
        onViewAllTransactions: @escaping () -> Void = {},
        onEditTransaction: @escaping (Purchase) -> Void = { _ in }
    ) {
        _summaryModel = State(initialValue: DashboardSummaryModel(
            repository: repository,
            context: context
        ))
        _monthlyBudgetModel = State(initialValue: DashboardMonthlyBudgetModel(
            repository: repository,
            context: context
        ))
        _recentTransactionsModel = State(initialValue: DashboardRecentTransactionsModel(
            repository: repository,
            context: context
        ))
        self.refreshToken = refreshToken
        self.purchaseMutationEvent = purchaseMutationEvent
        self.onAddTransaction = onAddTransaction
        self.onViewAllTransactions = onViewAllTransactions
        self.onEditTransaction = onEditTransaction
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                periodPicker
                summaryCard
                addTransactionButton
                recentTransactions
                    .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(AppColor.dashboardBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 12)
        }
        .task(id: refreshToken) {
            await recentTransactionsModel.refresh()
            await summaryModel.load(period: selectedPeriod)
        }
        .task(id: refreshToken) {
            await monthlyBudgetModel.load()
        }
        .task(id: selectedPeriod) {
            await summaryModel.load(period: selectedPeriod)
        }
        .onChange(of: purchaseMutationEvent) { _, event in
            guard let event else { return }

            if let current = event.current {
                recentTransactionsModel.applyUpdatedPurchase(current)
                summaryModel.applyUpdate(from: event.previous, to: current, period: selectedPeriod)
                monthlyBudgetModel.applyUpdate(from: event.previous, to: current)
            } else {
                recentTransactionsModel.removeDeletedPurchase(id: event.previous.id)
                summaryModel.applyDeletion(event.previous, period: selectedPeriod)
                monthlyBudgetModel.applyDeletion(event.previous)
                Task { await recentTransactionsModel.replenishIfNeeded() }
            }
        }
        .animation(.snappy(duration: 0.28), value: selectedPeriod)
        .animation(.snappy(duration: 0.28), value: summaryModel.totalMinorUnits)
    }

    private var periodPicker: some View {
        Picker("Период расходов", selection: $selectedPeriod) {
            ForEach(DashboardPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
        .accessibilityHint("Изменяет сводку расходов")
    }

    private var summary: some View {
        VStack(spacing: 5) {
            Text(selectedPeriod.summaryTitle)
                .font(.subheadline)
                .foregroundStyle(AppColor.dashboardSecondaryText)

            Text(DashboardFormatting.amount(summaryModel.totalMinorUnits))
                .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.dashboardPrimaryText)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .contentTransition(.numericText())

            if summaryModel.failure != nil {
                Text("Не удалось обновить сумму")
                    .font(.caption)
                    .foregroundStyle(AppColor.dashboardSecondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var summaryCard: some View {
        VStack(spacing: 30) {
            summary
            monthlyLimit
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(AppColor.dashboardSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .dashboardCardShadow()
    }

    private var monthlyLimit: some View {
        DashboardBudgetProgressView(
            progress: DashboardBudgetProgress(
                spentMinorUnits: monthlyBudgetModel.spentMinorUnits,
                limitMinorUnits: DashboardSamples.currentMonthLimitMinorUnits
            )
        )
    }

    private var addTransactionButton: some View {
        Button(action: onAddTransaction) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppColor.dashboardAccent)
                    .frame(width: 42, height: 42)
                    .background(AppColor.dashboardAccentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Добавить транзакцию")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.dashboardPrimaryText)

                    Text("Быстрая запись расхода")
                        .font(.footnote)
                        .foregroundStyle(AppColor.dashboardSecondaryText)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.dashboardSecondaryText)
                    .padding(.trailing, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.dashboardSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(DashboardCardButtonStyle())
        .accessibilityHint("Открывает форму создания расхода")
    }

    @ViewBuilder
    private var recentTransactions: some View {
        let transactions = recentTransactionsModel.transactions

        if !transactions.isEmpty || recentTransactionsModel.isLoading || recentTransactionsModel.failure != nil {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Последние операции")
                        .font(.headline)
                        .foregroundStyle(AppColor.dashboardPrimaryText)

                    Spacer()

                    Button("Смотреть все", action: onViewAllTransactions)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppColor.dashboardAccent)
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    if transactions.isEmpty, recentTransactionsModel.isLoading {
                        ProgressView()
                            .tint(AppColor.dashboardAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                    } else if transactions.isEmpty, recentTransactionsModel.failure != nil {
                        Button("Не удалось загрузить. Повторить") {
                            Task { await recentTransactionsModel.retry() }
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppColor.dashboardAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                                Button {
                                    guard let purchase = transaction.purchase else { return }
                                    onEditTransaction(purchase)
                                } label: {
                                    DashboardTransactionRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                                .disabled(transaction.purchase == nil)

                                if index < transactions.count - 1 {
                                    Divider()
                                        .overlay(AppColor.dashboardSeparator.opacity(0.45))
                                        .padding(.leading, 54)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColor.dashboardSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .dashboardCardShadow()
            }
        }
    }
}

private struct DashboardBudgetProgressView: View {
    let progress: DashboardBudgetProgress

    private var accent: Color {
        progress.isOverLimit ? .red : AppColor.dashboardAccent
    }

    private var statusText: String {
        if progress.isOverLimit {
            return "Превышение на \(DashboardFormatting.amount(progress.overageMinorUnits))"
        }
        return "Осталось \(DashboardFormatting.amount(progress.remainingMinorUnits))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Лимит месяца")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.dashboardPrimaryText)

                Spacer(minLength: 8)

                Text(DashboardFormatting.amount(progress.limitMinorUnits))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.dashboardPrimaryText)
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.dashboardProgressTrack)

                    Capsule()
                        .fill(accent)
                        .frame(width: proxy.size.width * progress.fraction)
                        .animation(.easeInOut(duration: 0.45), value: progress.fraction)
                }
            }
            .frame(height: 7)

            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(progress.isOverLimit ? accent : AppColor.dashboardSecondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Месячный лимит \(DashboardFormatting.amount(progress.limitMinorUnits)). \(statusText)"
        )
    }
}

private struct DashboardTransactionRow: View {
    let transaction: DashboardTransaction

    var body: some View {
        TransactionListRow(
            merchant: transaction.merchant,
            details: transaction.detailsText,
            amountMinorUnits: transaction.amountMinorUnits,
            symbolName: transaction.category.symbolName,
            tint: transaction.category.tint
        )
    }
}

struct TransactionListRow: View {
    let merchant: String
    let details: String
    let amountMinorUnits: Int64
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(merchant)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.dashboardPrimaryText)
                    .lineLimit(1)

                Text(details)
                    .font(.footnote)
                    .foregroundStyle(AppColor.dashboardSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(DashboardFormatting.expense(amountMinorUnits))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.dashboardPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .dashboardCardShadow()
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private extension DashboardCategory {
    var tint: Color {
        Color(hex: tintHex)
    }

    var background: Color {
        tint.opacity(0.12)
    }
}

private extension View {
    func dashboardCardShadow() -> some View {
        shadow(color: Color.black.opacity(0.055), radius: 24, x: 0, y: 10)
    }
}

#Preview {
    DashboardView()
}

private actor DashboardPreviewPurchaseRepository: PurchaseRepository {
    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase] { [] }

    func purchasePage(in context: ExpenseContext, after cursor: String?, limit: Int) async throws -> PurchasePage {
        PurchasePage(purchases: [], nextCursor: nil, hasMore: false)
    }

    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase { throw AppFailure.unknown }
    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase { throw AppFailure.unknown }
    func delete(id: PurchaseID, expectedVersion: Int64) async throws {}
}

private actor DashboardPreviewStatisticsRepository: StatisticsRepository {
    func statistics(in context: ExpenseContext, interval: DateInterval) async throws -> StatisticsSnapshot {
        StatisticsSnapshot(totalMinor: 0, byDay: [:], byCategory: [:])
    }
}
