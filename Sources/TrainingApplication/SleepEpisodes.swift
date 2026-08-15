import Foundation

/// A stable, application-owned identity for a Health sleep source.
///
/// HealthKit may omit some provenance fields.  Such a source is intentionally
/// marked incomparable: intervals with no stable source identity are never
/// joined across one another or used to invent continuity.
public struct HealthSleepSource: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public let displayName: String
  public let isComparable: Bool

  public init(id: String, displayName: String, isComparable: Bool = true) {
    precondition(!id.isEmpty)
    self.id = id
    self.displayName = displayName.isEmpty ? "Source unavailable" : displayName
    self.isComparable = isComparable
  }

  public init(provenance: HealthRecoverySampleProvenance) {
    if let bundle = Self.nonEmpty(provenance.sourceBundleIdentifier) {
      self.init(
        id: "bundle:\(bundle)",
        displayName: provenance.displayName,
        isComparable: true)
    } else if let product = Self.nonEmpty(provenance.sourceProductType) {
      self.init(
        id: "product:\(product)",
        displayName: provenance.displayName,
        isComparable: true)
    } else if let name = Self.nonEmpty(provenance.sourceName) {
      self.init(
        id: "name:\(name)",
        displayName: provenance.displayName,
        isComparable: true)
    } else if let device = Self.nonEmpty(provenance.deviceName) {
      self.init(
        id: "device:\(device)",
        displayName: provenance.displayName,
        isComparable: true)
    } else {
      self.init(id: "unavailable", displayName: provenance.displayName, isComparable: false)
    }
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return value
  }
}

/// Owner-controlled ordering for sleep sources.  Unknown sources are retained
/// and placed after configured sources, so adding a new Health source never
/// silently displaces an owner's existing preference.
public struct SleepSourcePreference: Codable, Equatable, Sendable {
  public let orderedSourceIDs: [String]

  public init(orderedSourceIDs: [String] = []) {
    var seen = Set<String>()
    self.orderedSourceIDs = orderedSourceIDs.filter {
      !$0.isEmpty && seen.insert($0).inserted
    }
  }

  public init(sources: [HealthSleepSource]) {
    self.init(orderedSourceIDs: sources.map(\.id))
  }

  public func rank(for source: HealthSleepSource) -> Int {
    guard source.isComparable else { return Int.max }
    return orderedSourceIDs.firstIndex(of: source.id) ?? Int.max - 1
  }

  public func reordered(sourceIDs: [String]) -> Self {
    Self(orderedSourceIDs: sourceIDs)
  }

  public func moving(sourceID: String, to index: Int) -> Self {
    var values = orderedSourceIDs.filter { $0 != sourceID }
    let boundedIndex = min(max(0, index), values.count)
    values.insert(sourceID, at: boundedIndex)
    return Self(orderedSourceIDs: values)
  }

  public func orderedSources(_ sources: [HealthSleepSource]) -> [HealthSleepSource] {
    sources.sorted { lhs, rhs in
      let leftRank = rank(for: lhs)
      let rightRank = rank(for: rhs)
      if leftRank != rightRank { return leftRank < rightRank }
      return lhs.id < rhs.id
    }
  }
}

public typealias PreferredSleepSource = SleepSourcePreference

public enum SleepEpisodeKind: String, Codable, Equatable, Sendable {
  case primarySleep
  case nap

  public var displayName: String {
    switch self {
    case .primarySleep: "Primary Sleep"
    case .nap: "Nap"
    }
  }
}

public struct SleepEpisodeInterval: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let startDate: Date
  public let endDate: Date
  public let source: HealthSleepSource

  public init(id: String, startDate: Date, endDate: Date, source: HealthSleepSource) {
    precondition(!id.isEmpty)
    precondition(endDate >= startDate)
    self.id = id
    self.startDate = startDate
    self.endDate = endDate
    self.source = source
  }

  public var durationSeconds: TimeInterval {
    max(0, endDate.timeIntervalSince(startDate))
  }
}

public struct SleepEpisode: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let kind: SleepEpisodeKind
  /// Sleep is assigned to the date on which the episode ends, not the date on
  /// which it starts.  This makes an episode crossing midnight belong to its
  /// wake-up date.
  public let wakeUpDate: TrainingDate
  public let startDate: Date
  public let endDate: Date
  public let midpoint: Date
  public let durationSeconds: TimeInterval
  public let source: HealthSleepSource
  public let intervals: [SleepEpisodeInterval]
  public let alternativeSources: [HealthSleepSource]
  public let explanation: InsightExplanation

  public init(
    id: String,
    kind: SleepEpisodeKind,
    wakeUpDate: TrainingDate,
    startDate: Date,
    endDate: Date,
    midpoint: Date,
    durationSeconds: TimeInterval,
    source: HealthSleepSource,
    intervals: [SleepEpisodeInterval],
    alternativeSources: [HealthSleepSource] = [],
    explanation: InsightExplanation
  ) {
    precondition(!id.isEmpty)
    precondition(endDate >= startDate)
    self.id = id
    self.kind = kind
    self.wakeUpDate = wakeUpDate
    self.startDate = startDate
    self.endDate = endDate
    self.midpoint = midpoint
    self.durationSeconds = max(0, durationSeconds)
    self.source = source
    self.intervals = intervals
    self.alternativeSources = alternativeSources
    self.explanation = explanation
  }

  public var duration: TimeInterval { durationSeconds }
  public var midpointDate: Date { midpoint }
  public var isPrimarySleep: Bool { kind == .primarySleep }
}

public struct SleepEpisodeProjection: Codable, Equatable, Sendable {
  public let episodes: [SleepEpisode]
  public let availableSources: [HealthSleepSource]
  public let preference: SleepSourcePreference
  public let status: HealthStreamStatus?
  public let explanation: InsightExplanation

  public init(
    episodes: [SleepEpisode] = [],
    availableSources: [HealthSleepSource] = [],
    preference: SleepSourcePreference = .init(),
    status: HealthStreamStatus? = nil,
    explanation: InsightExplanation
  ) {
    self.episodes = episodes
    self.availableSources = availableSources
    self.preference = preference
    self.status = status
    self.explanation = explanation
  }

  public func episodes(on date: TrainingDate) -> [SleepEpisode] {
    episodes.filter { $0.wakeUpDate == date }
  }

  public func primarySleep(on date: TrainingDate) -> SleepEpisode? {
    episodes(on: date).first { $0.kind == .primarySleep }
  }

  public func naps(on date: TrainingDate) -> [SleepEpisode] {
    episodes(on: date).filter { $0.kind == .nap }
  }

  public var primarySleepEpisodes: [SleepEpisode] {
    episodes.filter { $0.kind == .primarySleep }
  }

  public var napEpisodes: [SleepEpisode] {
    episodes.filter { $0.kind == .nap }
  }
}

/// Deterministically projects source-owned sleep intervals into Primary Sleep
/// and descriptive Nap episodes.  It deliberately has no HealthKit or
/// persistence dependency, making replacement and deletion ordinary input
/// changes that recompute the view without inventing continuity.
public struct SleepEpisodeCalculator: Sendable {
  public static let maximumAwakeGap: TimeInterval = 90 * 60

  public init() {}

  public func calculate(
    samples: [HealthSleepSample],
    preference: SleepSourcePreference = .init(),
    calendar: Calendar = Calendar(identifier: .gregorian),
    status: HealthStreamStatus? = nil
  ) -> SleepEpisodeProjection {
    let usable = samples.compactMap { sample -> RawInterval? in
      guard Self.isAsleep(sample.stage), sample.endDate > sample.startDate else { return nil }
      let source = HealthSleepSource(provenance: sample.provenance)
      return RawInterval(
        id: sample.id,
        startDate: sample.startDate,
        endDate: sample.endDate,
        source: source,
        groupingKey: source.isComparable ? source.id : "unavailable:\(sample.id)")
    }
    let sources = preference.orderedSources(Self.uniqueSources(from: usable))

    let candidates = Self.candidates(from: usable)
    let selected = candidates.filter { candidate in
      !candidates.contains { other in
        guard candidate.id != other.id, candidate.overlaps(other) else { return false }
        return Self.precedes(other, candidate, preference: preference)
      }
    }
    let intervalIDs = Set(usable.map(\.id))
    let selectedIDs = Set(selected.flatMap { $0.intervals.map(\.id) })
    let exclusions = usable.filter { !selectedIDs.contains($0.id) }.map {
      InsightExplanationExclusion(
        recordID: $0.id,
        reason: "Overlapping lower-priority or incomparable alternative sleep interval")
    }

    let grouped = Dictionary(grouping: selected) { candidate in
      Self.trainingDate(for: candidate.endDate, calendar: calendar)
    }
    var episodes: [SleepEpisode] = []
    for (wakeUpDate, dateCandidates) in grouped {
      let ordered = dateCandidates.sorted {
        if $0.duration != $1.duration { return $0.duration > $1.duration }
        if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
        return $0.id < $1.id
      }
      for (index, candidate) in ordered.enumerated() {
        let alternatives =
          candidates
          .filter { $0.id != candidate.id && candidate.overlaps($0) }
          .map(\.source)
          .filter { $0.id != candidate.source.id }
        let originalIntervals = candidate.intervals.map {
          SleepEpisodeInterval(
            id: $0.id,
            startDate: $0.startDate,
            endDate: $0.endDate,
            source: $0.source)
        }
        let episodeID = "sleep:\(wakeUpDate.iso8601String):\(candidate.id)"
        let episodeExplanation = Self.explanation(
          candidate: candidate,
          alternatives: alternatives,
          allIntervalIDs: intervalIDs,
          exclusions: exclusions,
          wakeUpDate: wakeUpDate,
          preference: preference,
          status: status)
        episodes.append(
          SleepEpisode(
            id: episodeID,
            kind: index == 0 ? .primarySleep : .nap,
            wakeUpDate: wakeUpDate,
            startDate: candidate.startDate,
            endDate: candidate.endDate,
            midpoint: candidate.startDate.addingTimeInterval(
              candidate.endDate.timeIntervalSince(candidate.startDate) / 2),
            durationSeconds: candidate.duration,
            source: candidate.source,
            intervals: originalIntervals,
            alternativeSources: Self.uniqueSources(from: alternatives),
            explanation: episodeExplanation))
      }
    }
    episodes.sort {
      if $0.wakeUpDate != $1.wakeUpDate { return $0.wakeUpDate < $1.wakeUpDate }
      if $0.kind != $1.kind { return $0.kind == .primarySleep }
      return $0.startDate < $1.startDate
    }

    let allDates = Set(episodes.map { $0.wakeUpDate.iso8601String }).sorted()
    let explanation = InsightExplanation(
      question: "Which recorded sleep episodes belong to each wake-up date?",
      includedRecordIDs: selected.flatMap { $0.intervals.map(\.id) },
      excludedRecords: [],
      formula:
        "Union asleep intervals from the selected source; merge gaps of at most 90 minutes; choose the longest episode per wake-up date as Primary Sleep and label all others Nap.",
      dateRange: allDates.isEmpty ? "No wake-up dates" : allDates.joined(separator: ", "),
      roundingRule:
        "Durations and midpoint use full-precision timestamps; no rounding is used for classification.",
      sourceState: sources.isEmpty
        ? "No comparable sleep source available"
        : sources.map(\.displayName).joined(separator: ", ")
          + (status.map { ". Stream state: \($0.statusLabel)." } ?? ""),
      includedDates: allDates,
      sourceCoverage: "Recorded asleep intervals only; missing intervals remain missing.",
      calculationRule:
        "Overlapping sources are represented once by the highest-priority usable source and are never summed.",
      missingData: (usable.isEmpty ? ["No usable asleep intervals"] : [])
        + (status?.failure.map { ["Sleep stream failure: \($0.code)"] } ?? [])
        + (status?.isUpdating == true ? ["Sleep stream reconciliation is still updating"] : []),
      exclusions: exclusions,
      lastReconciliation: status?.lastSuccessfulCheck?.ISO8601Format(),
      configuration: preference.orderedSourceIDs.isEmpty
        ? "No explicit source order; stable source identity tie-breaker"
        : preference.orderedSourceIDs.joined(separator: " > "))
    return SleepEpisodeProjection(
      episodes: episodes,
      availableSources: sources,
      preference: preference,
      status: status,
      explanation: explanation)
  }

  private static func isAsleep(_ stage: HealthSleepStage) -> Bool {
    switch stage {
    case .asleep, .asleepCore, .asleepDeep, .asleepREM: true
    case .inBed, .awake, .unknown: false
    }
  }

  private static func trainingDate(for date: Date, calendar: Calendar) -> TrainingDate {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return TrainingDate(
      year: components.year ?? 1,
      month: components.month ?? 1,
      day: components.day ?? 1)
  }

  private static func uniqueSources(from intervals: [RawInterval]) -> [HealthSleepSource] {
    uniqueSources(from: intervals.map(\.source))
  }

  private static func uniqueSources(from sources: [HealthSleepSource]) -> [HealthSleepSource] {
    var seen = Set<String>()
    return sources.filter { seen.insert($0.id).inserted }
  }

  private static func candidates(from intervals: [RawInterval]) -> [Candidate] {
    let grouped = Dictionary(grouping: intervals, by: \.groupingKey)
    return grouped.values.flatMap { values in
      let sorted = values.sorted {
        if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
        if $0.endDate != $1.endDate { return $0.endDate < $1.endDate }
        return $0.id < $1.id
      }
      var output: [Candidate] = []
      for interval in sorted {
        guard let last = output.last else {
          output.append(Candidate(intervals: [interval]))
          continue
        }
        if interval.startDate.timeIntervalSince(last.endDate) <= maximumAwakeGap {
          output[output.count - 1] = Candidate(intervals: last.intervals + [interval])
        } else {
          output.append(Candidate(intervals: [interval]))
        }
      }
      return output
    }
  }

  private static func precedes(
    _ lhs: Candidate,
    _ rhs: Candidate,
    preference: SleepSourcePreference
  ) -> Bool {
    guard lhs.source.isComparable, rhs.source.isComparable else { return false }
    let leftRank = preference.rank(for: lhs.source)
    let rightRank = preference.rank(for: rhs.source)
    if leftRank != rightRank { return leftRank < rightRank }
    if lhs.source.id != rhs.source.id { return lhs.source.id < rhs.source.id }
    return lhs.id < rhs.id
  }

  private static func explanation(
    candidate: Candidate,
    alternatives: [HealthSleepSource],
    allIntervalIDs: Set<String>,
    exclusions: [InsightExplanationExclusion],
    wakeUpDate: TrainingDate,
    preference: SleepSourcePreference,
    status: HealthStreamStatus?
  ) -> InsightExplanation {
    let included = candidate.intervals.map(\.id)
    let dateRange = "Wake-up date: \(wakeUpDate.iso8601String)"
    let sourceState =
      "Chosen source: \(candidate.source.displayName)"
      + (alternatives.isEmpty
        ? ". No overlapping alternative source."
        : ". Alternatives: " + alternatives.map(\.displayName).joined(separator: ", ") + ".")
    let missing =
      (allIntervalIDs.subtracting(included).isEmpty
        ? []
        : ["Intervals outside this selected episode are not continuity evidence"])
      + (status?.failure.map { ["Sleep stream failure: \($0.code)"] } ?? [])
    return InsightExplanation(
      question: "Why is this sleep episode represented by this source?",
      includedRecordIDs: included,
      excludedRecords: [],
      formula:
        "Asleep intervals from one comparable source joined when the awake gap is at most 90 minutes.",
      dateRange: dateRange,
      roundingRule: "Full-precision timestamps; duration is the union of asleep intervals.",
      sourceState: sourceState,
      includedDates: [wakeUpDate.iso8601String],
      sourceCoverage: "Source provenance is retained for every included interval.",
      calculationRule:
        "Higher-priority overlapping sources replace alternatives; alternatives are not added.",
      missingData: missing,
      exclusions: exclusions,
      lastReconciliation: status?.lastSuccessfulCheck?.ISO8601Format(),
      configuration: preference.orderedSourceIDs.joined(separator: " > "))
  }

  private struct RawInterval: Sendable {
    let id: String
    let startDate: Date
    let endDate: Date
    let source: HealthSleepSource
    let groupingKey: String
  }

  private struct Candidate: Sendable {
    let intervals: [RawInterval]

    var id: String { intervals.map(\.id).sorted().joined(separator: "+") }
    var source: HealthSleepSource { intervals[0].source }
    var startDate: Date { intervals.map(\.startDate).min()! }
    var endDate: Date { intervals.map(\.endDate).max()! }
    var duration: TimeInterval {
      let sorted = intervals.sorted { $0.startDate < $1.startDate }
      var total: TimeInterval = 0
      var currentStart = sorted[0].startDate
      var currentEnd = sorted[0].endDate
      for interval in sorted.dropFirst() {
        if interval.startDate <= currentEnd {
          currentEnd = max(currentEnd, interval.endDate)
        } else {
          total += currentEnd.timeIntervalSince(currentStart)
          currentStart = interval.startDate
          currentEnd = interval.endDate
        }
      }
      return total + currentEnd.timeIntervalSince(currentStart)
    }

    func overlaps(_ other: Candidate) -> Bool {
      startDate < other.endDate && other.startDate < endDate
    }
  }
}

extension HealthRecoveryEvidenceSnapshot {
  public var availableSleepSources: [HealthSleepSource] {
    var seen = Set<String>()
    return sleep.compactMap { sample in
      let source = HealthSleepSource(provenance: sample.provenance)
      return seen.insert(source.id).inserted ? source : nil
    }
  }

  public func sleepEpisodes(
    preference: SleepSourcePreference = .init(),
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) -> SleepEpisodeProjection {
    SleepEpisodeCalculator().calculate(
      samples: sleep,
      preference: preference,
      calendar: calendar,
      status: statuses.first { $0.stream == .sleep })
  }
}
