import Foundation
import TrainingInsights

/// The owner's decision for one fixed Training Max progression proposal.
public enum TrainingMaxProposalDecision: Codable, Equatable, Sendable {
  case accept
  case reject
  case replace(kg: Double)

  public static func manual(kg: Double) -> Self { .replace(kg: kg) }
}

public enum TrainingMaxProposalStatus: String, Codable, Equatable, Sendable {
  case pending
  case accepted
  case rejected
  case manuallyReplaced

  public var isResolved: Bool { self != .pending }
}

public struct TrainingMaxProposalExcludedWork: Codable, Equatable, Identifiable, Sendable {
  public enum Kind: String, Codable, Equatable, Sendable {
    case skippedSession
    case omittedSet
    case failedSet

    public var displayName: String {
      switch self {
      case .skippedSession: "Skipped Session"
      case .omittedSet: "Omitted Set"
      case .failedSet: "Failed Set"
      }
    }
  }

  public let id: String
  public let kind: Kind
  public let cycleID: String
  public let weekID: String?
  public let sessionID: String?
  public let prescriptionID: String?
  public let note: String?

  public init(
    id: String,
    kind: Kind,
    cycleID: String,
    weekID: String? = nil,
    sessionID: String? = nil,
    prescriptionID: String? = nil,
    note: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.cycleID = cycleID
    self.weekID = weekID
    self.sessionID = sessionID
    self.prescriptionID = prescriptionID
    self.note = note?.isEmpty == true ? nil : note
  }
}

/// Evidence captured when a completed cycle produces a proposal. The evidence
/// is immutable so a later correction can be understood against the decision
/// that was actually presented to the owner.
public struct TrainingMaxProposalEvidence: Codable, Equatable, Sendable {
  public let eligibleE1RM: [E1RMObservation]
  public let excludedWork: [TrainingMaxProposalExcludedWork]
  public let explanation: InsightExplanation

  public init(
    eligibleE1RM: [E1RMObservation] = [],
    excludedWork: [TrainingMaxProposalExcludedWork] = [],
    explanation: InsightExplanation
  ) {
    self.eligibleE1RM = eligibleE1RM
    self.excludedWork = excludedWork
    self.explanation = explanation
  }

  public var e1RMObservations: [E1RMObservation] { eligibleE1RM }
  public var skippedSessions: [TrainingMaxProposalExcludedWork] {
    excludedWork.filter { $0.kind == .skippedSession }
  }
  public var omittedSets: [TrainingMaxProposalExcludedWork] {
    excludedWork.filter { $0.kind == .omittedSet }
  }
  public var skippedOrOmittedWork: [TrainingMaxProposalExcludedWork] { excludedWork }
}

public struct TrainingMaxProposal: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let liftID: String
  public let liftName: String
  public let sourceCycleID: String
  public let currentTrainingMaxKg: Double
  public let proposedTrainingMaxKg: Double
  public let incrementKg: Double
  public let evidence: TrainingMaxProposalEvidence
  public let status: TrainingMaxProposalStatus
  public let decision: TrainingMaxProposalDecision?
  public let decidedAt: Int64?
  public let effectiveCycleID: String?
  public let createdAt: Int64
  public let updatedAt: Int64

  public init(
    id: String,
    liftID: String,
    liftName: String,
    sourceCycleID: String,
    currentTrainingMaxKg: Double,
    proposedTrainingMaxKg: Double,
    incrementKg: Double,
    evidence: TrainingMaxProposalEvidence,
    status: TrainingMaxProposalStatus = .pending,
    decision: TrainingMaxProposalDecision? = nil,
    decidedAt: Int64? = nil,
    effectiveCycleID: String? = nil,
    createdAt: Int64 = 0,
    updatedAt: Int64 = 0
  ) {
    self.id = id
    self.liftID = liftID
    self.liftName = liftName
    self.sourceCycleID = sourceCycleID
    self.currentTrainingMaxKg = currentTrainingMaxKg
    self.proposedTrainingMaxKg = proposedTrainingMaxKg
    self.incrementKg = incrementKg
    self.evidence = evidence
    self.status = status
    self.decision = decision
    self.decidedAt = decidedAt
    self.effectiveCycleID = effectiveCycleID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var currentTrainingMax: Double { currentTrainingMaxKg }
  public var proposedTrainingMax: Double { proposedTrainingMaxKg }
  public var currentTMKg: Double { currentTrainingMaxKg }
  public var proposedTMKg: Double { proposedTrainingMaxKg }
  public var sourceCycle: String { sourceCycleID }
  public var isResolved: Bool { status.isResolved }
}

public enum TrainingMaxHistoryEvent: String, Codable, Equatable, Sendable {
  case initial
  case manual
  case proposal
  case accepted
  case rejected
  case manuallyReplaced
  case correction

  public var displayName: String {
    switch self {
    case .initial: "Initial"
    case .manual: "Manual"
    case .proposal: "Proposal"
    case .accepted: "Accepted"
    case .rejected: "Rejected"
    case .manuallyReplaced: "Manual Replacement"
    case .correction: "Correction"
    }
  }
}

public struct TrainingMaxHistoryEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let liftID: String
  public let event: TrainingMaxHistoryEvent
  public let occurredAt: Int64
  public let beforeKg: Double?
  public let afterKg: Double?
  public let proposalID: String?
  public let cycleID: String?
  public let effectiveCycleID: String?
  public let evidence: TrainingMaxProposalEvidence?
  public let decision: TrainingMaxProposalDecision?
  public let note: String?

  public init(
    id: String,
    liftID: String,
    event: TrainingMaxHistoryEvent,
    occurredAt: Int64,
    beforeKg: Double? = nil,
    afterKg: Double? = nil,
    proposalID: String? = nil,
    cycleID: String? = nil,
    effectiveCycleID: String? = nil,
    evidence: TrainingMaxProposalEvidence? = nil,
    decision: TrainingMaxProposalDecision? = nil,
    note: String? = nil
  ) {
    self.id = id
    self.liftID = liftID
    self.event = event
    self.occurredAt = occurredAt
    self.beforeKg = beforeKg
    self.afterKg = afterKg
    self.proposalID = proposalID
    self.cycleID = cycleID
    self.effectiveCycleID = effectiveCycleID
    self.evidence = evidence
    self.decision = decision
    self.note = note?.isEmpty == true ? nil : note
  }

  public var beforeAndAfter: (before: Double?, after: Double?) { (beforeKg, afterKg) }
}

public struct TrainingMaxProposalDecisionPreview: Equatable, Sendable {
  public let before: TrainingMaxProposal
  public let after: TrainingMaxProposal
  public let updatedTrainingMax: LiftConfiguration?

  public init(
    before: TrainingMaxProposal,
    after: TrainingMaxProposal,
    updatedTrainingMax: LiftConfiguration?
  ) {
    self.before = before
    self.after = after
    self.updatedTrainingMax = updatedTrainingMax
  }
}

public protocol TrainingMaxProposalRepository: Sendable {
  func loadTrainingMaxProposals() async throws -> [TrainingMaxProposal]
  func saveTrainingMaxProposal(
    _ proposal: TrainingMaxProposal,
    expectedBefore: TrainingMaxProposal?,
    auditID: String,
    occurredAt: Int64,
    history: TrainingMaxHistoryEntry?
  ) async throws -> TrainingMaxProposal
  func loadTrainingMaxHistory(for liftID: String?) async throws -> [TrainingMaxHistoryEntry]
  func markTrainingMaxProposalsEffective(cycleID: String) async throws
  func decideTrainingMaxProposal(
    _ proposal: TrainingMaxProposal,
    expectedBefore: TrainingMaxProposal,
    configuration: LiftConfiguration?,
    expectedConfiguration: LiftConfigurationSnapshot?,
    auditID: String,
    occurredAt: Int64,
    history: TrainingMaxHistoryEntry,
    liftAuditID: String
  ) async throws -> TrainingMaxProposal
}

extension TrainingMaxProposalRepository {
  public func loadTrainingMaxProposals(for cycleID: String) async throws -> [TrainingMaxProposal] {
    try await loadTrainingMaxProposals().filter { $0.sourceCycleID == cycleID }
  }

  public func loadTrainingMaxHistory() async throws -> [TrainingMaxHistoryEntry] {
    try await loadTrainingMaxHistory(for: nil)
  }
}

public enum TrainingMaxProposalRepositoryError: Error, Equatable, Sendable {
  case unavailable
  case staleProposal
  case unknownProposal
  case proposalAlreadyResolved
  case invalidDecision
}

extension TrainingMaxProposalRepository {
  public func loadTrainingMaxProposals() async throws -> [TrainingMaxProposal] { [] }

  public func saveTrainingMaxProposal(
    _ proposal: TrainingMaxProposal,
    expectedBefore: TrainingMaxProposal?,
    auditID: String,
    occurredAt: Int64,
    history: TrainingMaxHistoryEntry?
  ) async throws -> TrainingMaxProposal {
    throw TrainingMaxProposalRepositoryError.unavailable
  }

  public func loadTrainingMaxHistory(for liftID: String?) async throws -> [TrainingMaxHistoryEntry]
  {
    []
  }

  public func markTrainingMaxProposalsEffective(cycleID: String) async throws {}

  public func decideTrainingMaxProposal(
    _ proposal: TrainingMaxProposal,
    expectedBefore: TrainingMaxProposal,
    configuration: LiftConfiguration?,
    expectedConfiguration: LiftConfigurationSnapshot?,
    auditID: String,
    occurredAt: Int64,
    history: TrainingMaxHistoryEntry,
    liftAuditID: String
  ) async throws -> TrainingMaxProposal {
    throw TrainingMaxProposalRepositoryError.unavailable
  }
}

public typealias TrainingMaxHistory = TrainingMaxHistoryEntry

/// Coordinates proposal generation and owner decisions. Generation is
/// idempotent, allowing callers to safely repair a store after an interrupted
/// completion transaction.
public struct TrainingMaxProposalBoundary: Sendable {
  private let proposalRepository: any TrainingMaxProposalRepository
  private let cycleRepository: any TrainingCycleRepository
  private let resultRepository: (any SetResultRepository)?
  private let liftRepository: any LiftConfigurationRepository
  private let clock: any Clock
  private let uuidGenerator: any UUIDGenerator

  public init(
    proposalRepository: any TrainingMaxProposalRepository,
    cycleRepository: any TrainingCycleRepository,
    resultRepository: (any SetResultRepository)? = nil,
    liftRepository: any LiftConfigurationRepository,
    clock: any Clock,
    uuidGenerator: any UUIDGenerator
  ) {
    self.proposalRepository = proposalRepository
    self.cycleRepository = cycleRepository
    self.resultRepository = resultRepository
    self.liftRepository = liftRepository
    self.clock = clock
    self.uuidGenerator = uuidGenerator
  }

  public init(
    repository: any TrainingRepository,
    clock: any Clock = SystemClock(),
    uuidGenerator: any UUIDGenerator = RandomUUIDGenerator()
  ) {
    self.init(
      proposalRepository: repository,
      cycleRepository: repository,
      resultRepository: repository,
      liftRepository: repository,
      clock: clock,
      uuidGenerator: uuidGenerator
    )
  }

  public func proposals() async throws -> [TrainingMaxProposal] {
    try await generateMissingProposals()
    return try await proposalRepository.loadTrainingMaxProposals().sorted {
      if $0.sourceCycleID != $1.sourceCycleID { return $0.sourceCycleID < $1.sourceCycleID }
      return $0.liftID < $1.liftID
    }
  }

  public func list() async throws -> [TrainingMaxProposal] { try await proposals() }

  public func proposals(for cycleID: String) async throws -> [TrainingMaxProposal] {
    try await proposals().filter { $0.sourceCycleID == cycleID }
  }

  public func history(for liftID: String? = nil) async throws -> [TrainingMaxHistoryEntry] {
    try await proposalRepository.loadTrainingMaxHistory(for: liftID).sorted {
      if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
      return $0.id < $1.id
    }
  }

  public func loadHistory(for liftID: String? = nil) async throws -> [TrainingMaxHistoryEntry] {
    try await history(for: liftID)
  }

  public func previewDecision(
    proposalID: String,
    decision: TrainingMaxProposalDecision
  ) async throws -> TrainingMaxProposalDecisionPreview {
    let proposal = try await proposalRepository.loadTrainingMaxProposals().first {
      $0.id == proposalID
    }
    guard let proposal else { throw TrainingMaxProposalRepositoryError.unknownProposal }
    guard proposal.status == .pending else {
      throw TrainingMaxProposalRepositoryError.proposalAlreadyResolved
    }
    let after = try decisionApplied(to: proposal, decision: decision, decidedAt: timestamp())
    let configuration = try await liftRepository.loadLiftConfigurations().first {
      $0.id == proposal.liftID
    }
    let updated: LiftConfiguration?
    switch decision {
    case .accept:
      updated = try configuration.map {
        try LiftConfiguration(
          id: $0.id, identity: $0.identity,
          trainingMax: try TrainingMax(kg: proposal.proposedTrainingMaxKg),
          loadingIncrement: $0.loadingIncrement
        )
      }
    case .replace(let kg):
      guard kg.isFinite, kg > 0 else {
        throw TrainingMaxProposalRepositoryError.invalidDecision
      }
      updated = try configuration.map {
        try LiftConfiguration(
          id: $0.id, identity: $0.identity,
          trainingMax: try TrainingMax(kg: kg), loadingIncrement: $0.loadingIncrement
        )
      }
    case .reject:
      updated = nil
    }
    return TrainingMaxProposalDecisionPreview(
      before: proposal, after: after, updatedTrainingMax: updated)
  }

  @discardableResult
  public func decide(
    proposalID: String,
    decision: TrainingMaxProposalDecision,
    confirmation: TrainingCycleLifecycleConfirmation = .confirmed,
    note: String? = nil
  ) async throws -> TrainingMaxProposal {
    guard confirmation == .confirmed else {
      throw TrainingCycleValidationError.confirmationRequired
    }
    let preview = try await previewDecision(proposalID: proposalID, decision: decision)
    let currentConfiguration = try await liftRepository.loadLiftConfigurations().first {
      $0.id == preview.before.liftID
    }
    let event: TrainingMaxHistoryEvent
    switch decision {
    case .accept: event = .accepted
    case .reject: event = .rejected
    case .replace: event = .manuallyReplaced
    }
    let history = TrainingMaxHistoryEntry(
      id: uuidGenerator.makeUUID().uuidString,
      liftID: preview.before.liftID,
      event: event,
      occurredAt: timestamp(),
      beforeKg: preview.before.currentTrainingMaxKg,
      afterKg: preview.updatedTrainingMax?.trainingMax.kg,
      proposalID: preview.before.id,
      cycleID: preview.before.sourceCycleID,
      effectiveCycleID: nil,
      evidence: preview.before.evidence,
      decision: decision,
      note: note
    )
    return try await proposalRepository.decideTrainingMaxProposal(
      preview.after,
      expectedBefore: preview.before,
      configuration: preview.updatedTrainingMax,
      expectedConfiguration: currentConfiguration?.snapshot,
      auditID: uuidGenerator.makeUUID().uuidString,
      occurredAt: timestamp(),
      history: history,
      liftAuditID: uuidGenerator.makeUUID().uuidString
    )
  }

  public func accept(proposalID: String) async throws -> TrainingMaxProposal {
    try await decide(proposalID: proposalID, decision: .accept)
  }

  public func reject(proposalID: String) async throws -> TrainingMaxProposal {
    try await decide(proposalID: proposalID, decision: .reject)
  }

  public func replace(proposalID: String, with kg: Double) async throws -> TrainingMaxProposal {
    try await decide(proposalID: proposalID, decision: .replace(kg: kg))
  }

  public func acceptProposal(_ proposalID: String) async throws -> TrainingMaxProposal {
    try await accept(proposalID: proposalID)
  }

  public func rejectProposal(_ proposalID: String) async throws -> TrainingMaxProposal {
    try await reject(proposalID: proposalID)
  }

  public func replaceProposal(_ proposalID: String, with kg: Double) async throws
    -> TrainingMaxProposal
  {
    try await replace(proposalID: proposalID, with: kg)
  }

  public func markEffectiveCycle(_ cycleID: String) async throws {
    try await proposalRepository.markTrainingMaxProposalsEffective(cycleID: cycleID)
  }

  /// Called by lifecycle completion and also safe to call during app launch.
  @discardableResult
  public func generateMissingProposals() async throws -> [TrainingMaxProposal] {
    let existing = try await proposalRepository.loadTrainingMaxProposals()
    let cycles = try await cycleRepository.loadTrainingCycles()
    let configurations = try await liftRepository.loadLiftConfigurations()
    var generated: [TrainingMaxProposal] = []
    for cycle in cycles where cycle.lifecycleState == .completed {
      guard cycle.weeks.allSatisfy(\.isFinished) else { continue }
      let sourceIDs = Set(cycle.weeks.flatMap(\.sessions).map(\.primaryLiftID))
      for liftID in sourceIDs {
        let snapshot = cycle.liftSnapshots[liftID]
        let configuration = configurations.first { $0.id == liftID }
        guard
          let progression = snapshot?.identity.progressionLift
            ?? configuration?.identity.progressionLift
        else { continue }
        guard !existing.contains(where: { $0.sourceCycleID == cycle.id && $0.liftID == liftID })
        else { continue }
        let current = configuration?.trainingMax.kg ?? snapshot?.trainingMaxKg ?? 0
        guard current > 0 else { continue }
        let evidence = try await evidenceFor(liftID: liftID, cycle: cycle)
        let proposal = TrainingMaxProposal(
          id: uuidGenerator.makeUUID().uuidString,
          liftID: liftID,
          liftName: snapshot?.identity.displayName ?? configuration?.identity.displayName ?? liftID,
          sourceCycleID: cycle.id,
          currentTrainingMaxKg: current,
          proposedTrainingMaxKg: current + progression.trainingMaxIncrementKg,
          incrementKg: progression.trainingMaxIncrementKg,
          evidence: evidence,
          createdAt: timestamp(),
          updatedAt: timestamp()
        )
        let history = TrainingMaxHistoryEntry(
          id: uuidGenerator.makeUUID().uuidString,
          liftID: liftID,
          event: .proposal,
          occurredAt: timestamp(),
          beforeKg: current,
          afterKg: proposal.proposedTrainingMaxKg,
          proposalID: proposal.id,
          cycleID: cycle.id,
          evidence: evidence
        )
        _ = try await proposalRepository.saveTrainingMaxProposal(
          proposal, expectedBefore: nil, auditID: uuidGenerator.makeUUID().uuidString,
          occurredAt: timestamp(), history: history
        )
        generated.append(proposal)
      }
    }
    return generated
  }

  public func hasPendingProposals() async throws -> Bool {
    try await generateMissingProposals()
    return try await proposalRepository.loadTrainingMaxProposals().contains {
      $0.status == .pending
    }
  }

  private func decisionApplied(
    to proposal: TrainingMaxProposal,
    decision: TrainingMaxProposalDecision,
    decidedAt: Int64
  ) throws -> TrainingMaxProposal {
    let status: TrainingMaxProposalStatus
    switch decision {
    case .accept: status = .accepted
    case .reject: status = .rejected
    case .replace(let kg):
      guard kg.isFinite, kg > 0 else { throw TrainingMaxProposalRepositoryError.invalidDecision }
      status = .manuallyReplaced
    }
    return TrainingMaxProposal(
      id: proposal.id, liftID: proposal.liftID, liftName: proposal.liftName,
      sourceCycleID: proposal.sourceCycleID,
      currentTrainingMaxKg: proposal.currentTrainingMaxKg,
      proposedTrainingMaxKg: proposal.proposedTrainingMaxKg,
      incrementKg: proposal.incrementKg, evidence: proposal.evidence, status: status,
      decision: decision, decidedAt: decidedAt, effectiveCycleID: nil,
      createdAt: proposal.createdAt, updatedAt: decidedAt
    )
  }

  private func evidenceFor(liftID: String, cycle: TrainingCycle) async throws
    -> TrainingMaxProposalEvidence
  {
    var records: [E1RMSessionRecord] = []
    var excluded: [TrainingMaxProposalExcludedWork] = []
    for week in cycle.weeks {
      for session in week.sessions where session.primaryLiftID == liftID {
        let results = try await resultRepository?.loadSetResults(for: session.id) ?? []
        let omissions = try await resultRepository?.loadOmittedSets(for: session.id) ?? []
        let additional = try await resultRepository?.loadAdditionalSets(for: session.id) ?? []
        if session.status == .skipped {
          excluded.append(
            .init(
              id: session.id, kind: .skippedSession, cycleID: cycle.id,
              weekID: week.id, sessionID: session.id
            ))
        }
        excluded.append(
          contentsOf: omissions.map {
            .init(
              id: $0.id, kind: .omittedSet, cycleID: cycle.id, weekID: week.id,
              sessionID: session.id, prescriptionID: $0.prescriptionID, note: $0.reason
            )
          })
        excluded.append(
          contentsOf: results.filter { $0.result.isFailed }.map {
            .init(
              id: $0.id, kind: .failedSet, cycleID: cycle.id, weekID: week.id,
              sessionID: session.id, prescriptionID: $0.prescriptionID
            )
          })
        let correctionAudits =
          try await resultRepository?.sessionCorrectionAuditHistory(
            for: session.id) ?? []
        let correctedResultIDs = correctionAudits.flatMap { audit in
          let before = Dictionary(uniqueKeysWithValues: audit.before.results.map { ($0.id, $0) })
          let after = Dictionary(uniqueKeysWithValues: audit.after.results.map { ($0.id, $0) })
          return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        }
        records.append(
          E1RMSessionRecord(
            cycleID: cycle.id, cycleState: cycle.lifecycleState, weekID: week.id,
            weekKind: week.kind, session: session,
            primaryLiftName: cycle.liftSnapshots[liftID]?.identity.displayName,
            results: results, omissions: omissions, additionalSets: additional,
            correctedResultIDs: correctedResultIDs
          ))
      }
    }
    let progress = E1RMProgressCalculator().calculate(
      from: records, selectedLiftID: liftID,
      sourceState: "Completed Training Cycle \(cycle.id)"
    )
    return TrainingMaxProposalEvidence(
      eligibleE1RM: progress.observations,
      excludedWork: excluded,
      explanation: progress.explanation
    )
  }

  private func timestamp() -> Int64 { Int64(clock.now().timeIntervalSince1970) }
}
