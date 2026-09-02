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

    func testBuildsWeekContainingSelectedDateWhileIdentifyingRealTodaySeparately() throws {
        let calendar = makeCalendar()
        let selectedDate = try makeDate(year: 2026, month: 9, day: 30, calendar: calendar)
        let today = try makeDate(year: 2026, month: 10, day: 2, calendar: calendar)

        let week = ExpenseWeek.current(containing: selectedDate, today: today, calendar: calendar)

        XCTAssertEqual(week.days.map(\.day), [28, 29, 30, 1, 2, 3, 4])
        XCTAssertEqual(week.today?.day, 2)
    }

    func testMovingSelectedDateByWeekPreservesWeekdayAcrossMonthBoundary() throws {
        let calendar = makeCalendar()
        let selectedDate = try makeDate(year: 2026, month: 9, day: 30, calendar: calendar)

        let nextWeek = try XCTUnwrap(ExpenseWeek.date(byMoving: selectedDate, weeks: 1, calendar: calendar))
        let previousWeek = try XCTUnwrap(ExpenseWeek.date(byMoving: selectedDate, weeks: -1, calendar: calendar))

        XCTAssertEqual(dayComponents(for: nextWeek, calendar: calendar), DateComponents(year: 2026, month: 10, day: 7))
        XCTAssertEqual(dayComponents(for: previousWeek, calendar: calendar), DateComponents(year: 2026, month: 9, day: 23))
        XCTAssertEqual(calendar.component(.weekday, from: nextWeek), calendar.component(.weekday, from: selectedDate))
        XCTAssertEqual(calendar.component(.weekday, from: previousWeek), calendar.component(.weekday, from: selectedDate))
    }

    func testMovingSelectedDateByWeekPreservesWeekdayAcrossYearBoundary() throws {
        let calendar = makeCalendar()
        let selectedDate = try makeDate(year: 2026, month: 12, day: 31, calendar: calendar)

        let nextWeek = try XCTUnwrap(ExpenseWeek.date(byMoving: selectedDate, weeks: 1, calendar: calendar))
        let previousWeek = try XCTUnwrap(ExpenseWeek.date(byMoving: selectedDate, weeks: -1, calendar: calendar))

        XCTAssertEqual(dayComponents(for: nextWeek, calendar: calendar), DateComponents(year: 2027, month: 1, day: 7))
        XCTAssertEqual(dayComponents(for: previousWeek, calendar: calendar), DateComponents(year: 2026, month: 12, day: 24))
    }

    func testMovingSelectedDateByWeekHandlesFebruaryInLeapYear() throws {
        let calendar = makeCalendar()
        let selectedDate = try makeDate(year: 2028, month: 2, day: 29, calendar: calendar)

        let nextWeek = try XCTUnwrap(ExpenseWeek.date(byMoving: selectedDate, weeks: 1, calendar: calendar))
        let previousWeek = try XCTUnwrap(ExpenseWeek.date(byMoving: selectedDate, weeks: -1, calendar: calendar))

        XCTAssertEqual(dayComponents(for: nextWeek, calendar: calendar), DateComponents(year: 2028, month: 3, day: 7))
        XCTAssertEqual(dayComponents(for: previousWeek, calendar: calendar), DateComponents(year: 2028, month: 2, day: 22))
    }

    func testPagingRequiresActualDistanceThreshold() {
        XCTAssertEqual(ExpenseWeekPaging.weekOffset(translation: -149, pageWidth: 300), 0)
        XCTAssertEqual(ExpenseWeekPaging.weekOffset(translation: 149, pageWidth: 300), 0)
        XCTAssertEqual(ExpenseWeekPaging.weekOffset(translation: -150, pageWidth: 300), 1)
        XCTAssertEqual(ExpenseWeekPaging.weekOffset(translation: 150, pageWidth: 300), -1)
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

    private func dayComponents(for date: Date, calendar: Calendar) -> DateComponents {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DateComponents(year: components.year, month: components.month, day: components.day)
    }
}
