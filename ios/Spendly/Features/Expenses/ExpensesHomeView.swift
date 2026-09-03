import SwiftUI
import UIKit

private enum ExpensesLayout {
    static let horizontalPadding: CGFloat = 20
    static let separatorColor = AppColor.border
}

private enum ExpenseScope: String, CaseIterable {
    case personal = "Мои расходы"
    case family = "Семейные расходы"
}

struct ExpensesHomeView: View {
    let onSignOut: () -> Void

    @State private var selectedTab: SpendlyTab = .expenses

    init(onSignOut: @escaping () -> Void = {}) {
        self.onSignOut = onSignOut
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ExpensesContentView()
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
    }
}

private struct ExpensesContentView: View {
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedExpense: ExpenseListItem?
    @State private var selectedScope: ExpenseScope = .personal
    @State private var isMonthPickerPresented = false
    @State private var isAddExpensePresented = false
    @State private var expenseListContainerHeight: CGFloat = 0
    @State private var expenseListContentHeight: CGFloat = 0

    private let expenses = [
        ExpenseListItem(title: "Кино", subtitle: "Личное · Развлечения", amount: MoneyFormatter.rubles(1_000)),
        ExpenseListItem(title: "Ozon Fresh", subtitle: "Семья · 5 товаров", amount: MoneyFormatter.rubles(1_486)),
        ExpenseListItem(title: "Метро", subtitle: "Личное · Транспорт", amount: MoneyFormatter.rubles(169))
    ]

    private var week: ExpenseWeek {
        ExpenseWeek.current(containing: selectedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ExpensesHeader(
                        onMonthTap: { isMonthPickerPresented = true },
                        monthTitle: ExpenseDateText.monthTitle(for: selectedDate),
                        selectedScope: $selectedScope,
                        onAddTap: { isAddExpensePresented = true }
                    )
                    .padding(.top, 2)

                    WeekCalendar(
                        days: week.days,
                        selectedDate: selectedDate,
                        onSelect: { selectedDate = $0 }
                    )
                    .padding(.top, 22)
                    .padding(.horizontal, -ExpensesLayout.horizontalPadding)

                    Divider()
                        .overlay(ExpensesLayout.separatorColor)
                        .padding(.top, 12)
                        .padding(.horizontal, -ExpensesLayout.horizontalPadding)
                }
                .padding(.horizontal, ExpensesLayout.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.white.ignoresSafeArea(edges: .top))

                DailySummary(selectedDate: selectedDate)
                    .padding(.horizontal, ExpensesLayout.horizontalPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
            }

            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(expenses.enumerated()), id: \.element.id) { index, item in
                            Button {
                                selectedExpense = item
                            } label: {
                                ExpenseRow(item: item)
                                    .padding(.horizontal, ExpensesLayout.horizontalPadding)
                            }
                            .buttonStyle(.plain)

                            if index < expenses.count - 1 {
                                Divider()
                                    .overlay(ExpensesLayout.separatorColor)
                            }
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: ExpenseListContentHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
                }
                .scrollDisabled(ExpensesScrollState.isScrollDisabled(
                    contentHeight: expenseListContentHeight,
                    containerHeight: expenseListContainerHeight
                ))
                .onAppear {
                    expenseListContainerHeight = proxy.size.height
                }
                .onChange(of: proxy.size.height) { _, newValue in
                    expenseListContainerHeight = newValue
                }
                .onPreferenceChange(ExpenseListContentHeightPreferenceKey.self) { newValue in
                    expenseListContentHeight = newValue
                }
            }
        }
        .background(AppColor.white)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Месяц", isPresented: $isMonthPickerPresented, titleVisibility: .visible) {
            Button(ExpenseDateText.monthTitle(for: selectedDate)) {}
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $isAddExpensePresented) {
            AddExpenseView(scope: selectedScope.addExpenseCategoryScope) { _ in
                isAddExpensePresented = false
            }
            .presentationDetents([.large])
        }
        .sheet(item: $selectedExpense) { expense in
            NavigationStack {
                ExpenseDetailsPreview(item: expense)
            }
            .presentationDetents([.medium])
        }
    }
}

struct ExpensesScrollState {
    static func isScrollDisabled(contentHeight: CGFloat, containerHeight: CGFloat) -> Bool {
        contentHeight <= containerHeight
    }
}

private struct ExpenseListContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension ExpenseScope {
    var addExpenseCategoryScope: AddExpenseCategoryScope {
        switch self {
        case .personal:
            .personal
        case .family:
            .family
        }
    }
}

private struct ExpensesHeader: View {
    let onMonthTap: () -> Void
    let monthTitle: String
    @Binding var selectedScope: ExpenseScope
    let onAddTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onMonthTap) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                    Text(monthTitle)
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .liquidGlassButton(cornerRadius: 22)
                .contentShape(.rect(cornerRadius: 22))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                Menu {
                    ForEach(ExpenseScope.allCases, id: \.self) { scope in
                        Button {
                            selectedScope = scope
                        } label: {
                            if scope == selectedScope {
                                Label(scope.rawValue, systemImage: "checkmark")
                            } else {
                                Text(scope.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)

                Button(action: onAddTap) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .liquidGlassButton(cornerRadius: 22)
            .contentShape(.rect(cornerRadius: 22))
        }
    }
}

private struct WeekCalendar: View {
    let days: [ExpenseDay]
    let selectedDate: Date
    let onSelect: (Date) -> Void

    @State private var pageOffset: CGFloat = 0
    @State private var isSettling = false
    @State private var dragAxis: WeekCalendarDragAxis?
    @State private var didTriggerPagingHaptic = false

    private let calendar = Calendar.current
    private let pageThresholdRatio: CGFloat = 0.50
    private let pagingAnimation = Animation.smooth(duration: 0.44, extraBounce: 0)
    private let pagingSettleDelay: TimeInterval = 0.44
    private let weekPageGap: CGFloat = 56
    private let weekContentInset: CGFloat = ExpensesLayout.horizontalPadding

    var body: some View {
        VStack(spacing: 14) {
            WeekdayHeader(days: days)

            GeometryReader { proxy in
                let width = proxy.size.width
                let pageStride = width + weekPageGap

                HStack(spacing: weekPageGap) {
                    WeekDateRow(
                        days: weekDays(weeksFromSelectedDate: -1),
                        selectedDate: selectedDateForWeek(weeksFromSelectedDate: -1),
                        onSelect: select,
                        horizontalInset: weekContentInset
                    )
                    .frame(width: width)

                    WeekDateRow(
                        days: days,
                        selectedDate: selectedDate,
                        onSelect: select,
                        horizontalInset: weekContentInset
                    )
                    .frame(width: width)

                    WeekDateRow(
                        days: weekDays(weeksFromSelectedDate: 1),
                        selectedDate: selectedDateForWeek(weeksFromSelectedDate: 1),
                        onSelect: select,
                        horizontalInset: weekContentInset
                    )
                    .frame(width: width)
                }
                .offset(x: -pageStride + clamped(offset: pageOffset, pageStride: pageStride))
                .animation(isSettling ? pagingAnimation : nil, value: pageOffset)
                .contentShape(Rectangle())
                .clipped()
                .highPriorityGesture(dragGesture(width: width, pageStride: pageStride), including: .gesture)
                .allowsHitTesting(!isSettling)
            }
            .frame(height: 38)
        }
    }

    private func weekDays(weeksFromSelectedDate weeks: Int) -> [ExpenseDay] {
        let date = selectedDateForWeek(weeksFromSelectedDate: weeks)
        return ExpenseWeek.current(containing: date).days
    }

    private func selectedDateForWeek(weeksFromSelectedDate weeks: Int) -> Date {
        ExpenseWeek.date(byMoving: selectedDate, weeks: weeks, calendar: calendar) ?? selectedDate
    }

    private func select(_ date: Date) {
        guard !isSettling else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSelect(date)
    }

    private func finishDrag(_ value: DragGesture.Value, width: CGFloat) {
        let translation = value.translation.width
        let weeks = ExpenseWeekPaging.weekOffset(
            translation: Double(translation),
            pageWidth: Double(width),
            thresholdRatio: Double(pageThresholdRatio)
        )

        guard weeks != 0 else {
            isSettling = true
            withAnimation(pagingAnimation) {
                pageOffset = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + pagingSettleDelay) {
                isSettling = false
            }
            return
        }

        let nextSelectedDate = selectedDateForWeek(weeksFromSelectedDate: weeks)
        let pageStride = width + weekPageGap
        let targetOffset = weeks > 0 ? -pageStride : pageStride

        isSettling = true
        withAnimation(pagingAnimation) {
            pageOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pagingSettleDelay) {
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                onSelect(nextSelectedDate)
                pageOffset = 0
            }

            isSettling = false
        }
    }

    private func clamped(offset: CGFloat, pageStride: CGFloat) -> CGFloat {
        min(max(offset, -pageStride), pageStride)
    }

    private func updatePageOffset(_ offset: CGFloat, pageStride: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            pageOffset = clamped(offset: offset, pageStride: pageStride)
        }
    }

    private func updatePagingHaptic(for translation: CGFloat, width: CGFloat) {
        let weeks = ExpenseWeekPaging.weekOffset(
            translation: Double(translation),
            pageWidth: Double(width),
            thresholdRatio: Double(pageThresholdRatio)
        )

        guard weeks != 0, !didTriggerPagingHaptic else {
            return
        }

        didTriggerPagingHaptic = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
    }

    private func dragGesture(width: CGFloat, pageStride: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard !isSettling else {
                    return
                }

                switch dragAxis {
                case .horizontal:
                    updatePageOffset(value.translation.width, pageStride: pageStride)
                    updatePagingHaptic(for: value.translation.width, width: width)
                case .vertical:
                    break
                case nil:
                    let axis = axis(for: value)
                    dragAxis = axis

                    if axis == .horizontal {
                        updatePageOffset(value.translation.width, pageStride: pageStride)
                        updatePagingHaptic(for: value.translation.width, width: width)
                    }
                }
            }
            .onEnded { value in
                guard !isSettling else {
                    dragAxis = nil
                    didTriggerPagingHaptic = false
                    return
                }

                let axis = dragAxis
                dragAxis = nil
                didTriggerPagingHaptic = false

                guard axis == .horizontal else {
                    withAnimation(pagingAnimation) {
                        pageOffset = 0
                    }
                    return
                }

                finishDrag(value, width: width)
            }
    }

    private func axis(for value: DragGesture.Value) -> WeekCalendarDragAxis? {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if horizontalDistance >= 3, horizontalDistance >= verticalDistance {
            return .horizontal
        }
        if verticalDistance >= 8, verticalDistance > horizontalDistance * 1.2 {
            return .vertical
        }

        return nil
    }
}

private enum WeekCalendarDragAxis {
    case horizontal
    case vertical
}

private struct WeekdayHeader: View {
    let days: [ExpenseDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index > 0 {
                    Spacer(minLength: 0)
                }

                Text(day.weekday)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(day.isWeekend ? AppColor.weekend : AppColor.black)
                    .frame(width: 32)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
        }
        .padding(.horizontal, ExpensesLayout.horizontalPadding)
    }
}

private struct WeekDateRow: View {
    let days: [ExpenseDay]
    let selectedDate: Date
    let onSelect: (Date) -> Void
    let horizontalInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index > 0 {
                    Spacer(minLength: 0)
                }

                let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                let isToday = day.isToday

                Text("\(day.day)")
                    .font(.system(size: 19, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(day.foregroundColor(isSelected: isSelected, isToday: isToday))
                    .frame(width: 30, height: 30)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .background {
                        Circle()
                            .fill(isToday ? AppColor.blue : AppColor.black)
                            .frame(width: 34, height: 34)
                            .scaleEffect(isSelected ? 1 : 0.72)
                            .opacity(isSelected ? 1 : 0)
                            .animation(
                                .spring(response: 0.24, dampingFraction: 0.72),
                                value: isSelected
                            )
                    }
                    .frame(width: 32)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isSelected else { return }
                        onSelect(day.date)
                    }
                    .scaleEffect(1)
                    .animation(.easeOut(duration: 0.10), value: isSelected)
                    .frame(height: 38)
            }
        }
        .padding(.horizontal, horizontalInset)
    }
}

private struct DailySummary: View {
    let selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.muted)

            Text(MoneyFormatter.rubles(2_655))
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(AppColor.black)
                .minimumScaleFactor(0.8)
        }
    }

    private var title: String {
        Calendar.current.isDateInToday(selectedDate) ? "Сегодня" : ExpenseDateText.dayMonthTitle(for: selectedDate)
    }
}

private struct ExpenseRow: View {
    let item: ExpenseListItem

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColor.black)
                Text(item.subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColor.muted)
            }

            Spacer(minLength: 16)

            Text(item.amount)
                .font(.headline.weight(.heavy))
                .foregroundStyle(AppColor.black)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct ExpenseDetailsPreview: View {
    let item: ExpenseListItem

    var body: some View {
        List {
            LabeledContent("Название", value: item.title)
            LabeledContent("Описание", value: item.subtitle)
            LabeledContent("Сумма", value: item.amount)
        }
        .navigationTitle("Расход")
        .navigationBarTitleDisplayMode(.inline)
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

private extension ExpenseDay {
    func foregroundColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return AppColor.white
        }
        if isWeekend {
            return AppColor.weekend
        }
        if isToday {
            return AppColor.blue
        }
        return AppColor.black
    }
}

private struct ExpenseListItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let amount: String
}

private extension View {
    @ViewBuilder
    func liquidGlassButton(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

#Preview {
    ExpensesHomeView()
}
