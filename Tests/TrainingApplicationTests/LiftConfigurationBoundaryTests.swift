import Foundation
import XCTest

@testable import TrainingApplication
@testable import TrainingDomain

final class LiftConfigurationBoundaryTests: XCTestCase {
  func testValidCreationUsesDefaultIncrementAndRecordsCreatedAudit() async throws {
    let repository = InMemoryLiftConfigurationRepository()
    let boundary = LiftConfigurationBoundary(
      repository: repository,
      clock: FixedClock(date: Date(timeIntervalSince1970: 123)),
      uuidGenerator: SequenceUUIDGenerator(values: [uuid(1), uuid(2)])
    )

    let audit = try await boundary.save(
      LiftConfigurationRequest(
        identity: .progression(.benchPress),
        trainingMaxKg: 72.3
      )
    )

    XCTAssertEqual(audit.action, .created)
    XCTAssertNil(audit.before)
    XCTAssertEqual(audit.after.loadingIncrementKg, 2.5)
    let configurations = try await boundary.list()
    XCTAssertEqual(configurations.count, 1)
    let rows = try await boundary.listTMs()
    XCTAssertEqual(
      rows.prefix(4).map { $0.identity.displayName },
      ["Squat", "Deadlift", "Bench Press", "Overhead Press"]
    )
  }

  func testInvalidReferenceIsRejectedBeforeRepositoryMutation() async throws {
    let repository = InMemoryLiftConfigurationRepository()
    let boundary = LiftConfigurationBoundary(
      repository: repository,
      clock: FixedClock(date: Date()),
      uuidGenerator: SequenceUUIDGenerator(values: [uuid(3), uuid(4)])
    )

    do {
      _ = try await boundary.save(
        LiftConfigurationRequest(identity: .custom(name: "Home Lift"), trainingMaxKg: 0)
      )
      XCTFail("Expected invalid Training Max")
    } catch let error as WeightValidationError {
      XCTAssertEqual(error, .mustBePositive(.trainingMax))
    }

    let saved = await repository.savedCount
    XCTAssertEqual(saved, 0)
  }

  func testCorrectiveEditIsDistinguishedAndPreservesTheBeforeValue() async throws {
    let repository = InMemoryLiftConfigurationRepository()
    let boundary = LiftConfigurationBoundary(
      repository: repository,
      clock: FixedClock(date: Date(timeIntervalSince1970: 500)),
      uuidGenerator: SequenceUUIDGenerator(values: [uuid(5), uuid(6), uuid(7)])
    )
    let created = try await boundary.save(
      LiftConfigurationRequest(identity: .progression(.deadlift), trainingMaxKg: 140)
    )
    let corrected = try await boundary.save(
      LiftConfigurationRequest(
        id: created.liftID,
        identity: .progression(.deadlift),
        trainingMaxKg: 137.5,
        isCorrection: true
      )
    )

    XCTAssertEqual(corrected.action, .corrected)
    XCTAssertEqual(corrected.before?.trainingMaxKg, 140)
    XCTAssertEqual(corrected.after.trainingMaxKg, 137.5)
  }

  private func uuid(_ value: UInt8) -> UUID {
    UUID(uuidString: String(format: "%02X000000-0000-0000-0000-000000000000", value))!
  }
}

private struct FixedClock: Clock {
  let date: Date

  func now() -> Date { date }
}

private final class SequenceUUIDGenerator: UUIDGenerator, @unchecked Sendable {
  var values: [UUID]
  private var index = 0

  init(values: [UUID]) { self.values = values }

  func makeUUID() -> UUID {
    defer { index += 1 }
    return values[min(index, values.count - 1)]
  }
}

private actor InMemoryLiftConfigurationRepository: LiftConfigurationRepository {
  private(set) var configurations: [String: LiftConfiguration] = [:]
  private(set) var audits: [LiftConfigurationAuditEntry] = []

  var savedCount: Int { audits.count }

  func loadLiftConfigurations() async throws -> [LiftConfiguration] {
    configurations.values.sorted { $0.id < $1.id }
  }

  func saveLiftConfiguration(
    _ configuration: LiftConfiguration,
    auditID: String,
    occurredAt: Int64,
    action: LiftConfigurationAuditAction
  ) async throws -> LiftConfigurationAuditEntry {
    let before = configurations[configuration.id]?.snapshot
    let audit = LiftConfigurationAuditEntry(
      id: auditID,
      liftID: configuration.id,
      action: action,
      occurredAt: occurredAt,
      before: before,
      after: configuration.snapshot
    )
    configurations[configuration.id] = configuration
    audits.append(audit)
    return audit
  }

  func auditHistory(for liftID: String) async throws -> [LiftConfigurationAuditEntry] {
    audits.filter { $0.liftID == liftID }
  }
}
