# Summary and Budget Card Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Объединить сводку расходов и месячный лимит в одну просторную белую карточку.

**Architecture:** `DashboardView` получает единый контейнер `summaryCard`, внутри которого остаются существующие `summary` и `monthlyLimit`. Логика периода, прогресса, хранения и редактирования не меняется; меняются только уровни визуальных поверхностей и интервалы.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen, iOS 17+.

---

### Task 1: Объединить поверхности

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

**Step 1:** Заменить соседние `summary` и `monthlyLimit` в корневом стеке на единый `summaryCard`.

**Step 2:** Разместить сводку и кнопку лимита в `VStack` с интервалом около 30 pt.

**Step 3:** Применить общие внутренние отступы, белую поверхность, скругление и одну тень ко всей карточке.

**Step 4:** Удалить фон и тень из заполненного блока лимита; сохранить всю область блока интерактивной.

**Step 5:** Адаптировать состояние «Установить лимит» для размещения внутри общей карточки.

### Task 2: Проверить реализацию

**Files:**
- Modify only if verification exposes an in-scope issue.

**Step 1:** Выполнить `xcodegen generate`.

**Step 2:** Запустить полный `xcodebuild test` на iPhone 17 Pro.

**Step 3:** Запустить `xcodebuild build` и `git diff --check`.

**Step 4:** Просмотреть `DashboardView.swift` и убедиться, что внутри общей карточки нет второй поверхности или второй тени.
