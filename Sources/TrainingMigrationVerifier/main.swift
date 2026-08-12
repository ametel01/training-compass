import Foundation
import GRDB
import TrainingPersistence

enum MigrationVerificationError: Error {
  case databasesAreNotSeparate
  case expectedInterruption
  case gateZeroMarkerMissing(store: String)
  case simulatedInterruption
}

let root = FileManager.default.temporaryDirectory
  .appending(path: UUID().uuidString, directoryHint: .isDirectory)
defer { try? FileManager.default.removeItem(at: root) }

let checkpoint = InterruptOnceStoreBootstrapCheckpoint()
let bootstrapper = ProtectedStoreBootstrapper(checkpoint: checkpoint)
do {
  _ = try bootstrapper.open(in: root)
  throw MigrationVerificationError.expectedInterruption
} catch MigrationVerificationError.simulatedInterruption {
  // A retry must finish from the partially prepared on-disk state.
}

let stores = try bootstrapper.open(in: root)
let reopenedStores = try bootstrapper.open(in: root)
guard stores.authoritative.path != stores.reconstructible.path else {
  throw MigrationVerificationError.databasesAreNotSeparate
}

let authoritativeMarker = try stores.authoritative.read { db in
  try Int.fetchOne(db, sql: "SELECT owner_data_accepted FROM gate_zero_metadata")
}
guard authoritativeMarker == 0 else {
  throw MigrationVerificationError.gateZeroMarkerMissing(store: "authoritative")
}

let reconstructibleMarker = try stores.reconstructible.read { db in
  try Int.fetchOne(db, sql: "SELECT owner_data_accepted FROM gate_zero_metadata")
}
guard reconstructibleMarker == 0 else {
  throw MigrationVerificationError.gateZeroMarkerMissing(store: "reconstructible")
}

let authoritativeLiftTables = try stores.authoritative.read { db in
  Set(
    try String.fetchAll(
      db,
      sql: """
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name IN ('lifts', 'lift_configuration_audit')
        """
    ))
}
guard authoritativeLiftTables == ["lifts", "lift_configuration_audit"] else {
  throw MigrationVerificationError.gateZeroMarkerMissing(store: "authoritative v2")
}

let authoritativeRowCount = try reopenedStores.authoritative.read { db in
  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gate_zero_metadata")
}
let reconstructibleRowCount = try reopenedStores.reconstructible.read { db in
  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gate_zero_metadata")
}
guard authoritativeRowCount == 1, reconstructibleRowCount == 1 else {
  throw MigrationVerificationError.gateZeroMarkerMissing(store: "idempotent retry")
}

print(
  "Authoritative v2 and reconstructible v1 migration interruption, retry, and idempotence passed.")

final class InterruptOnceStoreBootstrapCheckpoint: StoreBootstrapCheckpointing, @unchecked Sendable
{
  private var shouldInterrupt = true

  func didMigrateAuthoritativeStore() throws {
    if shouldInterrupt {
      shouldInterrupt = false
      throw MigrationVerificationError.simulatedInterruption
    }
  }
}
