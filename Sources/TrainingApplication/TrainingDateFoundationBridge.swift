import Foundation
import TrainingDomain

extension TrainingDate {
  private static var timezoneFreeCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }

  public init(date: Date, calendar: Calendar = .current) {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(
      year: components.year ?? 2000,
      month: components.month ?? 1,
      day: components.day ?? 1
    )
  }

  public func date(in calendar: Calendar = .current) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))
      ?? Date(timeIntervalSince1970: 0)
  }

  public func date() -> Date { date(in: Self.timezoneFreeCalendar) }

  public static func monday(containing date: Date, calendar: Calendar = .current) -> TrainingDate {
    let day = calendar.component(.weekday, from: date)
    let daysFromMonday = (day + 5) % 7
    let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
    return TrainingDate(date: monday, calendar: calendar)
  }
}
