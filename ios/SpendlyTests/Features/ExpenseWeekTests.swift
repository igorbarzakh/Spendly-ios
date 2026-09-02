import XCTest
@testable import Spendly

final class ExpenseWeekTests: XCTestCase {
    func testBuildsCurrentWeekInsideSingleMonth() throws {
        let calendar = makeCalendar()
        let today = try makeDate(year: 2026, month: 8, day: 19, calendar: calendar)

        let week = ExpenseWeek.current(containing: today, calendar: calendar)

        XCTAssertEqual(week.days.map(\.weekday), ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"])
        XCTAssertEqual(week.days.map(\.day), [17, 18, 19, 20, 21, 22, 23])
        XCTAssertEqual(week.today?.day, 19)
    }

    func testBuildsCurrentWeekAcrossMonthBoundary() throws {
        let calendar = makeCalendar()
        let today = try makeDate(year: 2026, month: 9, day: 2, calendar: calendar)

        let week = ExpenseWeek.current(containing: today, calendar: calendar)

        XCTAssertEqual(week.days.map(\.day), [31, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(week.today?.day, 2)
    }

    func testBuildsCurrentWeekAcrossYearBoundary() throws {
        let calendar = makeCalendar()
        let today = try makeDate(year: 2027, month: 1, day: 1, calendar: calendar)

        let week = ExpenseWeek.current(containing: today, calendar: calendar)

        XCTAssertEqual(week.days.map(\.day), [28, 29, 30, 31, 1, 2, 3])
        XCTAssertEqual(week.today?.day, 1)
    }

    func testIdentifiesTodayByCalendarDate() throws {
        let calendar = makeCalendar()
        let today = try makeDate(year: 2026, month: 6, day: 8, calendar: calendar)

        let week = ExpenseWeek.current(containing: today, calendar: calendar)

        XCTAssertTrue(week.days[0].isToday)
        XCTAssertFalse(week.days[1].isToday)
    }

    func testFormatsMonthTitlesInRussian() throws {
        let calendar = makeCalendar()
        let date = try makeDate(year: 2026, month: 9, day: 2, calendar: calendar)

        XCTAssertEqual(ExpenseDateText.monthTitle(for: date), "Сентябрь")
        XCTAssertEqual(ExpenseDateText.dayMonthTitle(for: date), "2 сентября")
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
