import SwiftUI

struct ExpensesHomeView: View {
    let onSignOut: () -> Void

    @State private var selectedTab: SpendlyTab = .expenses
    @State private var isAddExpensePresented = false

    init(onSignOut: @escaping () -> Void = {}) {
        self.onSignOut = onSignOut
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView {
                    isAddExpensePresented = true
                }
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
    ExpensesHomeView()
}
