import Foundation
import TrainingApplication
import XCTest

final class PrivacyDiagnosticsTests: XCTestCase {
  func testDiagnosticsRetainNewestSevenDaysAndAtMostTwoHundredEvents() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let clock = FixedClock(date: Date(timeIntervalSince1970: 2_000_000))
    let store = PrivacyDiagnosticStore(directory: directory, clock: clock)
    let diagnostic = PrivacyDiagnostic(
      operation: .storeOpen,
      durationMilliseconds: 12,
      recordCount: 0,
      byteCount: 0,
      peakMemoryMiB: 8,
      resultCategory: .success,
      deviceConditions: .init(
        lowPowerMode: false,
        thermalState: .nominal,
        batteryState: .full,
        availableStorageMiB: 1024
      )
    )

    for _ in 0..<201 {
      try await store.append(diagnostic)
    }
    let retained = try await store.entries()
    XCTAssertEqual(retained.count, 200)

    let oldDirectory = directory.appending(
      path: "diagnostic-old.json", directoryHint: .notDirectory)
    try JSONEncoder().encode(diagnostic).write(to: oldDirectory)
    try FileManager.default.setAttributes(
      [
        .modificationDate: clock.date.addingTimeInterval(
          -PrivacyDiagnosticStore.retentionWindow - 1)
      ],
      ofItemAtPath: oldDirectory.path()
    )
    _ = try await store.entries()
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldDirectory.path()))
  }

  func testExplicitExportIsClosedSchemaAndCanBeCleanedUp() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "diagnostic-export-\(UUID().uuidString)", directoryHint: .isDirectory)
    let export = directory.appending(path: "review.json", directoryHint: .notDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = PrivacyDiagnosticStore(directory: directory, clock: FixedClock(date: Date()))
    try await store.append(
      PrivacyDiagnostic(
        operation: .healthRefresh,
        durationMilliseconds: 40,
        recordCount: 10,
        byteCount: 128,
        peakMemoryMiB: 4,
        resultCategory: .degraded,
        deviceConditions: .init(
          lowPowerMode: true,
          thermalState: .fair,
          batteryState: .charging,
          availableStorageMiB: 512
        )
      )
    )
    try await store.export(to: export)

    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: export)) as? [[String: Any]]
    )
    XCTAssertEqual(object.count, 1)
    XCTAssertEqual(
      Set(object[0].keys),
      [
        "operation", "durationMilliseconds", "recordCount", "byteCount", "peakMemoryMiB",
        "resultCategory", "deviceConditions",
      ]
    )
    XCTAssertNil(object[0]["date"])
    XCTAssertNil(object[0]["healthKitUUID"])

    try await store.removeExport(at: export)
    XCTAssertFalse(FileManager.default.fileExists(atPath: export.path()))
  }

  func testDiagnosticsApplyProtectionToStoreAndExportBoundaries() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "diagnostic-protection-\(UUID().uuidString)", directoryHint: .isDirectory)
    let export = directory.appending(path: "review.json", directoryHint: .notDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let protection = ProtectionSpy()
    let store = PrivacyDiagnosticStore(
      directory: directory, clock: FixedClock(date: Date()), protection: protection)
    try await store.append(
      PrivacyDiagnostic(
        operation: .storeOpen,
        durationMilliseconds: 0,
        recordCount: 0,
        byteCount: 0,
        peakMemoryMiB: 0,
        resultCategory: .success,
        deviceConditions: .init(
          lowPowerMode: false, thermalState: .unknown, batteryState: .unknown,
          availableStorageMiB: 0)))
    try await store.export(to: export)
    let protectedPaths = protection.paths
    XCTAssertTrue(protectedPaths.contains(directory.path()))
    XCTAssertTrue(protectedPaths.contains(export.path()))
  }
}

private struct FixedClock: Clock {
  let date: Date

  func now() -> Date { date }
}

private final class ProtectionSpy: PrivacyDiagnosticProtectionManaging, @unchecked Sendable {
  private(set) var paths: Set<String> = []
  private let lock = NSLock()

  func createDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  func applyCompleteFileProtection(to url: URL) throws {
    lock.lock()
    paths.insert(url.path())
    lock.unlock()
  }
  func excludeFromBackup(_ url: URL) throws {}
  func verifyCompleteFileProtection(at url: URL) throws {}
  func verifyExcludedFromBackup(_ url: URL) throws {}
}
