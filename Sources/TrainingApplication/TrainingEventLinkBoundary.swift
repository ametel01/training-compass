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
  case missingHealthProvenance
  case linkConflict(healthKitUUID: String, sessionIDs: [String])
  case writeBackConflict(syncIdentifier: String, syncVersion: Int, healthKitUUIDs: [String])

  public var message: String {
    switch self {
    case .localDate(let session, let health):
      "Session date \(session) differs from Health date \(health)."
    case .missingHealthProvenance:
      "Health Workout source provenance is unavailable."
    case .linkConflict(let healthKitUUID, let sessionIDs):
      "HealthKit UUID \(healthKitUUID) has conflicting active links: \(sessionIDs.joined(separator: ", "))."
    case .writeBackConflict(let syncIdentifier, let syncVersion, let healthKitUUIDs):
      "App-authored Health summary \(syncIdentifier) has multiple version \(syncVersion) objects: \(healthKitUUIDs.joined(separator: ", ")). Repair the extra app-owned objects explicitly."
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
  public let healthWorkoutEnrichment: HealthWorkoutEnrichment?
  public let link: HealthWorkoutLinkFact?
  public let linkState: UnifiedTrainingEventLinkState
  public let lastSuccessfulReconciliation: Date?
  public let reconciliationContext: String?
  public let healthCoverage: HealthStreamCoverage?
  public let disagreements: [TrainingEventDisagreement]

  public init(
    id: String,
    localDate: String,
    sortDate: Date,
    session: TrainingEventSessionFacts? = nil,
    healthWorkout: HealthWorkout? = nil,
    healthWorkoutEnrichment: HealthWorkoutEnrichment? = nil,
    link: HealthWorkoutLinkFact? = nil,
    linkState: UnifiedTrainingEventLinkState,
    lastSuccessfulReconciliation: Date? = nil,
    reconciliationContext: String? = nil,
    healthCoverage: HealthStreamCoverage? = nil,
    additionalDisagreements: [TrainingEventDisagreement] = []
  ) {
    self.id = id
    self.localDate = localDate
    self.sortDate = sortDate
    self.session = session
    self.healthWorkout = healthWorkout
    self.healthWorkoutEnrichment = healthWorkout.map {
      healthWorkoutEnrichment ?? .loading(healthKitUUID: $0.healthKitUUID)
    }
    self.link = link
    self.linkState = linkState
    self.lastSuccessfulReconciliation = lastSuccessfulReconciliation
    self.reconciliationContext = reconciliationContext
    self.healthCoverage = healthWorkout.map { _ in healthCoverage ?? .unknown }
    var disagreements: [TrainingEventDisagreement] = []
    if let session, let healthWorkout,
      session.session.intendedDate.iso8601String != healthWorkout.localDate
    {
      disagreements.append(
        .localDate(
          session: session.session.intendedDate.iso8601String,
          health: healthWorkout.localDate))
    }
    if let healthWorkout, !HealthWorkoutProvenance(workout: healthWorkout).isAvailable {
      disagreements.append(.missingHealthProvenance)
    }
    self.disagreements = disagreements + additionalDisagreements
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
  /// Marks every active link for a local entity as historical. This is used
  /// when a Session is corrected to a non-completed disposition so the
  /// external Health Workout remains untouched while the association is
  /// auditable.
  func unlinkActiveHealthWorkoutLinkFacts(
    forLocalEntityID localEntityID: String,
    unlinkedAt: Date
  ) async throws -> [HealthWorkoutLinkFact]
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

  public func unlinkActiveHealthWorkoutLinkFacts(
    forLocalEntityID localEntityID: String,
    unlinkedAt: Date
  ) async throws -> [HealthWorkoutLinkFact] {
    let active = try await loadHealthWorkoutLinkFacts(for: nil).filter {
      $0.isActive && $0.localEntityKind == .session && $0.localEntityID == localEntityID
    }
    var unlinked: [HealthWorkoutLinkFact] = []
    for link in active {
      unlinked.append(
        try await unlinkHealthWorkoutLinkFact(
          id: link.id, expectedLinkedAt: link.linkedAt, unlinkedAt: unlinkedAt))
    }
    return unlinked
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
  case appAuthoredSummaryDeletionFailed
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
  private let writeBackBoundary: HealthWorkoutWriteBackBoundary?

  public init(
    cycleRepository: any TrainingCycleRepository,
    resultRepository: any SetResultRepository,
    healthRepository: any HealthWorkoutRepository,
    linkRepository: any TrainingEventLinkRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator,
    writeBackBoundary: HealthWorkoutWriteBackBoundary? = nil
  ) {
    self.cycleRepository = cycleRepository
    self.resultRepository = resultRepository
    self.healthRepository = healthRepository
    self.linkRepository = linkRepository
    self.clock = clock
    self.uuidGenerator = uuidGenerator
    self.writeBackBoundary = writeBackBoundary
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
    let writeBackRecords = (try? await writeBackBoundary?.records()) ?? []
    let writeBackBySyncIdentifier = Dictionary(
      writeBackRecords.map { ($0.syncIdentifier, $0) },
      uniquingKeysWith: { _, replacement in replacement })
    let checkpoint = try? await healthRepository.loadHealthSyncCheckpoint(for: .workouts)
    let healthCoverage: HealthStreamCoverage =
      checkpoint.map {
        $0.hasLimitedHistory ? .limitedHistory : .available
      } ?? .unknown
    let workoutsByID = Dictionary(
      workouts.map { ($0.healthKitUUID, $0) },
      uniquingKeysWith: { _, replacement in replacement })
    // HealthKit can retain more than one object for an app-authored sync
    // identifier after a failed/out-of-order replacement. Only the highest
    // version participates in the current projection; equal highest versions
    // remain visible through one deterministic object plus a conflict.
    let appAuthoredGroups = Dictionary(
      grouping: workouts.filter(\.isAppAuthored), by: { $0.appAuthoredSyncIdentifier! })
    var selectedAppAuthoredIDs: Set<String> = []
    var appAuthoredConflictsByID: [String: TrainingEventDisagreement] = [:]
    for (syncIdentifier, group) in appAuthoredGroups {
      guard let highest = group.compactMap(\.appAuthoredSyncVersion).max() else { continue }
      let highestObjects = group.filter { $0.appAuthoredSyncVersion == highest }
        .sorted { $0.healthKitUUID < $1.healthKitUUID }
      guard let selected = highestObjects.first else { continue }
      selectedAppAuthoredIDs.insert(selected.healthKitUUID)
      if highestObjects.count > 1 {
        let disagreement = TrainingEventDisagreement.writeBackConflict(
          syncIdentifier: syncIdentifier,
          syncVersion: highest,
          healthKitUUIDs: highestObjects.map(\.healthKitUUID))
        appAuthoredConflictsByID[selected.healthKitUUID] = disagreement
      }
    }
    var enrichmentsByID: [String: HealthWorkoutEnrichment] = [:]
    for workout in workouts {
      if let enrichment = try await healthRepository.loadHealthWorkoutEnrichment(
        for: workout.healthKitUUID)
      {
        enrichmentsByID[workout.healthKitUUID] = enrichment
      }
    }
    let activeLinks = persistedLinks.filter { workoutsByID[$0.healthKitUUID] != nil }
    let unavailableLinks = persistedLinks.filter { workoutsByID[$0.healthKitUUID] == nil }
    let linksByUUID = Dictionary(grouping: persistedLinks, by: \.healthKitUUID)
    let linkConflictsByID = Dictionary(
      persistedLinks.compactMap { link -> (String, TrainingEventDisagreement)? in
        let conflictingSessionIDs = linksByUUID[link.healthKitUUID, default: []]
          .map(\.localEntityID)
          .reduce(into: Set<String>()) { $0.insert($1) }
          .sorted()
        guard conflictingSessionIDs.count > 1 else { return nil }
        return (
          link.id,
          .linkConflict(
            healthKitUUID: link.healthKitUUID,
            sessionIDs: conflictingSessionIDs)
        )
      }, uniquingKeysWith: { first, _ in first })
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
          let persistedLink = linksBySessionID[session.id]
          let formerLink = unavailableLinksBySessionID[session.id]
          let persistedWorkout = persistedLink.flatMap { workoutsByID[$0.healthKitUUID] }
          // A stale active link to a lower-version app-authored object must
          // not win over the highest imported replacement. The local summary
          // still resolves through its sync identifier below; the old link
          // is omitted from this projection until an explicit repair updates
          // the authoritative relationship.
          let link =
            persistedWorkout.map {
              $0.isAppAuthored && !selectedAppAuthoredIDs.contains($0.healthKitUUID)
            } == true
            ? nil : persistedLink
          let appAuthoredCandidates = workouts.filter {
            guard
              $0.appAuthoredSyncIdentifier
                == HealthWorkoutWriteBackBoundary.syncIdentifier(for: session.id),
              selectedAppAuthoredIDs.contains($0.healthKitUUID)
            else { return false }
            guard let record = writeBackBySyncIdentifier[$0.appAuthoredSyncIdentifier!] else {
              return true
            }
            return record.state != .notShared && record.state != .deletedFromHealth
              && record.healthKitUUID == $0.healthKitUUID
          }
          let workout =
            link.flatMap { workoutsByID[$0.healthKitUUID] } ?? appAuthoredCandidates.first
          if let workout { consumedWorkoutIDs.insert(workout.healthKitUUID) }
          if let syncID = workout?.appAuthoredSyncIdentifier {
            consumedWorkoutIDs.formUnion(
              appAuthoredGroups[syncID, default: []].map(\.healthKitUUID))
          }
          let completionDate = Date(timeIntervalSince1970: TimeInterval(completion.confirmedAt))
          events.append(
            UnifiedTrainingEvent(
              id: link.map { "training-event:\($0.id)" } ?? "session:\(session.id)",
              localDate: session.intendedDate.iso8601String,
              sortDate: workout?.startDate ?? completionDate,
              session: facts,
              healthWorkout: workout,
              healthWorkoutEnrichment: workout.flatMap {
                enrichmentsByID[$0.healthKitUUID]
              },
              link: link ?? formerLink,
              linkState: link == nil && workout?.isAppAuthored != true
                ? (formerLink == nil ? .unlinked : .formerLinkWorkoutUnavailable)
                : .linked,
              lastSuccessfulReconciliation: checkpoint?.committedAt,
              reconciliationContext: checkpoint?.reconciliationContext,
              healthCoverage: healthCoverage,
              additionalDisagreements: [link, formerLink].compactMap { $0 }.compactMap {
                linkConflictsByID[$0.id]
              }
                + (workout.flatMap { appAuthoredConflictsByID[$0.healthKitUUID] }
                  .map { [$0] } ?? [])
            ))
        }
      }
    }

    for workout in workouts
    where !consumedWorkoutIDs.contains(workout.healthKitUUID)
      && (!workout.isAppAuthored || selectedAppAuthoredIDs.contains(workout.healthKitUUID))
    {
      events.append(
        UnifiedTrainingEvent(
          id: "health:\(workout.healthKitUUID)",
          localDate: workout.localDate,
          sortDate: workout.startDate,
          healthWorkout: workout,
          healthWorkoutEnrichment: enrichmentsByID[workout.healthKitUUID],
          linkState: .unlinked,
          lastSuccessfulReconciliation: checkpoint?.committedAt,
          reconciliationContext: checkpoint?.reconciliationContext,
          healthCoverage: healthCoverage,
          additionalDisagreements: workout.appAuthoredSyncIdentifier
            .flatMap { _ in appAuthoredConflictsByID[workout.healthKitUUID] }.map { [$0] } ?? []
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

    try await deleteAppAuthoredSummaryBeforeExternalLink(sessionID: sessionID)

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

    try await deleteAppAuthoredSummaryBeforeExternalLink(sessionID: sessionID)

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

  private func deleteAppAuthoredSummaryBeforeExternalLink(sessionID: String) async throws {
    guard let writeBackBoundary else { return }
    do {
      _ = try await writeBackBoundary.deleteAppAuthoredSummaryForReplacement(sessionID: sessionID)
    } catch HealthWorkoutWriteBackReplacementError.deletionFailed {
      throw TrainingEventLinkError.appAuthoredSummaryDeletionFailed
    } catch {
      throw TrainingEventLinkError.appAuthoredSummaryDeletionFailed
    }
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
