import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingPersistence

final class TrainingMaxProposalRepositoryTests: XCTestCase {
  func testCompletedCycleGeneratesEvidenceProposalAndHistoryThatSurviveRestart() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveLiftConfiguration(
      try LiftConfiguration(id: "squat", identity: .progression(.squat), trainingMaxKg: 100),
      expectedBefore: nil, auditID: "lift", occurredAt: 1, action: .created
    )
    let date = TrainingDate(year: 2024, month: 1, day: 1)
    let plus = TrainingSetPrescription(
      id: "plus", setNumber: 3, role: .primary, percentage: 0.85,
      repetitions: 5, weightKg: 85, isPlusSetEligible: true
    )
    let session = TrainingCycleSession(
      id: "session", intendedDate: date, sourceTemplateSessionID: "template",
      primaryLiftID: "squat", assistanceLiftID: "squat", prescriptions: [plus]
    )
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "template", intendedWeekday: .monday,
        primaryLiftID: "squat", assistanceLiftID: "squat")
    ])
    let loadedConfiguration = try await repository.loadLiftConfigurations().first
    let snapshot = try XCTUnwrap(loadedConfiguration?.snapshot)
    let active = TrainingCycle(
      id: "cycle", week1AnchorDate: date,
      weeks: [
        TrainingWeek(
          id: "week", position: 1, kind: .week1,
          startDate: date, sessions: [session])
      ],
      sourceTemplate: template.snapshot, includesProvisionalDeload: false,
      lifecycleState: .active,
      liftSnapshots: ["squat": snapshot]
    )
    _ = try await repository.saveTrainingCycle(
      active, expectedBefore: nil, auditID: "activate", occurredAt: 2, action: .activated
    )
    let result = RecordedSetResult(
      id: "result", sessionID: "session", prescriptionID: "plus",
      result: try SetResult(weight: try SetResultWeight(kg: 90), repetitions: 6), recordedAt: 3
    )
    _ = try await repository.saveSetResult(
      result, expectedBefore: nil, auditID: "result-audit", occurredAt: 3, action: .recorded
    )
    let completedSession = TrainingCycleSession(
      id: session.id, intendedDate: session.intendedDate,
      sourceTemplateSessionID: session.sourceTemplateSessionID,
      primaryLiftID: session.primaryLiftID, assistanceLiftID: session.assistanceLiftID,
      prescriptions: session.prescriptions, status: .completed
    )
    let completed = TrainingCycle(
      id: active.id, week1AnchorDate: active.week1AnchorDate,
      weeks: [
        TrainingWeek(
          id: "week", position: 1, kind: .week1,
          startDate: date, sessions: [completedSession])
      ],
      sourceTemplate: active.sourceTemplate, includesProvisionalDeload: false,
      lifecycleState: .completed, createdAt: active.createdAt, updatedAt: 4,
      liftSnapshots: active.liftSnapshots
    )
    let currentActive = try await repository.loadActiveTrainingCycle()
    let currentActiveCycle = try XCTUnwrap(currentActive)
    _ = try await repository.saveTrainingCycle(
      completed, expectedBefore: currentActiveCycle.snapshot, auditID: "complete", occurredAt: 4,
      action: .completed
    )

    let boundary = TrainingMaxProposalBoundary(
      repository: repository, clock: FixedProposalClock(), uuidGenerator: ProposalUUIDs())
    let proposals = try await boundary.generateMissingProposals()
    let proposal = try XCTUnwrap(proposals.first)
    XCTAssertEqual(proposal.currentTrainingMaxKg, 100)
    XCTAssertEqual(proposal.proposedTrainingMaxKg, 105)
    XCTAssertEqual(proposal.evidence.eligibleE1RM.first?.estimatedKg, 108)
    XCTAssertTrue(proposal.evidence.excludedWork.isEmpty)
    let persistedProposals = try await repository.loadTrainingMaxProposals()
    let persistedHistory = try await repository.loadTrainingMaxHistory(for: "squat")
    XCTAssertEqual(persistedProposals.count, 1)
    XCTAssertTrue(
      persistedHistory.contains {
        $0.event == .proposal && $0.proposalID == proposal.id
      })

    let restarted = GRDBTrainingRepository(root: root)
    let restartedProposal = try await restarted.loadTrainingMaxProposals().first
    XCTAssertEqual(restartedProposal, proposal)
  }

  func testDecisionUpdatesFutureTMButDoesNotRewriteCompletedCycleSnapshot() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let configuration = try LiftConfiguration(
      id: "bench", identity: .progression(.benchPress), trainingMaxKg: 80)
    _ = try await repository.saveLiftConfiguration(
      configuration, expectedBefore: nil, auditID: "lift", occurredAt: 1, action: .created)
    let proposal = TrainingMaxProposal(
      id: "proposal", liftID: "bench", liftName: "Bench Press", sourceCycleID: "cycle",
      currentTrainingMaxKg: 80, proposedTrainingMaxKg: 82.5, incrementKg: 2.5,
      evidence: TrainingMaxProposalEvidence(
        explanation: InsightExplanation(
          question: "How?", includedRecordIDs: [], excludedRecords: [], formula: "Epley",
          dateRange: "No included dates", roundingRule: "Full precision", sourceState: "Test")))
    _ = try await repository.saveTrainingMaxProposal(
      proposal, expectedBefore: nil, auditID: "proposal-audit", occurredAt: 2, history: nil)
    let boundary = TrainingMaxProposalBoundary(
      repository: repository, clock: FixedProposalClock(), uuidGenerator: ProposalUUIDs())
    _ = try await boundary.accept(proposalID: proposal.id)
    let updatedConfiguration = try await repository.loadLiftConfigurations().first
    let updatedProposal = try await repository.loadTrainingMaxProposals().first
    let history = try await repository.loadTrainingMaxHistory(for: "bench")
    XCTAssertEqual(updatedConfiguration?.trainingMax.kg, 82.5)
    XCTAssertEqual(updatedProposal?.status, .accepted)
    XCTAssertTrue(
      history.contains {
        $0.event == .accepted && $0.beforeKg == 80 && $0.afterKg == 82.5
      })
  }
}

private struct FixedProposalClock: Clock {
  func now() -> Date { Date(timeIntervalSince1970: 100) }
}

private final class ProposalUUIDs: UUIDGenerator, @unchecked Sendable {
  private var value = 0

  func makeUUID() -> UUID {
    defer { value += 1 }
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }
}
