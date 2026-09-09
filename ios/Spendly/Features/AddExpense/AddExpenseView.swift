import SwiftUI
import UIKit
import Observation

enum AddExpenseCategoryScope: Equatable {
    case personal
    case family
}

enum AddExpenseMode: Equatable {
    case create
    case edit(Purchase)

    var purchase: Purchase? {
        guard case let .edit(purchase) = self else { return nil }
        return purchase
    }
}

enum AddExpenseKeyboardLayout {
    static let baseBottomPadding: CGFloat = 24

    static func bottomContentPadding(keyboardHeight: CGFloat) -> CGFloat {
        guard keyboardHeight > 0 else {
            return baseBottomPadding
        }
        return keyboardHeight + baseBottomPadding
    }
}

@MainActor
private enum AddExpenseFeedback {
    static func saved() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.6)
    }

    static func deleted() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
    }
}

struct AddExpenseView: View {
    private enum Layout {
        static let sectionSpacing: CGFloat = 16
        static let fieldSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 18
        static let fieldHeight: CGFloat = 56
        static let fieldCornerRadius: CGFloat = 16
        static let amountFieldHeight: CGFloat = 68
        static let amountCornerRadius: CGFloat = 16
    }

    let scope: AddExpenseCategoryScope
    let mode: AddExpenseMode
    let onSave: (Purchase) -> Void
    let onDelete: (PurchaseID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AddExpenseDraft
    @State private var model: AddExpenseModel
    @State private var isDatePickerPresented = false
    @State private var isCategoryPickerPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isMerchantFocused: Bool

    init(
        repository: any PurchaseRepository = AddExpensePreviewPurchaseRepository(),
        context: ExpenseContext = .personal(UserID(rawValue: UUID())),
        scope: AddExpenseCategoryScope,
        onSave: @escaping (Purchase) -> Void = { _ in }
    ) {
        self.scope = scope
        self.mode = .create
        self.onSave = onSave
        self.onDelete = { _ in }
        _draft = State(initialValue: AddExpenseDraft())
        _model = State(initialValue: AddExpenseModel(
            repository: repository,
            context: context,
            saveFeedback: AddExpenseFeedback.saved,
            deleteFeedback: AddExpenseFeedback.deleted
        ))
    }

    init(
        repository: any PurchaseRepository,
        context: ExpenseContext,
        scope: AddExpenseCategoryScope,
        purchase: Purchase,
        onSave: @escaping (Purchase) -> Void = { _ in },
        onDelete: @escaping (PurchaseID) -> Void = { _ in }
    ) {
        self.scope = scope
        self.mode = .edit(purchase)
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: (try? AddExpenseDraft(purchase: purchase)) ?? AddExpenseDraft())
        _model = State(initialValue: AddExpenseModel(
            repository: repository,
            context: context,
            saveFeedback: AddExpenseFeedback.saved,
            deleteFeedback: AddExpenseFeedback.deleted
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    headerSection
                        .padding(.bottom, 14)
                    if model.failure != nil {
                        saveFailureMessage
                    }
                    detailsSection

                    amountSection

                    if mode.purchase != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, AddExpenseKeyboardLayout.bottomContentPadding(keyboardHeight: keyboardHeight))
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        dismissKeyboard()
                    }
            )
            .background(AppColor.dashboardBackground)
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
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                keyboardHeight = Self.keyboardHeight(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
            .alert("Удалить транзакцию?", isPresented: $isDeleteConfirmationPresented) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive, action: deletePurchase)
            } message: {
                Text("Это действие нельзя отменить.")
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

            Text(mode.purchase == nil ? "Новая запись" : "Редактирование")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColor.black)

            Spacer()

            Button(action: save) {
                saveActionButton
            }
            .buttonStyle(GlassCircleButtonStyle())
            .disabled(!canSubmit || model.isBusy)
        }
    }

    private var canSubmit: Bool {
        draft.canSubmit(comparedTo: mode.purchase)
    }

    private var saveActionButton: some View {
        ZStack {
            if model.isSaving {
                Circle()
                    .fill(AppColor.blue)
                    .frame(width: 44, height: 44)
                    .liquidGlassCircle()
                    .overlay(
                        Circle()
                            .stroke(AppColor.blue.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)

                ProgressView()
                    .tint(AppColor.white)
                    .controlSize(.small)
            } else {
                actionCircleButton(
                    systemName: "checkmark",
                    iconColor: canSubmit ? AppColor.white : AppColor.muted,
                    fillColor: canSubmit ? AppColor.blue : AppColor.gray,
                    isGlassTinted: canSubmit
                )
            }
        }
        .frame(width: 44, height: 44)
    }

    private var saveFailureMessage: some View {
        Text(model.failureAction == .delete
            ? "Не удалось удалить операцию. Проверьте подключение и попробуйте ещё раз."
            : "Не удалось сохранить операцию. Проверьте подключение и попробуйте ещё раз.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppColor.dashboardSecondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .whiteSurface(cornerRadius: 14)
    }

    private var deleteButton: some View {
        Button {
            dismissKeyboard()
            isDeleteConfirmationPresented = true
        } label: {
            HStack(spacing: 8) {
                if model.isDeleting {
                    ProgressView()
                        .tint(.red)
                } else {
                    Image(systemName: "trash")
                }

                Text("Удалить транзакцию")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: Layout.fieldHeight)
            .whiteSurface(cornerRadius: Layout.fieldCornerRadius)
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .padding(.top, 8)
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
            Text("Сумма")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColor.black)

            MoneyAmountTextField(text: $draft.amountText)
                .padding(.horizontal, 16)
                .frame(height: Layout.amountFieldHeight)
                .whiteSurface(cornerRadius: Layout.amountCornerRadius)
                .contentShape(Rectangle())
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            formField(title: "Название", onTap: {
                isMerchantFocused = true
            }) {
                TextField(
                    "",
                    text: $draft.merchant,
                    prompt: Text("Например, Ozon Fresh")
                        .font(.callout)
                        .foregroundStyle(AppColor.placeholder)
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
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColor.dashboardPrimaryText)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.muted)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: Layout.fieldHeight)
                    .whiteSurface(cornerRadius: Layout.fieldCornerRadius)
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
                        .font(draft.selectedCategory == nil ? .callout : .subheadline)
                        .foregroundStyle(
                            draft.selectedCategory == nil ? AppColor.placeholder : AppColor.dashboardPrimaryText
                        )
                        .contentTransition(.identity)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.muted)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: Layout.fieldHeight, alignment: .leading)
                .whiteSurface(cornerRadius: Layout.fieldCornerRadius)
                .contentShape(Rectangle())
                .transaction(value: draft.selectedCategory) { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .buttonStyle(.plain)
        }
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
                .font(.subheadline)
                .foregroundStyle(AppColor.dashboardPrimaryText)
                .padding(.horizontal, 16)
                .frame(height: Layout.fieldHeight)
                .whiteSurface(cornerRadius: Layout.fieldCornerRadius)
                .contentShape(RoundedRectangle(cornerRadius: Layout.fieldCornerRadius, style: .continuous))
                .onTapGesture {
                    onTap?()
                }
        }
    }

    private func save() {
        guard canSubmit, !model.isBusy else { return }

        Task {
            let savedPurchase: Purchase?
            if let purchase = mode.purchase {
                savedPurchase = await model.update(purchase, with: draft)
            } else {
                savedPurchase = await model.save(draft)
            }

            guard let savedPurchase else { return }

            onSave(savedPurchase)
            dismiss()
        }
    }

    private func deletePurchase() {
        guard let purchase = mode.purchase, !model.isBusy else { return }

        Task {
            guard await model.delete(purchase) else { return }
            onDelete(purchase.id)
            dismiss()
        }
    }

    private static func keyboardHeight(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        return max(0, UIScreen.main.bounds.maxY - frame.minY)
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

enum AddExpenseFailureAction {
    case save
    case delete
}

@MainActor
@Observable
final class AddExpenseModel {
    private(set) var isSaving = false
    private(set) var isDeleting = false
    private(set) var failure: AppFailure?
    private(set) var failureAction: AddExpenseFailureAction?

    var isBusy: Bool {
        isSaving || isDeleting
    }

    private let repository: any PurchaseRepository
    private let context: ExpenseContext
    private let saveFeedback: () -> Void
    private let deleteFeedback: () -> Void

    init(
        repository: any PurchaseRepository,
        context: ExpenseContext,
        saveFeedback: @escaping () -> Void = {},
        deleteFeedback: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.context = context
        self.saveFeedback = saveFeedback
        self.deleteFeedback = deleteFeedback
    }

    func save(_ draft: AddExpenseDraft, idempotencyKey: UUID = UUID()) async -> Purchase? {
        guard !isBusy else { return nil }

        isSaving = true
        failure = nil
        failureAction = nil
        defer { isSaving = false }

        do {
            let purchaseDraft = try draft.purchaseDraft(in: context)
            let purchase = try await repository.create(purchaseDraft, idempotencyKey: idempotencyKey)
            saveFeedback()
            return purchase
        } catch is CancellationError {
            return nil
        } catch {
            failure = error as? AppFailure ?? .unknown
            failureAction = .save
            return nil
        }
    }

    func update(_ purchase: Purchase, with draft: AddExpenseDraft) async -> Purchase? {
        guard !isBusy, draft.canSubmit(comparedTo: purchase) else { return nil }

        isSaving = true
        failure = nil
        failureAction = nil
        defer { isSaving = false }

        do {
            let updatedPurchase = try draft.updatedPurchase(purchase)
            let savedPurchase = try await repository.update(updatedPurchase, expectedVersion: purchase.version)
            saveFeedback()
            return savedPurchase
        } catch is CancellationError {
            return nil
        } catch {
            failure = error as? AppFailure ?? .unknown
            failureAction = .save
            return nil
        }
    }

    func delete(_ purchase: Purchase) async -> Bool {
        guard !isBusy else { return false }

        isDeleting = true
        failure = nil
        failureAction = nil
        defer { isDeleting = false }

        do {
            try await repository.delete(id: purchase.id, expectedVersion: purchase.version)
            deleteFeedback()
            return true
        } catch is CancellationError {
            return false
        } catch {
            failure = error as? AppFailure ?? .unknown
            failureAction = .delete
            return false
        }
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColor.dashboardSurface)

                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("Поиск или новая категория")
                            .font(.callout)
                            .foregroundStyle(AppColor.placeholder)
                    )
                        .font(.subheadline)
                        .textInputAutocapitalization(.words)
                        .submitLabel(validatedNewCategoryName == nil ? .search : .done)
                        .onSubmit(createCategoryIfPossible)
                        .focused($isSearchFocused)
                        .foregroundStyle(AppColor.dashboardPrimaryText)
                        .padding(.horizontal, 16)
                }
                .frame(height: 56)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    isSearchFocused = true
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let validatedNewCategoryName {
                            createCategoryButton(named: validatedNewCategoryName)

                            if !filteredCategories.isEmpty {
                                Divider()
                                    .overlay(AppColor.dashboardSeparator.opacity(0.45))
                                    .padding(.leading, 54)
                            }
                        }

                        ForEach(filteredCategories) { category in
                            if category.id != filteredCategories.first?.id {
                                Divider()
                                    .overlay(AppColor.dashboardSeparator.opacity(0.45))
                                    .padding(.leading, 54)
                            }

                            categoryButton(category)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        AppColor.dashboardSurface,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .shadow(color: Color.black.opacity(0.055), radius: 24, x: 0, y: 10)
                    .padding(.bottom, 32)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            dismissSearchKeyboard()
                        }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
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
                Image(systemName: category.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(category.tint)
                    .frame(width: 42, height: 42)
                    .background(
                        category.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.dashboardPrimaryText)

                    Text(category.kind.title)
                        .font(.footnote)
                        .foregroundStyle(AppColor.dashboardSecondaryText)
                }

                Spacer()

                if selectedCategory?.id == category.id {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.blue)
                }
            }
            .padding(.vertical, 8)
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.blue)
                    .frame(width: 42, height: 42)
                    .background(
                        AppColor.blue.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                Text("Create \"\(name)\"")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.dashboardPrimaryText)

                Spacer()
            }
            .padding(.vertical, 8)
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
                .fill(AppColor.dashboardSurface)
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
    let fontSize: CGFloat
    let fontWeight: UIFont.Weight

    init(
        text: Binding<String>,
        fontSize: CGFloat = 34,
        fontWeight: UIFont.Weight = .semibold
    ) {
        _text = text
        self.fontSize = fontSize
        self.fontWeight = fontWeight
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.keyboardType = .decimalPad
        textField.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        textField.adjustsFontSizeToFitWidth = true
        textField.minimumFontSize = min(20, fontSize)
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

    init() {}

    @MainActor
    init(purchase: Purchase) throws {
        guard case let .quick(categoryName, amount) = purchase.kind else {
            throw AppFailure.validation(fields: [:])
        }

        amountText = Self.amountText(minorUnits: amount.minorUnits)
        merchant = purchase.merchant
        selectedCategory = AddExpenseCategoryStore.categories.first { $0.name == categoryName }
            ?? AddExpenseCategory.userCreated(name: categoryName)
        spentAt = purchase.spentAt
    }

    var canSave: Bool {
        normalizedMinorUnits != nil && !merchantTrimmed.isEmpty && selectedCategory != nil
    }

    func canSubmit(comparedTo purchase: Purchase?, calendar: Calendar = .current) -> Bool {
        guard canSave else { return false }
        guard let purchase else { return true }
        guard case let .quick(originalCategory, originalAmount) = purchase.kind,
              let normalizedMinorUnits
        else {
            return false
        }

        let originalMerchant = purchase.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return merchantTrimmed != originalMerchant
            || ExpenseCategoryPresentation.normalizedName(category)
                != ExpenseCategoryPresentation.normalizedName(originalCategory)
            || Int64(normalizedMinorUnits) != originalAmount.minorUnits
            || !calendar.isDate(spentAt, inSameDayAs: purchase.spentAt)
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

    func purchaseDraft(
        in context: ExpenseContext,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) throws -> PurchaseDraft {
        guard case let .personal(ownerID) = context,
              let normalizedMinorUnits,
              !merchantTrimmed.isEmpty,
              !category.isEmpty
        else {
            throw AppFailure.validation(fields: [:])
        }

        let amount = try Money(minorUnits: Int64(normalizedMinorUnits), currencyCode: "RUB")

        return PurchaseDraft(
            id: PurchaseID(rawValue: UUID()),
            ownerID: ownerID,
            groupID: nil,
            merchant: merchantTrimmed,
            spentAt: spentAt,
            localDate: Self.localDate(from: spentAt, calendar: calendar),
            timeZone: timeZone.identifier,
            kind: .quick(category: category, amount: amount)
        )
    }

    func updatedPurchase(
        _ purchase: Purchase,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) throws -> Purchase {
        guard case let .quick(_, originalAmount) = purchase.kind,
              let normalizedMinorUnits,
              !merchantTrimmed.isEmpty,
              !category.isEmpty
        else {
            throw AppFailure.validation(fields: [:])
        }

        return try Purchase.quick(
            id: purchase.id,
            ownerID: purchase.ownerID,
            groupID: purchase.groupID,
            merchant: merchantTrimmed,
            category: category,
            amount: Money(
                minorUnits: Int64(normalizedMinorUnits),
                currencyCode: originalAmount.currencyCode
            ),
            spentAt: spentAt,
            localDate: Self.localDate(from: spentAt, calendar: calendar),
            timeZone: timeZone.identifier,
            version: purchase.version
        )
    }

    static func localDate(from date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return utcCalendar.date(from: components) ?? date
    }

    private static func amountText(minorUnits: Int64) -> String {
        let majorUnits = minorUnits / 100
        let fractionalUnits = minorUnits % 100
        let rawValue: String

        if fractionalUnits == 0 {
            rawValue = String(majorUnits)
        } else if fractionalUnits.isMultiple(of: 10) {
            rawValue = "\(majorUnits),\(fractionalUnits / 10)"
        } else {
            rawValue = "\(majorUnits),\(String(format: "%02lld", fractionalUnits))"
        }

        return MoneyFormatter.inputText(from: rawValue)
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

    var tintHex: UInt32 {
        guard kind == .defaultCategory else { return ExpenseCategoryPresentation.customTintHex }
        return ExpenseCategoryPresentation.standard(matching: name)?.tintHex
            ?? ExpenseCategoryPresentation.customTintHex
    }

    var tint: Color {
        Color(hex: tintHex)
    }

    var symbolName: String {
        guard kind == .defaultCategory else { return ExpenseCategoryPresentation.customSymbolName }
        return ExpenseCategoryPresentation.standard(matching: name)?.symbolName
            ?? ExpenseCategoryPresentation.customSymbolName
    }

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

private actor AddExpensePreviewPurchaseRepository: PurchaseRepository {
    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase] { [] }
    func purchasePage(in context: ExpenseContext, after cursor: String?, limit: Int) async throws -> PurchasePage {
        PurchasePage(purchases: [], nextCursor: nil, hasMore: false)
    }
    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase {
        try RepositoryMapping.optimisticPurchase(from: draft)
    }
    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase { throw AppFailure.unknown }
    func delete(id: PurchaseID, expectedVersion: Int64) async throws {}
}

@MainActor
enum AddExpenseCategoryStore {
    static let defaultCategories = ExpenseCategoryPresentation.standardCategories
        .map { AddExpenseCategory.defaultCategory(name: $0.name) }

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
        ExpenseCategoryPresentation.normalizedName(value)
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
        ExpenseCategoryPresentation.displayName(value)
    }
}

#Preview {
    AddExpenseView(scope: .personal) { _ in }
}
