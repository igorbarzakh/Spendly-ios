# Transaction Save Haptic Design

Creating or updating a transaction produces a soft, reduced-intensity impact only after the repository confirms success. A successful deletion produces a separate medium impact. Both feedback actions are injected into `AddExpenseModel`, keeping tests deterministic and ensuring failed operations never produce feedback. `AddExpenseView` supplies the live `UIImpactFeedbackGenerator` implementations.
