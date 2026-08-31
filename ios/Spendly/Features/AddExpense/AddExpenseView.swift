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
    @State private var isItemsSheetPresented = false
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
            .sheet(isPresented: $isItemsSheetPresented) {
                CartItemsSheet(draft: $draft)
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

            if draft.hasItems {
                Text(MoneyFormatter.rublesMinorUnits(draft.totalMinorUnits ?? 0))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppColor.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .whiteSurface(cornerRadius: 18)
            } else {
                MoneyAmountTextField(text: $draft.amountText)
                    .padding(.horizontal, 18)
                    .frame(height: 72)
                    .whiteSurface(cornerRadius: 18)
            }
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
            isItemsSheetPresented = true
        } label: {
            if draft.items.isEmpty {
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
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Товары")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColor.black)

                    VStack(spacing: 10) {
                        ForEach(draft.items.prefix(3)) { item in
                            HStack {
                                Text(item.displayName)
                                    .foregroundStyle(AppColor.black)
                                    .lineLimit(1)
                                Spacer()
                                Text(MoneyFormatter.rublesMinorUnits(item.totalMinorUnits ?? 0))
                                    .foregroundStyle(AppColor.black)
                            }
                            .font(.body)
                        }
                    }

                    HStack(alignment: .bottom) {
                        Text("\(draft.items.count) \(draft.items.count == 1 ? "товар" : "товара")")
                            .foregroundStyle(AppColor.muted)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(MoneyFormatter.rublesMinorUnits(draft.itemsSubtotalMinorUnits ?? 0))
                                .foregroundStyle(AppColor.black)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColor.muted)
                        }
                    }
                    .font(.body.weight(.medium))
                }
                .padding(18)
                .whiteSurface(cornerRadius: 16)
            }
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

private struct CartItemsSheet: View {
    @Binding var draft: AddExpenseDraft

    @Environment(\.dismiss) private var dismiss
    @State private var itemFormDraft: CartItemFormDraft?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !draft.items.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(draft.items) { item in
                                    itemRow(item)

                                    if item.id != draft.items.last?.id {
                                        Divider()
                                            .overlay(AppColor.border)
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                            .whiteSurface(cornerRadius: 16)
                        }

                        Button {
                            itemFormDraft = CartItemFormDraft()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppColor.blue)

                                Text("Добавить товар")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColor.black)

                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 56)
                            .whiteSurface(cornerRadius: 16)
                        }
                        .buttonStyle(ContrastRowButtonStyle())

                        totalsControls
                    }
                    .padding(20)
                }

                cartSummary
                    .padding(20)
                    .background(AppColor.white)
            }
            .background(AppColor.gray)
            .navigationTitle("Товары")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(AppColor.blue)
                }
            }
            .sheet(item: $itemFormDraft) { formDraft in
                CartItemFormSheet(initialDraft: formDraft) { saved in
                    draft.upsertItem(saved.item)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func itemRow(_ item: AddExpenseItemDraft) -> some View {
        Button {
            itemFormDraft = CartItemFormDraft(item: item)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(AppColor.black)
                        .lineLimit(1)

                    Text("\(item.quantity) × \(MoneyFormatter.rublesMinorUnits(item.unitPriceMinorUnits ?? 0))")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)
                }

                Spacer()

                Text(MoneyFormatter.rublesMinorUnits(item.totalMinorUnits ?? 0))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.black)

                Button(role: .destructive) {
                    draft.removeItem(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var totalsControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Доставка")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColor.black)

                MoneyAmountTextField(text: $draft.deliveryFeeText)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .whiteSurface(cornerRadius: 16)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Скидка")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColor.black)

                HStack(spacing: 10) {
                    TextField("0", text: $draft.discountText)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColor.black)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .whiteSurface(cornerRadius: 14)
                        .onChange(of: draft.discountText) { _, _ in
                            draft.normalizeDiscountText()
                        }

                    Picker("Тип скидки", selection: $draft.discountType) {
                        Text("₽").tag(AddExpenseDiscountType.fixed)
                        Text("%").tag(AddExpenseDiscountType.percentage)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 112)
                    .onChange(of: draft.discountType) { _, _ in
                        draft.normalizeDiscountText()
                    }
                }
            }
        }
    }

    private var cartSummary: some View {
        VStack(spacing: 10) {
            summaryRow("Товары", draft.itemsSubtotalMinorUnits ?? 0)
            summaryRow("Доставка", draft.deliveryFeeMinorUnits ?? 0)
            summaryRow("Скидка", -(draft.discountMinorUnits ?? 0))

            Divider()
                .overlay(AppColor.border)

            summaryRow("Итого", draft.totalMinorUnits ?? 0, isTotal: true)
        }
    }

    private func summaryRow(_ title: String, _ value: Int64, isTotal: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(MoneyFormatter.rublesMinorUnits(value))
        }
        .font(isTotal ? .headline.weight(.bold) : .body.weight(.medium))
        .foregroundStyle(AppColor.black)
    }
}

private struct CartItemFormSheet: View {
    let initialDraft: CartItemFormDraft
    let onSave: (CartItemFormDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CartItemFormDraft
    @FocusState private var isNameFocused: Bool

    init(initialDraft: CartItemFormDraft, onSave: @escaping (CartItemFormDraft) -> Void) {
        self.initialDraft = initialDraft
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                formField(title: "Название") {
                    TextField("", text: $draft.name, prompt: Text("Например, Молоко").foregroundStyle(AppColor.placeholder))
                        .textInputAutocapitalization(.words)
                        .focused($isNameFocused)
                }

                formField(title: "Количество") {
                    TextField("1", value: $draft.quantity, format: .number)
                        .keyboardType(.numberPad)
                }

                formField(title: "Цена") {
                    MoneyAmountTextField(text: $draft.unitPriceText)
                }

                Spacer()
            }
            .padding(20)
            .background(AppColor.gray)
            .navigationTitle(initialDraft.isExistingItem ? "Товар" : "Новый товар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                    .foregroundStyle(draft.canSave ? AppColor.blue : AppColor.muted)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func formField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColor.black)

            content()
                .font(.body)
                .foregroundStyle(AppColor.black)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .whiteSurface(cornerRadius: 16)
        }
    }
}

private struct CartItemFormDraft: Identifiable {
    let id: UUID
    var name: String
    var quantity: Int64
    var unitPriceText: String
    let isExistingItem: Bool

    init(item: AddExpenseItemDraft? = nil) {
        if let item {
            id = item.id
            name = item.name
            quantity = item.quantity
            unitPriceText = item.unitPriceText
            isExistingItem = true
        } else {
            id = UUID()
            name = ""
            quantity = 1
            unitPriceText = ""
            isExistingItem = false
        }
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantity > 0
            && MoneyFormatter.minorUnits(from: unitPriceText) != nil
    }

    var item: AddExpenseItemDraft {
        AddExpenseItemDraft(id: id, name: name, quantity: quantity, unitPriceText: unitPriceText)
    }
}

struct AddExpenseItemDraft: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var quantity: Int64 = 1
    var unitPriceText: String

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var unitPriceMinorUnits: Int64? {
        MoneyFormatter.minorUnits(from: unitPriceText).map(Int64.init)
    }

    var totalMinorUnits: Int64? {
        guard let unitPriceMinorUnits, quantity > 0 else { return nil }
        let result = unitPriceMinorUnits.multipliedReportingOverflow(by: quantity)
        guard !result.overflow else { return nil }
        return result.partialValue
    }
}

enum AddExpenseDiscountType: Equatable, Hashable {
    case fixed
    case percentage
}

struct AddExpenseDraft: Equatable {
    var amountText = ""
    var merchant = ""
    var selectedCategory: AddExpenseCategory?
    var spentAt = Date.now
    var items: [AddExpenseItemDraft] = []
    var deliveryFeeText = ""
    var discountText = ""
    var discountType: AddExpenseDiscountType = .fixed

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
        if let totalMinorUnits, hasItems {
            return Int(totalMinorUnits)
        }
        return MoneyFormatter.minorUnits(from: amountText)
    }

    var hasItems: Bool {
        !items.isEmpty
    }

    var itemsSubtotalMinorUnits: Int64? {
        guard !items.isEmpty else { return 0 }
        var subtotal: Int64 = 0
        for item in items {
            guard let total = item.totalMinorUnits else { return nil }
            let result = subtotal.addingReportingOverflow(total)
            guard !result.overflow else { return nil }
            subtotal = result.partialValue
        }
        return subtotal
    }

    var deliveryFeeMinorUnits: Int64? {
        guard !deliveryFeeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }
        return MoneyFormatter.nonNegativeMinorUnits(from: deliveryFeeText).map(Int64.init)
    }

    var discountMinorUnits: Int64? {
        guard let subtotal = itemsSubtotalMinorUnits else { return nil }
        guard !discountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }

        switch discountType {
        case .fixed:
            return MoneyFormatter.nonNegativeMinorUnits(from: discountText).map(Int64.init)
        case .percentage:
            guard let value = Int64(discountText.filter(\.isNumber)), (0...100).contains(value) else {
                return nil
            }
            return subtotal * value / 100
        }
    }

    var totalMinorUnits: Int64? {
        guard hasItems, let subtotal = itemsSubtotalMinorUnits, let delivery = deliveryFeeMinorUnits, let discount = discountMinorUnits else {
            return nil
        }
        return max(0, subtotal + delivery - discount)
    }

    mutating func upsertItem(_ item: AddExpenseItemDraft) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    mutating func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func normalizeDiscountText() {
        switch discountType {
        case .fixed:
            discountText = MoneyFormatter.inputText(from: discountText)
        case .percentage:
            let digits = discountText.filter(\.isNumber)
            let value = min(Int(digits) ?? 0, 100)
            discountText = digits.isEmpty ? "" : "\(value)"
        }
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
