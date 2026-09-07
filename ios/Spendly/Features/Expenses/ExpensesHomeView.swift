import SwiftUI

struct ExpensesHomeView: View {
    let purchaseRepository: any PurchaseRepository
    let expenseContext: ExpenseContext
    let onSignOut: () -> Void

    @State private var selectedTab: SpendlyTab = .expenses
    @State private var isAddExpensePresented = false
    @State private var isAllTransactionsPresented = false
    @State private var shouldAddExpenseAfterClosingTransactions = false

    init(
        purchaseRepository: any PurchaseRepository,
        expenseContext: ExpenseContext,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.purchaseRepository = purchaseRepository
        self.expenseContext = expenseContext
        self.onSignOut = onSignOut
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    onAddTransaction: { isAddExpensePresented = true },
                    onViewAllTransactions: { isAllTransactionsPresented = true }
                )
            }
            .tag(SpendlyTab.expenses)
            .tabItem {
                Label("Расходы", systemImage: "receipt")
            }

            PlaceholderTabView(title: "Статистика", systemImage: "chart.bar")
                .tag(SpendlyTab.statistics)
                .tabItem {
                    Label("Статистика", systemImage: "chart.bar")
                }

            PlaceholderTabView(title: "Группы", systemImage: "person.2")
                .tag(SpendlyTab.groups)
                .tabItem {
                    Label("Группы", systemImage: "person.2")
                }

            NavigationStack {
                PlaceholderContent(title: "Профиль", systemImage: "person.crop.circle")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Выйти", action: onSignOut)
                        }
                    }
            }
            .tag(SpendlyTab.profile)
            .tabItem {
                Label("Профиль", systemImage: "person.crop.circle")
            }
        }
        .tint(AppColor.blue)
        .sheet(isPresented: $isAddExpensePresented) {
            AddExpenseView(scope: .personal) { _ in
                isAddExpensePresented = false
            }
            .presentationDetents([.large])
        }
        .fullScreenCover(
            isPresented: $isAllTransactionsPresented,
            onDismiss: {
                guard shouldAddExpenseAfterClosingTransactions else { return }
                shouldAddExpenseAfterClosingTransactions = false
                isAddExpensePresented = true
            }
        ) {
            AllTransactionsView(
                repository: purchaseRepository,
                context: expenseContext,
                onAddTransaction: {
                    shouldAddExpenseAfterClosingTransactions = true
                    isAllTransactionsPresented = false
                }
            )
        }
    }
}

private struct PlaceholderTabView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            PlaceholderContent(title: title, systemImage: systemImage)
        }
    }
}

private struct PlaceholderContent: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text("Экран будет добавлен позже.")
        )
        .navigationTitle(title)
    }
}

private enum SpendlyTab: Hashable {
    case expenses
    case statistics
    case groups
    case profile
}

#Preview {
    ExpensesHomeView(
        purchaseRepository: PreviewPurchaseRepository(),
        expenseContext: .personal(UserID(rawValue: UUID()))
    )
}

private actor PreviewPurchaseRepository: PurchaseRepository {
    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase] { [] }
    func purchasePage(in context: ExpenseContext, after cursor: String?, limit: Int) async throws -> PurchasePage {
        PurchasePage(purchases: [], nextCursor: nil, hasMore: false)
    }
    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase { throw AppFailure.unknown }
    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase { throw AppFailure.unknown }
    func delete(id: PurchaseID, expectedVersion: Int64) async throws {}
}
