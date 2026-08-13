import Foundation
import XCTest

@testable import TrainingApplication

final class TrainingExportBoundaryTests: XCTestCase {
  func testPreviewWarnsBeforeCreationAndArchiveIsDeterministicAndVerifiable() async throws {
    let data = TrainingAuthoritativeExportData(
      tables: [
        TrainingExportTable(
          name: "lifts",
          records: [
            TrainingExportRecord(
              id: "lift-1",
              fields: [
                "id": .string("lift-1"),
                "training_max_kg": .number(100),
              ]
            )
          ]
        )
      ],
      preferences: [TrainingExportPreference(key: "guidance", value: .boolean(false))]
    )
    let fileSystem = MemoryExportFileSystem()
    let boundary = makeBoundary(data: data, fileSystem: fileSystem)
    let preview = try await boundary.preview()

    XCTAssertTrue(preview.requiresSensitiveDataConfirmation)
    XCTAssertTrue(preview.warning.localizedCaseInsensitiveContains("unencrypted"))
    XCTAssertEqual(preview.summary.recordCount, 1)
    XCTAssertThrowsError(try boundary.create(preview, confirmation: .cancelled)) { error in
      XCTAssertEqual(error as? TrainingExportError, .confirmationRequired)
    }

    let first = try boundary.create(preview, confirmation: .confirmed)
    try first.archive.verifyIntegrity()
    let firstData = try first.archive.encodedData()
    let writtenData = fileSystem.data(at: first.url)
    XCTAssertEqual(firstData, writtenData)

    let second = try boundary.create(preview, confirmation: .confirmed)
    XCTAssertEqual(first.archive, second.archive)
    XCTAssertEqual(firstData, try second.archive.encodedData())

    let tampered = TrainingCompassExport(
      manifest: first.archive.manifest,
      summary: TrainingExportSummary(
        recordCount: 99,
        tableCounts: first.archive.summary.tableCounts,
        readableText: first.archive.summary.readableText
      ),
      authoritativeData: first.archive.authoritativeData,
      healthKitMirror: first.archive.healthKitMirror,
      integrity: first.archive.integrity
    )
    XCTAssertThrowsError(try tampered.verifyIntegrity()) { error in
      XCTAssertEqual(error as? TrainingExportError, .integrityMismatch)
    }
  }

  func testMirrorIsSeparateReferenceMaterialAndCleanupRunsForCancellation() async throws {
    let fileSystem = MemoryExportFileSystem()
    let boundary = TrainingExportBoundary(
      repository: ExportRepository(data: TrainingAuthoritativeExportData(tables: [])),
      clock: FixedClock(date: Date(timeIntervalSince1970: 42)),
      timeZone: FixedTimeZone(identifier: "UTC"),
      uuidGenerator: FixedUUIDGenerator(),
      fileSystem: fileSystem,
      mirrorProvider: MirrorProvider(
        snapshot: TrainingHealthKitMirrorExport(
          records: [TrainingExportTable(name: "workouts", records: [])]
        )
      )
    )
    let preview = try await boundary.preview(includeHealthKitMirror: true)
    XCTAssertEqual(preview.healthKitMirror?.source, "HealthKit Mirror (reference material)")
    let artifact = try boundary.create(preview, confirmation: .confirmed)

    let outcome = try boundary.completeShare(artifact, outcome: .cancelled)
    XCTAssertEqual(outcome, .cancelled)
    let removedURLs = fileSystem.removedURLs
    XCTAssertTrue(removedURLs.contains(artifact.url))
  }

  func testInsufficientSpaceRefusesBeforeWritingAndCleansTheReservedPath() async throws {
    let fileSystem = MemoryExportFileSystem(availableSpace: 0)
    let boundary = makeBoundary(
      data: TrainingAuthoritativeExportData(
        tables: [
          TrainingExportTable(
            name: "lifts",
            records: [
              TrainingExportRecord(id: "lift", fields: ["id": .string("lift")])
            ]
          )
        ]
      ),
      fileSystem: fileSystem
    )
    let preview = try await boundary.preview()

    do {
      _ = try boundary.create(preview, confirmation: .confirmed)
      XCTFail("Expected an insufficient-space refusal")
    } catch let error as TrainingExportError {
      guard case .insufficientSpace = error else {
        return XCTFail("Unexpected export error: \(error)")
      }
    }
    XCTAssertEqual(fileSystem.fileCount, 0)
    XCTAssertEqual(fileSystem.removedURLs.count, 1)
  }

  func testRecoverableFailureCleansUpTheTemporaryArtifact() async throws {
    let fileSystem = MemoryExportFileSystem()
    let boundary = makeBoundary(
      data: TrainingAuthoritativeExportData(tables: []), fileSystem: fileSystem
    )
    let artifact = try boundary.create(try await boundary.preview(), confirmation: .confirmed)
    XCTAssertEqual(
      try boundary.completeShare(artifact, outcome: .recoverableFailure), .recoverableFailure)
    XCTAssertEqual(fileSystem.fileCount, 0)
  }

  func testInterruptionStopsPreviewAndDiagnosticsDoNotExposeStorageDetails() async throws {
    let boundary = TrainingExportBoundary(
      repository: SlowExportRepository(),
      clock: FixedClock(date: Date(timeIntervalSince1970: 42)),
      timeZone: FixedTimeZone(identifier: "UTC"),
      uuidGenerator: FixedUUIDGenerator(),
      fileSystem: MemoryExportFileSystem()
    )
    let task = Task { try await boundary.preview() }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected interruption path.
    }

    let diagnostic = TrainingExportError.insufficientSpace(
      requiredBytes: 123_456, availableBytes: 7
    ).privacySafeDescription
    XCTAssertFalse(diagnostic.contains("123456"))
    XCTAssertFalse(diagnostic.contains("7"))
  }

  private func makeBoundary(
    data: TrainingAuthoritativeExportData,
    fileSystem: MemoryExportFileSystem
  ) -> TrainingExportBoundary {
    TrainingExportBoundary(
      repository: ExportRepository(data: data),
      clock: FixedClock(date: Date(timeIntervalSince1970: 42)),
      timeZone: FixedTimeZone(identifier: "UTC"),
      uuidGenerator: FixedUUIDGenerator(),
      fileSystem: fileSystem,
      generatorVersion: "test/1"
    )
  }
}

private actor ExportRepository: TrainingAuthoritativeExportRepository {
  let data: TrainingAuthoritativeExportData

  init(data: TrainingAuthoritativeExportData) { self.data = data }

  func loadAuthoritativeExportData() async throws -> TrainingAuthoritativeExportData { data }
}

private actor MirrorProvider: TrainingHealthKitMirrorExportProvider {
  let snapshot: TrainingHealthKitMirrorExport

  init(snapshot: TrainingHealthKitMirrorExport) { self.snapshot = snapshot }

  func exportHealthKitMirror() async throws -> TrainingHealthKitMirrorExport { snapshot }
}

private actor SlowExportRepository: TrainingAuthoritativeExportRepository {
  func loadAuthoritativeExportData() async throws -> TrainingAuthoritativeExportData {
    try await Task.sleep(for: .milliseconds(100))
    return TrainingAuthoritativeExportData(tables: [])
  }
}

private final class MemoryExportFileSystem: TrainingExportFileSystem, TrainingExportSpaceChecking,
  @unchecked Sendable
{
  private let lock = NSLock()
  private let availableSpace: Int64
  private var files: [URL: Data] = [:]
  private var removed: [URL] = []

  init(availableSpace: Int64 = .max) { self.availableSpace = availableSpace }

  func temporaryExportDirectory() throws -> URL {
    URL(filePath: "/tmp/training-compass-export-tests")
  }

  func write(_ data: Data, to url: URL) throws {
    lock.lock()
    defer { lock.unlock() }
    files[url] = data
  }

  func removeItem(at url: URL) throws {
    lock.lock()
    defer { lock.unlock() }
    files[url] = nil
    removed.append(url)
  }

  func data(at url: URL) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return files[url]
  }

  var removedURLs: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return removed
  }

  var fileCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return files.count
  }

  func availableExportSpaceBytes() throws -> Int64 { availableSpace }
}

private struct FixedClock: Clock {
  let date: Date
  func now() -> Date { date }
}

private struct FixedTimeZone: TimeZoneProvider {
  let identifier: String
  func timeZone() -> TimeZone { TimeZone(identifier: identifier)! }
}

private struct FixedUUIDGenerator: UUIDGenerator {
  func makeUUID() -> UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
}
