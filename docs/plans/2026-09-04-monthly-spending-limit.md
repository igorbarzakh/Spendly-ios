# Monthly Spending Limit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Заменить сравнение с прошлым периодом на компактную шкалу месячного лимита с локальным редактированием.

**Architecture:** Чистая модель `DashboardBudgetProgress` рассчитывает долю заполнения, остаток и превышение без зависимости от SwiftUI. `DashboardView` хранит необязательный лимит через `@AppStorage`, показывает блок только для периода `.month` и открывает отдельный sheet для редактирования суммы.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, XcodeGen, iOS 17+.

---

### Task 1: Модель прогресса бюджета

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardModels.swift`
- Modify: `ios/SpendlyTests/Features/DashboardModelsTests.swift`

**Step 1: Написать падающие тесты**

Добавить тесты желаемого API `DashboardBudgetProgress(spentMinorUnits:limitMinorUnits:)`: обычный прогресс 84 320 / 100 000, ограничение визуального прогресса единицей, остаток и превышение.

**Step 2: Запустить тесты и подтвердить RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SpendlyTests/DashboardModelsTests
```

Expected: FAIL, потому что `DashboardBudgetProgress` еще не существует.

**Step 3: Реализовать минимальную модель**

Добавить тип с `fraction`, `remainingMinorUnits`, `overageMinorUnits` и `isOverLimit`. Долю ограничивать диапазоном `0...1`, а входные суммы нормализовать до неотрицательных значений.

**Step 4: Удалить устаревшее сравнение**

Удалить `comparisonText` из `DashboardSnapshot`, демонстрационных снимков и соответствующих проверок.

**Step 5: Запустить модельные тесты и подтвердить GREEN**

Expected: все `DashboardModelsTests` проходят.

### Task 2: Шкала и локальное редактирование лимита

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

**Step 1: Подключить локальное состояние**

Добавить `@AppStorage` для лимита в минорных единицах. Значение по умолчанию — 10 000 000 минорных единиц (100 000 ₽); специальное значение `0` означает отсутствие лимита.

**Step 2: Заменить сравнение на месячный блок**

Для `.month` показать кнопку под основной суммой: подпись «потрачено из лимита», тонкий `ProgressView`, остаток или превышение. Для `.day` и `.year` блок не создавать. При отсутствии лимита показать «Установить лимит».

**Step 3: Реализовать sheet редактирования**

Создать приватный SwiftUI-компонент с цифровым `TextField`, кнопкой «Сохранить» и действием «Удалить лимит». Валидировать положительное целое количество рублей, преобразовывать его в минорные единицы и закрывать sheet после успешного действия.

**Step 4: Добавить доступность**

Объединить подписи шкалы для VoiceOver, дать кнопке понятный hint и не полагаться только на цвет при превышении.

**Step 5: Проверить сборку**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `BUILD SUCCEEDED`.

### Task 3: Полная проверка

**Files:**
- Modify only if verification exposes an in-scope issue.

**Step 1: Перегенерировать проект**

Run: `xcodegen generate`

Expected: новые и измененные Swift-файлы входят в проект.

**Step 2: Запустить полный набор тестов**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `TEST SUCCEEDED`.

**Step 3: Проверить итоговый diff**

Run: `git diff --check` and inspect `git diff`.

Expected: нет whitespace-ошибок, упоминаний старого сравнения и несвязанных изменений.
