import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingDomain
@testable import TrainingPersistence

final class TrainingExportRepositoryTests: XCTestCase {
  func testExportSnapshotContainsEveryAuthoritativeTableAndStableRecordIdentity() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "training-export-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = GRDBTrainingRepository(root: root)
    let lift = try LiftConfiguration(
      id: "lift-squat",
      identity: .progression(.squat),
      trainingMax: try TrainingMax(kg: 100)
    )
    _ = try await repository.saveLiftConfiguration(
      lift,
      expectedBefore: nil,
      auditID: "lift-audit",
      occurredAt: 10,
      action: .created
    )

    let snapshot = try await repository.loadAuthoritativeExportData()
    XCTAssertTrue(snapshot.table(named: "lifts")?.records.contains { $0.id == lift.id } == true)
    XCTAssertTrue(
      snapshot.table(named: "lift_configuration_audit")?.records.contains {
        $0.id == "lift-audit"
      } == true
    )
    XCTAssertTrue(snapshot.table(named: "gate_zero_metadata") != nil)
    XCTAssertNil(snapshot.table(named: "session_projections"))
    XCTAssertGreaterThanOrEqual(snapshot.recordCount, 3)
    let metadataID = try XCTUnwrap(snapshot.table(named: "gate_zero_metadata")?.records.first?.id)
    XCTAssertTrue(metadataID.hasPrefix("gate_zero_metadata#"))
  }
}
