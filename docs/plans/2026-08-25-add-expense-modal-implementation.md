# Add Expense Modal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Построить отдельный модальный экран создания расхода с iOS-native формой и валидацией обязательных полей.

**Architecture:** Экран добавления расхода выделяется в отдельный feature-файл и показывается через `sheet` из вкладки расходов. Внутри `NavigationStack` размещается форма ввода, а сохранение управляется локальным draft-state и UI-валидацией.

**Tech Stack:** Swift 6, SwiftUI, Observation, XcodeGen, Xcode build.

---

### Task 1: Выделить отдельный экран добавления расхода

**Files:**
- Create: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`
- Modify: `ios/Spendly/Features/Expenses/ExpensesHomeView.swift`

**Step 1: Создать локальную draft-модель**

Добавить `AddExpenseDraft` с полями суммы, названия, категории и даты. Добавить вычисление `canSave`.

**Step 2: Построить модальный экран**

Собрать `NavigationStack`-экран с:
- заголовком `Новая трата`;
- кнопкой отмены `xmark` слева;
- кнопкой сохранения `checkmark` справа;
- главным полем суммы;
- полями названия, категории, даты;
- действием `Добавить товары`.

**Step 3: Подключить экран вместо текущей заглушки**

`plus` в `ExpensesHomeView` должен открывать `AddExpenseView`, а не `ContentUnavailableView`.

**Step 4: Проверить сборку**

Run:

```bash
xcodebuild build -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `BUILD SUCCEEDED`

### Task 2: Привести взаимодействие к нативному виду

**Files:**
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`

**Step 1: Отключить сохранение до валидного состояния**

Пока сумма и название невалидны, правая верхняя кнопка должна быть disabled и серой.

**Step 2: Оформить вторичные действия**

`Добавить товары` оставить как отдельную строку действия с системной иконкой и placeholder-поведением до следующего шага.

**Step 3: Проверить сценарии закрытия**

- отмена закрывает sheet;
- сохранение закрывает sheet;
- кнопка сохранения не нажимается в невалидном состоянии.

Plan complete and saved to `docs/plans/2026-08-25-add-expense-modal-implementation.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, fast iteration

2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Given the current flow, implementation continues in this session.
