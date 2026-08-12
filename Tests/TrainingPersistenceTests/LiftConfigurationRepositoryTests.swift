import Foundation
import GRDB
import XCTest

@testable import TrainingDomain
@testable import TrainingPersistence

final class LiftConfigurationRepositoryTests: XCTestCase {
  func testConfigurationAndTimestampedBeforeAfterAuditSurviveRepositoryRestart() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let id = "lift-squat"
    let auditID = "audit-1"
    let first = try LiftConfiguration(
      id: id,
      identity: .progression(.squat),
      trainingMax: try TrainingMax(kg: 101)
    )
    let second = try LiftConfiguration(
      id: id,
      identity: .variant(name: "Low Bar Squat"),
      trainingMax: try TrainingMax(kg: 102.3),
      loadingIncrement: try LoadingIncrement(kg: 1.25)
    )
    let firstDate: Int64 = 100
    let secondDate: Int64 = 200

    let repository = GRDBTrainingRepository(root: root)
    let created = try await repository.saveLiftConfiguration(
      first,
      expectedBefore: nil,
      auditID: auditID,
      occurredAt: firstDate,
      action: .created
    )
    _ = try await repository.saveLiftConfiguration(
      second,
      expectedBefore: first.snapshot,
      auditID: "audit-2",
      occurredAt: secondDate,
      action: .corrected
    )

    XCTAssertNil(created.before)
    XCTAssertEqual(created.after.trainingMaxKg, 101)
    XCTAssertEqual(created.occurredAt, firstDate)

    let restarted = GRDBTrainingRepository(root: root)
    let configurations = try await restarted.loadLiftConfigurations()
    let history = try await restarted.auditHistory(for: id)
    XCTAssertEqual(configurations, [second])
    XCTAssertEqual(history.count, 2)
    XCTAssertEqual(history[1].before?.identity, .progression(.squat))
    XCTAssertEqual(history[1].after.identity, .variant(name: "Low Bar Squat"))
    XCTAssertEqual(history[1].after.loadingIncrementKg, 1.25)
  }

  func testDuplicateAuditIdentityRollsBackConfigurationAndAuditTogether() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let id = "lift-safety-bar"
    let auditID = "audit-duplicate"
    let initial = try LiftConfiguration(
      id: id,
      identity: .custom(name: "Safety Bar Squat"),
      trainingMax: try TrainingMax(kg: 80)
    )
    let replacement = try LiftConfiguration(
      id: id,
      identity: .custom(name: "Safety Bar Squat"),
      trainingMax: try TrainingMax(kg: 90)
    )
    let repository = GRDBTrainingRepository(root: root)
    _ = try await repository.saveLiftConfiguration(
      initial,
      expectedBefore: nil,
      auditID: auditID,
      occurredAt: 1,
      action: .created
    )

    do {
      _ = try await repository.saveLiftConfiguration(
        replacement,
        expectedBefore: initial.snapshot,
        auditID: auditID,
        occurredAt: 2,
        action: .edited
      )
      XCTFail("Expected duplicate audit identity to fail")
    } catch {}

    let configurations = try await repository.loadLiftConfigurations()
    let history = try await repository.auditHistory(for: id)
    XCTAssertEqual(configurations, [initial])
    XCTAssertEqual(history.count, 1)
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  }
}
