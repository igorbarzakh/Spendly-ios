import Foundation

struct ExpenseWeek {
    let days: [ExpenseDay]

    var today: ExpenseDay? {
        days.first(where: \.isToday)
    }

    static func current(containing date: Date = Date(), calendar: Calendar = .current) -> ExpenseWeek {
        var calendar = calendar
        calendar.firstWeekday = 2

        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return ExpenseWeek(days: [])
        }

        let days = (0..<7).compactMap { offset -> ExpenseDay? in
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return nil
            }

            let components = calendar.dateComponents([.day], from: dayDate)
            guard let day = components.day else {
                return nil
            }

            return ExpenseDay(
                weekday: ExpenseWeek.weekdayTitles[offset],
                day: day,
                date: calendar.startOfDay(for: dayDate),
                isToday: calendar.isDate(dayDate, inSameDayAs: date)
            )
        }

        return ExpenseWeek(days: days)
    }

    private static let weekdayTitles = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
}

struct ExpenseDay: Identifiable {
    let weekday: String
    let day: Int
    let date: Date
    let isToday: Bool

    var id: Date { date }
}

enum ExpenseDateText {
    static func monthTitle(for date: Date) -> String {
        date
            .formatted(.dateTime.month(.wide).locale(russianLocale))
            .capitalizedFirstLetter
    }

    static func dayMonthTitle(for date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(russianLocale))
    }

    private static let russianLocale = Locale(identifier: "ru_RU")
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else {
            return self
        }

        return String(first).uppercased() + dropFirst()
    }
}
