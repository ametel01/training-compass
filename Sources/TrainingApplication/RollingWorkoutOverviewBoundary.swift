import Foundation
import TrainingInsights

public protocol RollingWorkoutZoneProjectionProviding: Sendable {
  func zoneTimes(
    for workout: HealthWorkout,
    enrichment: HealthWorkoutEnrichment?
  ) async -> RollingWorkoutZoneTimeAvailability
}

public struct RollingWorkoutOverviewBoundary: Sendable {
  private let repository: any HealthWorkoutRepository
  private let clock: any Clock
  private let calendarProvider: any CalendarProvider
  private let zoneProvider: (any RollingWorkoutZoneProjectionProviding)?

  public init(
    repository: any HealthWorkoutRepository,
    clock: any Clock = SystemClock(),
    calendar: any CalendarProvider = CurrentCalendarProvider(),
    zoneProvider: (any RollingWorkoutZoneProjectionProviding)? = nil
  ) {
    self.repository = repository
    self.clock = clock
    self.calendarProvider = calendar
    self.zoneProvider = zoneProvider
  }

  public func overview(asOf date: TrainingDate? = nil) async throws -> RollingWorkoutOverview {
    let asOf = date ?? TrainingDate(date: clock.now(), calendar: calendarProvider.calendar())
    let deleted = Set(try await repository.loadHealthWorkoutDeletionUUIDs())
    let storedWorkouts = try await repository.loadHealthWorkouts()
    let workoutsByID = Dictionary(
      storedWorkouts.map { ($0.healthKitUUID, $0) },
      uniquingKeysWith: { first, replacement in
        replacement.firstImportedAt >= first.firstImportedAt ? replacement : first
      })
    var records: [RollingWorkoutRecord] = []
    for workout in workoutsByID.values where !deleted.contains(workout.healthKitUUID) {
      guard let localDate = Self.parse(localDate: workout.localDate) else { continue }
      let enrichment = try await repository.loadHealthWorkoutEnrichment(
        for: workout.healthKitUUID)
      let zoneTimes =
        await zoneProvider?.zoneTimes(for: workout, enrichment: enrichment)
        ?? .unavailable(reason: Self.zoneUnavailableReason(for: enrichment))
      records.append(
        RollingWorkoutRecord(
          id: workout.healthKitUUID,
          localDate: localDate,
          activityType: workout.activityType,
          durationSeconds: workout.duration.isFinite ? workout.duration : nil,
          zoneTimes: zoneTimes))
    }
    records.sort {
      if $0.localDate != $1.localDate { return $0.localDate < $1.localDate }
      return $0.id < $1.id
    }
    let checkpoint = try await repository.loadHealthSyncCheckpoint(for: .workouts)
    let coverage: RollingWorkoutSourceCoverage
    if let checkpoint, !checkpoint.hasLimitedHistory {
      coverage = .complete(lastReconciliation: checkpoint.committedAt.description)
    } else if let checkpoint {
      coverage = .incomplete(
        reason:
          "Health Workouts stream reported limited history; the complete comparison horizon is unavailable",
        lastReconciliation: checkpoint.committedAt.description)
    } else {
      coverage = .incomplete(
        reason:
          "Health Workouts stream has not successfully checked the complete comparison horizon")
    }
    return RollingWorkoutOverviewCalculator().calculate(
      records: records,
      asOf: asOf,
      coverage: coverage)
  }

  private static func zoneUnavailableReason(for enrichment: HealthWorkoutEnrichment?) -> String {
    guard let enrichment else { return "Heart-rate enrichment has not been checked" }
    switch enrichment.heartRate.state {
    case .available: return "Heart-Rate Zone projection is not configured"
    case .loading: return "Heart-rate enrichment is still loading"
    case .notAvailableFromHealth: return "Heart-rate samples are not available from Health"
    case .failed: return "Heart-rate enrichment failed"
    }
  }

  private static func parse(localDate: String) -> TrainingDate? {
    let components = localDate.split(separator: "-").compactMap { Int($0) }
    guard components.count == 3 else { return nil }
    let year = components[0]
    let month = components[1]
    let day = components[2]
    guard year > 0, (1...12).contains(month) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
      return nil
    }
    let verified = calendar.dateComponents([.year, .month, .day], from: date)
    guard verified.year == year, verified.month == month, verified.day == day else { return nil }
    return TrainingDate(year: year, month: month, day: day)
  }
}
