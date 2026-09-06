import SwiftUI

struct DashboardView: View {
    let onAddTransaction: () -> Void

    @State private var selectedPeriod: DashboardPeriod = .month
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 44

    private var snapshot: DashboardSnapshot {
        DashboardSamples.snapshot(for: selectedPeriod)
    }

    init(onAddTransaction: @escaping () -> Void = {}) {
        self.onAddTransaction = onAddTransaction
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
        .animation(.snappy(duration: 0.28), value: selectedPeriod)
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
            Text(snapshot.period.summaryTitle)
                .font(.subheadline)
                .foregroundStyle(AppColor.dashboardSecondaryText)

            Text(DashboardFormatting.amount(snapshot.totalMinorUnits))
                .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.dashboardPrimaryText)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .contentTransition(.numericText())
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
                spentMinorUnits: DashboardSamples.currentMonthTotalMinorUnits,
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

    private var recentTransactions: some View {
        let transactions = snapshot.recentTransactions(limit: 5)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Последние операции")
                    .font(.headline)
                    .foregroundStyle(AppColor.dashboardPrimaryText)

                Spacer()

                Button("Смотреть все") {}
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColor.dashboardAccent)
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 0) {
                ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                    DashboardTransactionRow(transaction: transaction)

                    if index < transactions.count - 1 {
                        Divider()
                            .overlay(AppColor.dashboardSeparator.opacity(0.45))
                            .padding(.leading, 54)
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
        HStack(spacing: 12) {
            Image(systemName: transaction.category.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.category.tint)
                .frame(width: 42, height: 42)
                .background(transaction.category.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.dashboardPrimaryText)
                    .lineLimit(1)

                Text(transaction.detailsText)
                    .font(.footnote)
                    .foregroundStyle(AppColor.dashboardSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(DashboardFormatting.expense(transaction.amountMinorUnits))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.dashboardPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8)
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
        switch self {
        case .groceries:
            Color(red: 0.12, green: 0.62, blue: 0.26)
        case .transport:
            Color(red: 0.92, green: 0.57, blue: 0.05)
        case .dining:
            Color(red: 0.64, green: 0.39, blue: 0.25)
        case .subscriptions:
            Color(red: 0.08, green: 0.65, blue: 0.46)
        case .shopping:
            Color(red: 0.24, green: 0.43, blue: 0.91)
        }
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
