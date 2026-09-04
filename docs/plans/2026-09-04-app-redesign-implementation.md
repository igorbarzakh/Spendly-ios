# Spendly Main Screen Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Заменить старую главную вкладку на адаптивный демонстрационный дашборд расходов по утвержденному светлому дизайну.

**Architecture:** `ExpensesHomeView` сохраняет существующий `TabView`, а содержимое первой вкладки передает новому `DashboardView`. Типизированные демонстрационные снимки отделяются от SwiftUI-компонентов, а действие добавления продолжает открывать существующий `AddExpenseView`.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen, iOS 17+.

---

### Task 1: Описать периоды и демонстрационные снимки

**Files:**
- Create: `ios/Spendly/Features/Dashboard/DashboardModels.swift`
- Create: `ios/SpendlyTests/Features/DashboardModelsTests.swift`

**Step 1: Написать падающий тест порядка периодов**

Проверить, что `DashboardPeriod.allCases` содержит `.day`, `.month`, `.year` с пользовательскими названиями `День`, `Месяц`, `Год`.

**Step 2: Запустить тест и подтвердить RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SpendlyTests/DashboardModelsTests
```

Expected: FAIL, потому что `DashboardPeriod` еще не определен.

**Step 3: Реализовать минимальную модель периода**

Добавить `DashboardPeriod: String, CaseIterable, Identifiable` с русскими названиями и стабильным `id`.

**Step 4: Запустить тест и подтвердить GREEN**

Expected: выбранный тест проходит.

**Step 5: Написать падающие тесты демонстрационных данных**

Для каждого периода проверить положительную итоговую сумму и наличие последних операций.

**Step 6: Реализовать минимальные типы данных**

Добавить `DashboardSnapshot`, `DashboardTransaction` и фабрику демонстрационных снимков. Операция хранит название, категорию, дату, сумму, SF Symbol и цветовой стиль категории без логотипа магазина.

**Step 7: Запустить модельные тесты**

Expected: все `DashboardModelsTests` проходят.

### Task 2: Собрать новый дашборд

**Files:**
- Create: `ios/Spendly/Features/Dashboard/DashboardView.swift`
- Modify: `ios/Spendly/Core/DesignSystem/AppColor.swift`

**Step 1: Добавить семантические роли дизайна**

Добавить сфокусированные токены для фона дашборда, поверхности, текста, разделителя и индигового акцента. Существующие токены других экранов не менять.

**Step 2: Создать каркас `DashboardView`**

Использовать `ScrollView` и `LazyVStack` для сводки, быстрого добавления и последних операций. Передать `onAddTransaction` через closure, чтобы представление не управляло презентацией формы напрямую.

**Step 3: Реализовать период и главную метрику**

Использовать нативный segmented `Picker`. Выбранный период должен менять весь `DashboardSnapshot`, сумму и операции согласованно.

**Step 4: Реализовать быстрое добавление и операции**

Собрать доступную карточку-кнопку и секцию последних операций. Отображать SF Symbols категорий в цветных контейнерах, системные разделители и форматированную отрицательную сумму.

**Step 5: Проверить сборку нового компонента**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `BUILD SUCCEEDED`.

### Task 3: Подключить редизайн и удалить старую главную

**Files:**
- Modify: `ios/Spendly/Features/Expenses/ExpensesHomeView.swift`
- Delete: `ios/Spendly/Features/Expenses/ExpenseWeek.swift`
- Delete: `ios/SpendlyTests/Features/ExpenseWeekTests.swift`
- Modify: `ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift`

**Step 1: Подключить `DashboardView` к первой вкладке**

Сохранить структуру и названия существующего `TabView`. В первой вкладке открыть `DashboardView`, а `onAddTransaction` связать с существующим sheet `AddExpenseView`.

**Step 2: Убедиться, что действие добавления работает**

Проверить, что карточка `Добавить транзакцию` открывает текущую форму и не меняет поведение остальных вкладок.

**Step 3: Удалить недостижимый UI**

Удалить недельный календарь, paging-логику, старую дневную сводку, прежние строки расходов и детали-заглушку из `ExpensesHomeView.swift`.

**Step 4: Удалить осиротевшие вспомогательные типы и тесты**

После проверки через `rg` удалить `ExpenseWeek.swift`, `ExpenseWeekTests.swift` и тесты `ExpensesScrollState`, если эти символы больше нигде не используются.

**Step 5: Перегенерировать Xcode-проект**

Run:

```bash
xcodegen generate
```

Expected: проект включает новые файлы и не содержит удаленных.

### Task 4: Проверить светлый дизайн

**Files:**
- Modify only if verification exposes an in-scope issue.

**Step 1: Запустить iOS-тесты**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `TEST SUCCEEDED`.

**Step 2: Проверить сборку**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `BUILD SUCCEEDED`.

**Step 3: Выполнить визуальную проверку**

Запустить приложение в симуляторе, проверить главный экран на iPhone 17 Pro и компактном iPhone, прокрутку, выбор периода, открытие формы добавления и читаемость при увеличенном размере текста.

**Step 4: Проверить итоговый diff и мертвый код**

Использовать `git diff --check`, `git diff --stat` и `rg` по удаленным символам. Убедиться, что backend, авторизация, другие вкладки и существующая форма добавления не получили несвязанных изменений.
