# Persistent Monthly Limit Block Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Сделать блок месячного лимита постоянным и убрать из него повтор потраченной суммы.

**Architecture:** `DashboardSamples` предоставляет отдельную сумму расходов текущего месяца. `DashboardView` использует выбранный снимок только для крупной сводки, а бюджет строит из стабильной месячной суммы независимо от переключателя.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen, iOS 17+.

---

### Task 1: Отделить месячную метрику от выбранного периода

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardModels.swift`
- Modify: `ios/SpendlyTests/Features/DashboardModelsTests.swift`

**Step 1:** Написать падающий тест для `DashboardSamples.currentMonthTotalMinorUnits`.

**Step 2:** Запустить `DashboardModelsTests` и подтвердить отсутствие нового API.

**Step 3:** Добавить месячную метрику, согласованную со снимком `.month`.

**Step 4:** Повторно запустить модельные тесты и подтвердить GREEN.

### Task 2: Перекомпоновать постоянный блок лимита

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

**Step 1:** Удалить условие показа блока по `.month`.

**Step 2:** Рассчитывать прогресс из `currentMonthTotalMinorUnits`, а не из выбранной сводки.

**Step 3:** Заменить строку «потрачено из лимита» на заголовок «Лимит месяца» и значение лимита справа.

**Step 4:** Обновить VoiceOver-подпись без визуального дублирования суммы.

### Task 3: Проверка

**Files:**
- Modify only if verification exposes an in-scope issue.

**Step 1:** Выполнить `xcodegen generate`.

**Step 2:** Запустить полный `xcodebuild test` на iPhone 17 Pro.

**Step 3:** Запустить `xcodebuild build` и `git diff --check`.

**Step 4:** Проверить поиском, что старый текст «из» с потраченной суммой не остался в блоке.
