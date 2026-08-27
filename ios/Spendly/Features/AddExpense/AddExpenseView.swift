import SwiftUI
import UIKit

enum AddExpenseCategoryScope: Equatable {
    case personal
    case family
}

struct AddExpenseView: View {
    private enum Layout {
        static let sectionSpacing: CGFloat = 16
        static let fieldSpacing: CGFloat = 10
    }

    let scope: AddExpenseCategoryScope
    let onSave: (AddExpenseDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = AddExpenseDraft()
    @State private var isItemsPlaceholderPresented = false
    @State private var isDatePickerPresented = false
    @State private var isCategoryPickerPresented = false
    @FocusState private var isMerchantFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    headerSection
                    amountSection
                    detailsSection
                    itemsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        dismissKeyboard()
                    }
            )
            .background(AppColor.gray)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Товары будут следующим шагом", isPresented: $isItemsPlaceholderPresented) {
                Button("ОК", role: .cancel) {}
            } message: {
                Text("В этой версии экран показывает структуру добавления расхода без редактора позиций.")
            }
            .sheet(isPresented: $isDatePickerPresented) {
                NavigationStack {
                    VStack {
                        DatePicker(
                            "Дата",
                            selection: $draft.spentAt,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding()

                        Spacer()
                    }
                    .background(AppColor.gray)
                    .navigationTitle("Дата")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Готово") {
                                isDatePickerPresented = false
                            }
                            .foregroundStyle(AppColor.blue)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isCategoryPickerPresented) {
                CategorySelectionSheet(selectedCategory: $draft.selectedCategory)
            }
        }
    }

    private var headerSection: some View {
        HStack {
            Button(action: dismiss.callAsFunction) {
                actionCircleButton(
                    systemName: "xmark",
                    iconColor: AppColor.black,
                    fillColor: AppColor.gray
                )
            }
            .buttonStyle(GlassCircleButtonStyle())

            Spacer()

            Text("Новая трата")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColor.black)

            Spacer()

            Button(action: save) {
                actionCircleButton(
                    systemName: "checkmark",
                    iconColor: draft.canSave ? AppColor.white : AppColor.muted,
                    fillColor: draft.canSave ? AppColor.blue : AppColor.gray,
                    isGlassTinted: draft.canSave
                )
            }
            .buttonStyle(GlassCircleButtonStyle())
            .disabled(!draft.canSave)
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
            Text("Сумма")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColor.black)

            MoneyAmountTextField(text: $draft.amountText)
                .padding(.horizontal, 18)
                .frame(height: 72)
                .whiteSurface(cornerRadius: 18)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            formField(title: "Магазин или название", onTap: {
                isMerchantFocused = true
            }) {
                TextField(
                    "",
                    text: $draft.merchant,
                    prompt: Text("Например, Ozon Fresh").foregroundStyle(AppColor.placeholder)
                )
                    .textInputAutocapitalization(.words)
                    .focused($isMerchantFocused)
            }

            categorySection

            VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
                Text("Дата")
                    .foregroundStyle(AppColor.black)
                    .font(.headline.weight(.semibold))

                Button {
                    isDatePickerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColor.blue)

                        Text(draft.spentAt.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppColor.black)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.muted)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .whiteSurface(cornerRadius: 16)
                }
                .buttonStyle(ContrastRowButtonStyle())
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
            Text("Категория")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColor.black)

            Button {
                dismissKeyboard()
                isCategoryPickerPresented = true
            } label: {
                HStack {
                    Text(draft.selectedCategory?.name ?? "Выберите категорию")
                        .foregroundStyle(
                            draft.selectedCategory == nil ? AppColor.placeholder : AppColor.black
                        )
                        .contentTransition(.identity)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.muted)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .whiteSurface(cornerRadius: 16)
                .contentShape(Rectangle())
                .transaction(value: draft.selectedCategory) { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var itemsSection: some View {
        Button {
            isItemsPlaceholderPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColor.blue)

                Text("Добавить товары")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.black)

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .whiteSurface(cornerRadius: 16)
        }
        .buttonStyle(ContrastRowButtonStyle())
    }

    private func formField<Content: View>(
        title: String,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColor.black)

            content()
                .font(.body)
                .foregroundStyle(AppColor.black)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .whiteSurface(cornerRadius: 16)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    onTap?()
                }
        }
    }

    private func save() {
        guard draft.canSave else { return }
        onSave(draft)
        dismiss()
    }

    private func actionCircleButton(
        systemName: String,
        iconColor: Color,
        fillColor: Color,
        isGlassTinted: Bool = false
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 44, height: 44)
            .background {
                Circle()
                    .fill(isGlassTinted ? fillColor : AppColor.white)
            }
            .liquidGlassCircle()
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isGlassTinted ? AppColor.blue.opacity(0.18) : AppColor.white.opacity(0.95), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
            .contentShape(Circle())
    }

}

private struct CategorySelectionSheet: View {
    @Binding var selectedCategory: AddExpenseCategory?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var categories: [AddExpenseCategory] = []
    @FocusState private var isSearchFocused: Bool

    private var filteredCategories: [AddExpenseCategory] {
        AddExpenseCategoryStore.filteredCategories(matching: searchText, in: categories)
    }

    private var validatedNewCategoryName: String? {
        AddExpenseCategoryStore.validatedNewCategoryName(searchText, existingCategories: categories)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColor.white)

                    TextField("Поиск или новая категория", text: $searchText)
                        .textInputAutocapitalization(.words)
                        .submitLabel(validatedNewCategoryName == nil ? .search : .done)
                        .onSubmit(createCategoryIfPossible)
                        .focused($isSearchFocused)
                        .foregroundStyle(AppColor.black)
                        .padding(.horizontal, 16)
                }
                .frame(height: 52)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    isSearchFocused = true
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let validatedNewCategoryName {
                            createCategoryButton(named: validatedNewCategoryName)

                            if !filteredCategories.isEmpty {
                                Divider()
                                    .overlay(AppColor.border)
                                    .padding(.leading, 16)
                            }
                        }

                        ForEach(filteredCategories) { category in
                            if category.id != filteredCategories.first?.id {
                                Divider()
                                    .overlay(AppColor.border)
                                    .padding(.leading, 16)
                            }

                            categoryButton(category)
                        }
                    }
                    .whiteSurface(cornerRadius: 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            dismissSearchKeyboard()
                        }
                )
            }
            .padding(20)
            .background(AppColor.gray)
            .navigationTitle("Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        closeSheet()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            categories = AddExpenseCategoryStore.categories
        }
    }

    private func categoryButton(_ category: AddExpenseCategory) -> some View {
        Button {
            selectedCategory = category
            closeSheet()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppColor.black)

                    Text(category.kind.title)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                }

                Spacer()

                if selectedCategory?.id == category.id {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.blue)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func createCategoryButton(named name: String) -> some View {
        Button {
            createCategory(named: name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.blue)

                Text("Create \"\(name)\"")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppColor.black)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func createCategoryIfPossible() {
        guard let validatedNewCategoryName else { return }

        createCategory(named: validatedNewCategoryName)
    }

    private func createCategory(named name: String) {
        guard let category = AddExpenseCategoryStore.createCategory(named: name) else { return }

        categories = AddExpenseCategoryStore.categories
        selectedCategory = category
        closeSheet()
    }

    private func closeSheet() {
        dismissSearchKeyboard()
        dismiss()
    }

    private func dismissSearchKeyboard() {
        isSearchFocused = false
        dismissKeyboard()
    }
}

@MainActor
private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

private extension View {
    @ViewBuilder
    func liquidGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(
                .ultraThinMaterial,
                in: Circle()
            )
        }
    }

    func whiteSurface(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColor.white)
        )
    }

}

private struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ContrastRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .saturation(configuration.isPressed ? 1.15 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MoneyAmountTextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.keyboardType = .decimalPad
        textField.font = .systemFont(ofSize: 34, weight: .semibold)
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = 20
        textField.clipsToBounds = true
        textField.textColor = UIColor(red: 29 / 255, green: 29 / 255, blue: 31 / 255, alpha: 1)
        textField.tintColor = UIColor(red: 0 / 255, green: 102 / 255, blue: 204 / 255, alpha: 1)
        textField.attributedPlaceholder = NSAttributedString(
            string: "0",
            attributes: [
                .foregroundColor: UIColor(red: 197 / 255, green: 197 / 255, blue: 198 / 255, alpha: 1)
            ]
        )
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func editingChanged(_ textField: UITextField) {
            let raw = textField.text ?? ""
            let formatted = MoneyFormatter.inputText(from: raw)

            if textField.text != formatted {
                textField.text = formatted
            }

            if text != formatted {
                text = formatted
            }
        }
    }
}

struct AddExpenseDraft: Equatable {
    var amountText = ""
    var merchant = ""
    var selectedCategory: AddExpenseCategory?
    var spentAt = Date.now

    var canSave: Bool {
        normalizedMinorUnits != nil && !merchantTrimmed.isEmpty && selectedCategory != nil
    }

    var merchantTrimmed: String {
        merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var categoryId: String? {
        selectedCategory?.id
    }

    var category: String {
        (selectedCategory?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var normalizedMinorUnits: Int? {
        MoneyFormatter.minorUnits(from: amountText)
    }
}

struct AddExpenseCategory: Identifiable, Equatable, Hashable {
    enum Kind: Equatable, Hashable {
        case defaultCategory
        case userCreated

        var title: String {
            switch self {
            case .defaultCategory:
                "Стандартная"
            case .userCreated:
                "Своя"
            }
        }
    }

    let id: String
    let name: String
    let kind: Kind

    @MainActor
    static func defaultCategory(name: String) -> AddExpenseCategory {
        AddExpenseCategory(
            id: "default-\(AddExpenseCategoryStore.normalizedName(name))",
            name: AddExpenseCategoryStore.displayName(name),
            kind: .defaultCategory
        )
    }

    @MainActor
    static func userCreated(name: String) -> AddExpenseCategory {
        let displayName = AddExpenseCategoryStore.displayName(name)

        return AddExpenseCategory(
            id: "user-\(UUID().uuidString)",
            name: displayName,
            kind: .userCreated
        )
    }
}

@MainActor
enum AddExpenseCategoryStore {
    static let defaultCategories: [AddExpenseCategory] = [
        "Продукты",
        "Транспорт",
        "Кафе",
        "Развлечения",
        "Дом",
        "Здоровье",
        "Подарки",
        "Подписки",
        "Одежда",
        "Другое"
    ].map { AddExpenseCategory.defaultCategory(name: $0) }

    private static var userCreatedCategories: [AddExpenseCategory] = []

    static var categories: [AddExpenseCategory] {
        defaultCategories + userCreatedCategories
    }

    static func filteredCategories(
        matching query: String,
        in source: [AddExpenseCategory]? = nil
    ) -> [AddExpenseCategory] {
        let availableCategories = source ?? Self.categories
        let normalizedQuery = normalizedName(query)
        guard !normalizedQuery.isEmpty else { return availableCategories }

        return availableCategories.filter { category in
            normalizedName(category.name).contains(normalizedQuery)
        }
    }

    static func createCategory(named name: String) -> AddExpenseCategory? {
        guard let displayName = validatedNewCategoryName(name, existingCategories: categories) else {
            return nil
        }

        let category = AddExpenseCategory.userCreated(name: displayName)
        userCreatedCategories.append(category)
        return category
    }

    static func resetUserCategories() {
        userCreatedCategories = []
    }

    static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
    }

    static func validatedNewCategoryName(
        _ value: String,
        existingCategories: [AddExpenseCategory]
    ) -> String? {
        let name = displayName(value)
        guard !name.isEmpty else { return nil }

        let normalized = normalizedName(name)
        guard !existingCategories.contains(where: { normalizedName($0.name) == normalized }) else {
            return nil
        }

        return name
    }

    static func displayName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

#Preview {
    AddExpenseView(scope: .personal) { _ in }
}
