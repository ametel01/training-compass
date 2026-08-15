import Foundation
import TrainingInsights

/// Application vocabulary aliases keep the baseline API discoverable beside
/// the Health recovery projections while the statistical implementation stays
/// in the framework-free TrainingInsights module.
public typealias HealthRecoveryBaselineMetric = PersonalRecoveryBaselineMetric
public typealias HealthRecoveryBaseline = PersonalRecoveryBaseline

public typealias HealthRecoveryBaselineProjection = PersonalRecoveryBaselineProjection

extension HealthRecoveryEvidenceSnapshot {
  /// Calculates one independent Personal Recovery Baseline for each eligible
  /// Recovery Evidence measure. Primary Sleep is the only sleep episode used;
  /// Naps remain descriptive and never enter these baselines.
  public func personalRecoveryBaselines(
    preference: SleepSourcePreference = .init(),
    calendar: Calendar = .current,
    asOfDate: TrainingDate? = nil,
    now: Date = Date()
  ) -> PersonalRecoveryBaselineProjection {
    let effectiveDate = asOfDate ?? TrainingDate(date: now, calendar: calendar)
    let daily = dailyObservations(calendar: calendar, now: now)
    let sleep = sleepEpisodes(preference: preference, calendar: calendar)
    var inputs: [PersonalRecoveryBaselineMetric: [PersonalRecoveryBaselineObservation]] = [:]
    inputs[.restingHeartRate] = daily.restingHeartRate.map(Self.baselineInput)
    inputs[.heartRateVariabilitySDNN] = daily.heartRateVariability.map(Self.baselineInput)

    let primary = sleep.primarySleepEpisodes
    let durationInputs = primary.map { episode in
      Self.sleepInput(
        episode: episode,
        metric: .primarySleepDuration,
        value: episode.durationSeconds,
        status: sleep.status,
        calendar: calendar,
        now: now)
    }
    inputs[.primarySleepDuration] = durationInputs
    inputs[.sleepDurationConsistency] = Self.consistencyInputs(
      episodes: primary,
      metric: .sleepDurationConsistency,
      values: primary.map { $0.durationSeconds },
      status: sleep.status,
      calendar: calendar,
      now: now)
    inputs[.sleepTimingConsistency] = Self.consistencyInputs(
      episodes: primary,
      metric: .sleepTimingConsistency,
      values: primary.map { Self.timeOfDaySeconds($0.midpoint, calendar: calendar) },
      status: sleep.status,
      calendar: calendar,
      now: now)

    let projection = PersonalRecoveryBaselineCalculator().calculateProjection(
      observations: inputs, asOfDate: effectiveDate)
    return projection
  }

  /// Shorter aliases are provided for callers that use the screen's Recovery
  /// Evidence terminology rather than the glossary's full baseline name.
  public func recoveryBaselines(
    preference: SleepSourcePreference = .init(),
    calendar: Calendar = .current,
    asOfDate: TrainingDate? = nil,
    now: Date = Date()
  ) -> PersonalRecoveryBaselineProjection {
    personalRecoveryBaselines(
      preference: preference, calendar: calendar, asOfDate: asOfDate, now: now)
  }

  private static func baselineInput(
    _ observation: HealthRecoveryDailyObservation
  ) -> PersonalRecoveryBaselineObservation {
    PersonalRecoveryBaselineObservation(
      id: observation.id,
      date: observation.date,
      value: observation.value,
      sourceID: observation.source.id,
      sourceName: observation.source.displayName,
      sourceIsComparable: observation.source.isComparable,
      includedRecordIDs: observation.sampleIDs,
      sourceCoverage: observation.coverage.displayName,
      missingData: observation.explanation.missingData,
      algorithmVersions: observation.algorithmVersions,
      lastReconciliation: observation.lastSuccessfulReconciliation?.ISO8601Format(),
      isCurrent: observation.isCurrent)
  }

  private static func sleepInput(
    episode: SleepEpisode,
    metric: PersonalRecoveryBaselineMetric,
    value: Double,
    status: HealthStreamStatus?,
    calendar: Calendar,
    now: Date,
    algorithmVersions: [String] = ["sleep-episodes-v1"]
  ) -> PersonalRecoveryBaselineObservation {
    let current = status?.isCurrent(on: now, calendar: calendar) == true
    let source = episode.source
    let missing =
      episode.explanation.missingData
      + (status?.failure.map { ["Sleep stream failure: \($0.code)"] } ?? [])
    return PersonalRecoveryBaselineObservation(
      id: "\(metric.rawValue):\(episode.wakeUpDate.iso8601String):\(episode.id)",
      date: episode.wakeUpDate,
      value: value,
      sourceID: source.id,
      sourceName: source.displayName,
      sourceIsComparable: source.isComparable,
      includedRecordIDs: episode.intervals.map(\.id),
      sourceCoverage: status?.coverage.displayName ?? "Health sleep coverage unavailable",
      missingData: missing,
      algorithmVersions: algorithmVersions,
      lastReconciliation: status?.lastSuccessfulCheck?.ISO8601Format(),
      isCurrent: current)
  }

  /// Consistency is the population standard deviation of the current and up
  /// to six preceding same-source Primary Sleep values. This is deliberately a
  /// transparent variability measure, not a score or a sufficiency judgment.
  private static func consistencyInputs(
    episodes: [SleepEpisode],
    metric: PersonalRecoveryBaselineMetric,
    values: [Double],
    status: HealthStreamStatus?,
    calendar: Calendar,
    now: Date
  ) -> [PersonalRecoveryBaselineObservation] {
    guard episodes.count == values.count else { return [] }
    var result: [PersonalRecoveryBaselineObservation] = []
    for index in episodes.indices {
      let episode = episodes[index]
      guard episode.source.isComparable else { continue }
      let sourceID = episode.source.id
      let start = max(0, index - 6)
      let sameSource = zip(episodes[start...index], values[start...index])
        .filter { $0.0.source.isComparable && $0.0.source.id == sourceID }
        .map(\.1)
      guard sameSource.count >= 2 else { continue }
      let mean = sameSource.reduce(0, +) / Double(sameSource.count)
      let variance =
        sameSource.reduce(0) { partial, value in
          let difference = value - mean
          return partial + difference * difference
        } / Double(sameSource.count)
      let deviation = sqrt(variance)
      result.append(
        sleepInput(
          episode: episode,
          metric: metric,
          value: deviation,
          status: status,
          calendar: calendar,
          now: now,
          algorithmVersions: ["sleep-episodes-v1", "recovery-consistency-v1"]))
    }
    return result
  }

  private static func timeOfDaySeconds(_ date: Date, calendar: Calendar) -> Double {
    let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
    return Double(components.hour ?? 0) * 3_600
      + Double(components.minute ?? 0) * 60
      + Double(components.second ?? 0)
      + Double(components.nanosecond ?? 0) / 1_000_000_000
  }
}
