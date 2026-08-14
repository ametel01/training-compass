import Foundation
import TrainingDomain

public enum TrainingEventLinkWarning: Codable, Equatable, Sendable {
  case differentActivity
  case differentLocalDate
  case distantCompletionTime

  public var message: String {
    switch self {
    case .differentActivity:
      "The Health Workout is not classified as strength training."
    case .differentLocalDate:
      "The Health Workout is assigned to a different local date."
    case .distantCompletionTime:
      "The Health Workout ended far from the Session completion time."
    }
  }
}

public struct TrainingEventLinkCandidate: Codable, Equatable, Identifiable, Sendable {
  public let workout: HealthWorkout
  public let expectedSessionUpdatedAt: Int64
  public let timingDifference: TimeInterval
  public let activityMatchesStrengthTraining: Bool
  public let warnings: [TrainingEventLinkWarning]

  public init(
    workout: HealthWorkout,
    expectedSessionUpdatedAt: Int64,
    timingDifference: TimeInterval,
    activityMatchesStrengthTraining: Bool,
    warnings: [TrainingEventLinkWarning]
  ) {
    self.workout = workout
    self.expectedSessionUpdatedAt = expectedSessionUpdatedAt
    self.timingDifference = timingDifference
    self.activityMatchesStrengthTraining = activityMatchesStrengthTraining
    self.warnings = warnings
  }

  public var id: String { workout.healthKitUUID }
  public var healthKitUUID: String { workout.healthKitUUID }
  public var requiresWarningAcknowledgement: Bool { !warnings.isEmpty }
  public var isSelectable: Bool { true }
}

public struct TrainingEventLinkingSnapshot: Codable, Equatable, Sendable {
  public let sessionID: String
  public let candidates: [TrainingEventLinkCandidate]
  public let activeLink: HealthWorkoutLinkFact?
  /// Candidate ranking is advisory only. The owner must always make the
  /// selection explicitly, so a snapshot never preselects a candidate.
  public let selectedCandidateID: String?

  public init(
    sessionID: String,
    candidates: [TrainingEventLinkCandidate],
    activeLink: HealthWorkoutLinkFact? = nil,
    selectedCandidateID: String? = nil
  ) {
    self.sessionID = sessionID
    self.candidates = candidates
    self.activeLink = activeLink
    self.selectedCandidateID = selectedCandidateID
  }
}

public enum UnifiedTrainingEventLinkState: String, Codable, Equatable, Sendable {
  case unlinked
  case linked
  case formerLinkWorkoutUnavailable
}

public enum TrainingEventDisagreement: Codable, Equatable, Sendable {
  case localDate(session: String, health: String)

  public var message: String {
    switch self {
    case .localDate(let session, let health):
      "Session date \(session) differs from Health date \(health)."
    }
  }
}

public struct TrainingEventSessionFacts: Codable, Equatable, Sendable {
  public let cycleID: String
  public let weekID: String
  public let session: TrainingCycleSession
  public let completion: CompletedSession
  public let results: [RecordedSetResult]
  public let omissions: [OmittedSet]
  public let additionalSets: [AdditionalSet]

  public init(
    cycleID: String,
    weekID: String,
    session: TrainingCycleSession,
    completion: CompletedSession,
    results: [RecordedSetResult],
    omissions: [OmittedSet],
    additionalSets: [AdditionalSet]
  ) {
    self.cycleID = cycleID
    self.weekID = weekID
    self.session = session
    self.completion = completion
    self.results = results
    self.omissions = omissions
    self.additionalSets = additionalSets
  }

  public var sessionID: String { session.id }
}

public struct UnifiedTrainingEvent: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let localDate: String
  public let sortDate: Date
  public let session: TrainingEventSessionFacts?
  public let healthWorkout: HealthWorkout?
  public let link: HealthWorkoutLinkFact?
  public let linkState: UnifiedTrainingEventLinkState
  public let lastSuccessfulReconciliation: Date?
  public let reconciliationContext: String?
  public let disagreements: [TrainingEventDisagreement]

  public init(
    id: String,
    localDate: String,
    sortDate: Date,
    session: TrainingEventSessionFacts? = nil,
    healthWorkout: HealthWorkout? = nil,
    link: HealthWorkoutLinkFact? = nil,
    linkState: UnifiedTrainingEventLinkState,
    lastSuccessfulReconciliation: Date? = nil,
    reconciliationContext: String? = nil
  ) {
    self.id = id
    self.localDate = localDate
    self.sortDate = sortDate
    self.session = session
    self.healthWorkout = healthWorkout
    self.link = link
    self.linkState = linkState
    self.lastSuccessfulReconciliation = lastSuccessfulReconciliation
    self.reconciliationContext = reconciliationContext
    if let session, let healthWorkout,
      session.session.intendedDate.iso8601String != healthWorkout.localDate
    {
      self.disagreements = [
        .localDate(
          session: session.session.intendedDate.iso8601String,
          health: healthWorkout.localDate)
      ]
    } else {
      self.disagreements = []
    }
  }

  public var sourceBadges: [TrainingEventSource] {
    var sources: [TrainingEventSource] = []
    if session != nil { sources.append(.localTraining) }
    if healthWorkout != nil { sources.append(.health) }
    return sources
  }
}

public struct TrainingEventTimelineSnapshot: Codable, Equatable, Sendable {
  public let events: [UnifiedTrainingEvent]

  public init(events: [UnifiedTrainingEvent]) {
    self.events = events
  }

  public var aggregateCount: Int { events.count }
}

public protocol TrainingEventLinkRepository: Sendable {
  func loadHealthWorkoutLinkFacts(for healthKitUUID: String?) async throws
    -> [HealthWorkoutLinkFact]
  func createHealthWorkoutLinkFact(
    _ fact: HealthWorkoutLinkFact,
    expectedSessionUpdatedAt: Int64,
    expectedWorkout: HealthWorkout
  ) async throws -> HealthWorkoutLinkFact
  func completeSessionAndCreateHealthWorkoutLinkFact(
    completion: CompletedSession,
    fact: HealthWorkoutLinkFact,
    expectedSessionUpdatedAt: Int64,
    expectedWorkout: HealthWorkout
  ) async throws -> TrainingEventCompletionLinkResult
  func unlinkHealthWorkoutLinkFact(
    id: String,
    expectedLinkedAt: Date,
    unlinkedAt: Date
  ) async throws -> HealthWorkoutLinkFact
}

public struct TrainingEventCompletionLinkResult: Codable, Equatable, Sendable {
  public let completion: CompletedSession
  public let link: HealthWorkoutLinkFact

  public init(completion: CompletedSession, link: HealthWorkoutLinkFact) {
    self.completion = completion
    self.link = link
  }
}

public enum TrainingEventLinkRepositoryError: Error, Equatable, Sendable {
  case staleCandidate
  case duplicateLink
  case invalidLink
  case unavailable
}

extension TrainingEventLinkRepository {
  public func createHealthWorkoutLinkFact(
    _ fact: HealthWorkoutLinkFact,
    expectedSessionUpdatedAt: Int64,
    expectedWorkout: HealthWorkout
  ) async throws -> HealthWorkoutLinkFact {
    throw TrainingEventLinkRepositoryError.unavailable
  }

  public func completeSessionAndCreateHealthWorkoutLinkFact(
    completion: CompletedSession,
    fact: HealthWorkoutLinkFact,
    expectedSessionUpdatedAt: Int64,
    expectedWorkout: HealthWorkout
  ) async throws -> TrainingEventCompletionLinkResult {
    throw TrainingEventLinkRepositoryError.unavailable
  }

  public func unlinkHealthWorkoutLinkFact(
    id: String,
    expectedLinkedAt: Date,
    unlinkedAt: Date
  ) async throws -> HealthWorkoutLinkFact {
    throw TrainingEventLinkRepositoryError.unavailable
  }
}

public enum TrainingEventLinkConfirmation: Codable, Equatable, Sendable {
  case confirmed
  case confirmedUnusualMatch
  case cancelled
}

public enum TrainingEventUnlinkConfirmation: Codable, Equatable, Sendable {
  case confirmed
  case cancelled
}

public enum TrainingEventLinkError: Error, Equatable, Sendable {
  case unknownSession
  case sessionNotCompleted
  case sessionNotReady
  case warningAcknowledgementRequired
  case confirmationRequired
  case staleCandidate
}

/// The application seam for explicit external-workout linking. Ranking is
/// intentionally kept inside this module so every UI presents the same
/// candidates without acquiring authority to infer a link.
public struct TrainingEventLinkBoundary: Sendable {
  public static let trainingCompassBundleIdentifier = "com.ametel01.trainingcompass"

  private let cycleRepository: any TrainingCycleRepository
  private let resultRepository: any SetResultRepository
  private let healthRepository: any HealthWorkoutRepository
  private let linkRepository: any TrainingEventLinkRepository
  private let clock: any Clock
  private let uuidGenerator: any UUIDGenerator

  public init(
    cycleRepository: any TrainingCycleRepository,
    resultRepository: any SetResultRepository,
    healthRepository: any HealthWorkoutRepository,
    linkRepository: any TrainingEventLinkRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator
  ) {
    self.cycleRepository = cycleRepository
    self.resultRepository = resultRepository
    self.healthRepository = healthRepository
    self.linkRepository = linkRepository
    self.clock = clock
    self.uuidGenerator = uuidGenerator
  }

  public func linkingSnapshot(for sessionID: String) async throws
    -> TrainingEventLinkingSnapshot
  {
    let cycles = try await cycleRepository.loadTrainingCycles()
    guard
      let session = cycles.lazy.flatMap(\.weeks).lazy.flatMap(\.sessions)
        .first(where: { $0.id == sessionID })
    else { throw TrainingEventLinkError.unknownSession }
    guard session.status == .completed,
      let completion = try await resultRepository.loadCompletedSession(sessionID: sessionID)
    else { throw TrainingEventLinkError.sessionNotCompleted }
    guard
      let sessionSnapshot = try await resultRepository.loadSessionCorrectionSnapshot(
        sessionID: sessionID),
      sessionSnapshot.status == .completed,
      sessionSnapshot.completion != nil
    else { throw TrainingEventLinkError.sessionNotCompleted }

    let workouts = try await healthRepository.loadHealthWorkouts()
    let availableWorkoutIDs = Set(workouts.map(\.healthKitUUID))
    let links = try await linkRepository.loadHealthWorkoutLinkFacts(for: nil)
      .filter { $0.isActive && availableWorkoutIDs.contains($0.healthKitUUID) }
    if let activeLink = links.first(where: {
      $0.localEntityKind == .session && $0.localEntityID == sessionID
    }) {
      return TrainingEventLinkingSnapshot(
        sessionID: sessionID,
        candidates: [],
        activeLink: activeLink
      )
    }
    let linkedWorkoutIDs = Set(links.map(\.healthKitUUID))
    let candidates =
      workouts
      .filter { workout in
        workout.sourceBundleIdentifier != Self.trainingCompassBundleIdentifier
          && !linkedWorkoutIDs.contains(workout.healthKitUUID)
      }
      .map { workout in
        Self.candidate(
          workout: workout,
          session: session,
          completion: completion,
          expectedSessionUpdatedAt: sessionSnapshot.updatedAt
        )
      }
      .sorted(by: Self.candidateRanksBefore)

    _ = clock
    _ = uuidGenerator
    return TrainingEventLinkingSnapshot(sessionID: sessionID, candidates: candidates)
  }

  public func timeline() async throws -> TrainingEventTimelineSnapshot {
    let cycles = try await cycleRepository.loadTrainingCycles()
    let workouts = try await healthRepository.loadHealthWorkouts()
    let persistedLinks = try await linkRepository.loadHealthWorkoutLinkFacts(for: nil)
      .filter(\.isActive)
    let checkpoint = try? await healthRepository.loadHealthSyncCheckpoint(for: .workouts)
    let workoutsByID = Dictionary(
      workouts.map { ($0.healthKitUUID, $0) },
      uniquingKeysWith: { _, replacement in replacement })
    let activeLinks = persistedLinks.filter { workoutsByID[$0.healthKitUUID] != nil }
    let unavailableLinks = persistedLinks.filter { workoutsByID[$0.healthKitUUID] == nil }
    let linksBySessionID = Dictionary(
      activeLinks.filter { $0.localEntityKind == .session }.map { ($0.localEntityID, $0) },
      uniquingKeysWith: { first, _ in first })
    let unavailableLinksBySessionID = Dictionary(
      unavailableLinks.filter { $0.localEntityKind == .session }.map { ($0.localEntityID, $0) },
      uniquingKeysWith: { first, _ in first })
    var consumedWorkoutIDs: Set<String> = []
    var events: [UnifiedTrainingEvent] = []

    for cycle in cycles {
      for week in cycle.weeks {
        for session in week.sessions where session.status == .completed {
          guard
            let completion = try await resultRepository.loadCompletedSession(
              sessionID: session.id)
          else { continue }
          let facts = TrainingEventSessionFacts(
            cycleID: cycle.id,
            weekID: week.id,
            session: session,
            completion: completion,
            results: try await resultRepository.loadSetResults(for: session.id),
            omissions: try await resultRepository.loadOmittedSets(for: session.id),
            additionalSets: try await resultRepository.loadAdditionalSets(for: session.id)
          )
          let link = linksBySessionID[session.id]
          let formerLink = unavailableLinksBySessionID[session.id]
          let workout = link.flatMap { workoutsByID[$0.healthKitUUID] }
          if let workout { consumedWorkoutIDs.insert(workout.healthKitUUID) }
          let completionDate = Date(timeIntervalSince1970: TimeInterval(completion.confirmedAt))
          events.append(
            UnifiedTrainingEvent(
              id: link.map { "training-event:\($0.id)" } ?? "session:\(session.id)",
              localDate: session.intendedDate.iso8601String,
              sortDate: workout?.startDate ?? completionDate,
              session: facts,
              healthWorkout: workout,
              link: link ?? formerLink,
              linkState: link == nil
                ? (formerLink == nil ? .unlinked : .formerLinkWorkoutUnavailable)
                : .linked,
              lastSuccessfulReconciliation: checkpoint?.committedAt,
              reconciliationContext: checkpoint?.reconciliationContext
            ))
        }
      }
    }

    for workout in workouts where !consumedWorkoutIDs.contains(workout.healthKitUUID) {
      events.append(
        UnifiedTrainingEvent(
          id: "health:\(workout.healthKitUUID)",
          localDate: workout.localDate,
          sortDate: workout.startDate,
          healthWorkout: workout,
          linkState: .unlinked,
          lastSuccessfulReconciliation: checkpoint?.committedAt,
          reconciliationContext: checkpoint?.reconciliationContext
        ))
    }
    events.sort {
      if $0.sortDate != $1.sortDate { return $0.sortDate > $1.sortDate }
      return $0.id > $1.id
    }
    return TrainingEventTimelineSnapshot(events: events)
  }

  public func timeline(on date: TrainingDate) async throws -> TrainingEventTimelineSnapshot {
    let all = try await timeline()
    return TrainingEventTimelineSnapshot(
      events: all.events.filter { $0.localDate == date.iso8601String })
  }

  @discardableResult
  public func unlink(
    _ link: HealthWorkoutLinkFact,
    confirmation: TrainingEventUnlinkConfirmation
  ) async throws -> HealthWorkoutLinkFact {
    guard confirmation == .confirmed else {
      throw TrainingEventLinkError.confirmationRequired
    }
    guard link.isActive else { throw TrainingEventLinkError.staleCandidate }
    do {
      return try await linkRepository.unlinkHealthWorkoutLinkFact(
        id: link.id,
        expectedLinkedAt: link.linkedAt,
        unlinkedAt: clock.now()
      )
    } catch TrainingEventLinkRepositoryError.staleCandidate {
      throw TrainingEventLinkError.staleCandidate
    }
  }

  public func completionLinkingSnapshot(for sessionID: String) async throws
    -> TrainingEventLinkingSnapshot
  {
    let cycles = try await cycleRepository.loadTrainingCycles()
    guard
      let session = cycles.lazy.flatMap(\.weeks).lazy.flatMap(\.sessions)
        .first(where: { $0.id == sessionID })
    else { throw TrainingEventLinkError.unknownSession }
    guard !session.status.isTerminal,
      let sessionSnapshot = try await resultRepository.loadSessionCorrectionSnapshot(
        sessionID: sessionID),
      !sessionSnapshot.status.isTerminal
    else { throw TrainingEventLinkError.sessionNotReady }
    let resolvedPrescriptionIDs = Set(
      sessionSnapshot.results.map(\.prescriptionID)
        + sessionSnapshot.omissions.map(\.prescriptionID))
    guard session.prescriptions.allSatisfy({ resolvedPrescriptionIDs.contains($0.id) }) else {
      throw TrainingEventLinkError.sessionNotReady
    }

    let links = try await linkRepository.loadHealthWorkoutLinkFacts(for: nil)
    let activeLinks = links.filter(\.isActive)
    guard
      !activeLinks.contains(where: {
        $0.localEntityKind == .session && $0.localEntityID == sessionID
      })
    else { throw TrainingEventLinkRepositoryError.duplicateLink }
    let linkedWorkoutIDs = Set(activeLinks.map(\.healthKitUUID))
    let completionReference = CompletedSession(
      sessionID: sessionID,
      confirmedAt: Int64(clock.now().timeIntervalSince1970)
    )
    let candidates = try await healthRepository.loadHealthWorkouts()
      .filter { workout in
        workout.sourceBundleIdentifier != Self.trainingCompassBundleIdentifier
          && !linkedWorkoutIDs.contains(workout.healthKitUUID)
      }
      .map { workout in
        Self.candidate(
          workout: workout,
          session: session,
          completion: completionReference,
          expectedSessionUpdatedAt: sessionSnapshot.updatedAt
        )
      }
      .sorted(by: Self.candidateRanksBefore)
    return TrainingEventLinkingSnapshot(sessionID: sessionID, candidates: candidates)
  }

  @discardableResult
  public func confirmLink(
    _ candidate: TrainingEventLinkCandidate,
    to sessionID: String,
    confirmation: TrainingEventLinkConfirmation
  ) async throws -> HealthWorkoutLinkFact {
    guard confirmation != .cancelled else {
      throw TrainingEventLinkError.confirmationRequired
    }
    if candidate.requiresWarningAcknowledgement && confirmation != .confirmedUnusualMatch {
      throw TrainingEventLinkError.warningAcknowledgementRequired
    }

    let current = try await linkingSnapshot(for: sessionID)
    guard let currentCandidate = current.candidates.first(where: { $0.id == candidate.id }),
      currentCandidate == candidate
    else { throw TrainingEventLinkError.staleCandidate }

    let fact = HealthWorkoutLinkFact(
      id: uuidGenerator.makeUUID().uuidString,
      healthKitUUID: candidate.healthKitUUID,
      localEntityKind: .session,
      localEntityID: sessionID,
      linkedAt: clock.now()
    )
    do {
      return try await linkRepository.createHealthWorkoutLinkFact(
        fact,
        expectedSessionUpdatedAt: candidate.expectedSessionUpdatedAt,
        expectedWorkout: candidate.workout
      )
    } catch TrainingEventLinkRepositoryError.staleCandidate {
      throw TrainingEventLinkError.staleCandidate
    } catch TrainingEventLinkRepositoryError.duplicateLink {
      throw TrainingEventLinkRepositoryError.duplicateLink
    }
  }

  @discardableResult
  public func completeSession(
    linking candidate: TrainingEventLinkCandidate,
    to sessionID: String,
    confirmation: TrainingEventLinkConfirmation
  ) async throws -> TrainingEventCompletionLinkResult {
    guard confirmation != .cancelled else {
      throw TrainingEventLinkError.confirmationRequired
    }
    if candidate.requiresWarningAcknowledgement && confirmation != .confirmedUnusualMatch {
      throw TrainingEventLinkError.warningAcknowledgementRequired
    }
    let current = try await completionLinkingSnapshot(for: sessionID)
    guard let currentCandidate = current.candidates.first(where: { $0.id == candidate.id }),
      currentCandidate == candidate
    else { throw TrainingEventLinkError.staleCandidate }

    let now = clock.now()
    let completion = CompletedSession(
      sessionID: sessionID,
      confirmedAt: Int64(now.timeIntervalSince1970)
    )
    let link = HealthWorkoutLinkFact(
      id: uuidGenerator.makeUUID().uuidString,
      healthKitUUID: candidate.healthKitUUID,
      localEntityKind: .session,
      localEntityID: sessionID,
      linkedAt: now,
      linkedDuringCompletion: true,
      writeBackDisposition: .suppressedExternalWorkoutLinkedAtCompletion
    )
    do {
      return try await linkRepository.completeSessionAndCreateHealthWorkoutLinkFact(
        completion: completion,
        fact: link,
        expectedSessionUpdatedAt: candidate.expectedSessionUpdatedAt,
        expectedWorkout: candidate.workout
      )
    } catch TrainingEventLinkRepositoryError.staleCandidate {
      throw TrainingEventLinkError.staleCandidate
    }
  }

  private static func candidate(
    workout: HealthWorkout,
    session: TrainingCycleSession,
    completion: CompletedSession,
    expectedSessionUpdatedAt: Int64
  ) -> TrainingEventLinkCandidate {
    let timingDifference = abs(
      workout.endDate.timeIntervalSince1970 - TimeInterval(completion.confirmedAt))
    let activity = workout.activityType.lowercased()
    let activityMatches = activity.contains("strength")
    var warnings: [TrainingEventLinkWarning] = []
    if !activityMatches { warnings.append(.differentActivity) }
    if workout.localDate != session.intendedDate.iso8601String {
      warnings.append(.differentLocalDate)
    }
    if timingDifference > 6 * 60 * 60 { warnings.append(.distantCompletionTime) }
    return TrainingEventLinkCandidate(
      workout: workout,
      expectedSessionUpdatedAt: expectedSessionUpdatedAt,
      timingDifference: timingDifference,
      activityMatchesStrengthTraining: activityMatches,
      warnings: warnings
    )
  }

  private static func candidateRanksBefore(
    _ lhs: TrainingEventLinkCandidate,
    _ rhs: TrainingEventLinkCandidate
  ) -> Bool {
    if lhs.activityMatchesStrengthTraining != rhs.activityMatchesStrengthTraining {
      return lhs.activityMatchesStrengthTraining
    }
    let lhsSameDate = !lhs.warnings.contains(.differentLocalDate)
    let rhsSameDate = !rhs.warnings.contains(.differentLocalDate)
    if lhsSameDate != rhsSameDate { return lhsSameDate }
    if lhs.timingDifference != rhs.timingDifference {
      return lhs.timingDifference < rhs.timingDifference
    }
    return lhs.healthKitUUID < rhs.healthKitUUID
  }
}
