public enum TrainingDomainModule {}

public enum EquipmentUnit: String, Codable, Equatable, Sendable {
  case kilograms = "kg"
}

public enum ProgressionLift: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case squat = "Squat"
  case deadlift = "Deadlift"
  case benchPress = "Bench Press"
  case overheadPress = "Overhead Press"

  public var displayName: String { rawValue }

  public var trainingMaxIncrementKg: Double {
    switch self {
    case .squat, .deadlift:
      5
    case .benchPress, .overheadPress:
      2.5
    }
  }
}

public enum LiftIdentity: Codable, Equatable, Hashable, Sendable {
  case progression(ProgressionLift)
  case variant(name: String)
  case custom(name: String)

  public var displayName: String {
    switch self {
    case .progression(let lift):
      lift.displayName
    case .variant(let name), .custom(let name):
      name
    }
  }

  public var progressionLift: ProgressionLift? {
    guard case .progression(let lift) = self else { return nil }
    return lift
  }

  public var kind: Kind {
    switch self {
    case .progression: .progression
    case .variant: .variant
    case .custom: .custom
    }
  }

  public enum Kind: String, Codable, Equatable, Sendable {
    case progression
    case variant
    case custom
  }
}

public enum WeightReference: String, Codable, Equatable, Sendable {
  case trainingMax
  case loadingIncrement
  case setResult
}

public enum WeightValidationError: Error, Codable, Equatable, Sendable {
  case mustBePositive(WeightReference)
  case mustBeFinite(WeightReference)
  case invalidPercentage
  case invalidLiftName
}

public struct TrainingMax: Codable, Equatable, Sendable {
  public let kg: Double

  public init(kg: Double) throws {
    guard kg.isFinite else { throw WeightValidationError.mustBeFinite(.trainingMax) }
    guard kg > 0 else { throw WeightValidationError.mustBePositive(.trainingMax) }
    self.kg = kg
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(kg: container.decode(Double.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(kg)
  }
}

public struct LoadingIncrement: Codable, Equatable, Sendable {
  public let kg: Double

  public static let `default` = LoadingIncrement(uncheckedKg: 2.5)

  private init(uncheckedKg kg: Double) {
    self.kg = kg
  }

  public init(kg: Double = 2.5) throws {
    guard kg.isFinite else { throw WeightValidationError.mustBeFinite(.loadingIncrement) }
    guard kg > 0 else { throw WeightValidationError.mustBePositive(.loadingIncrement) }
    self.kg = kg
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(kg: container.decode(Double.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(kg)
  }
}

public enum SetResultWeightAlignment: Equatable, Sendable {
  case aligned
  case notAligned
}

public struct SetResultWeight: Codable, Equatable, Sendable {
  public let kg: Double

  public init(kg: Double) throws {
    guard kg.isFinite else { throw WeightValidationError.mustBeFinite(.setResult) }
    guard kg > 0 else { throw WeightValidationError.mustBePositive(.setResult) }
    self.kg = kg
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(kg: container.decode(Double.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(kg)
  }

  public func alignment(to increment: LoadingIncrement) -> SetResultWeightAlignment {
    let quotient = kg / increment.kg
    let nearest = quotient.rounded()
    return abs(quotient - nearest) < 0.000000001 ? .aligned : .notAligned
  }
}

public struct LoadableWeight: Codable, Equatable, Sendable {
  public let kg: Double

  public init(kg: Double) {
    self.kg = kg
  }
}

public struct LiftConfiguration: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let identity: LiftIdentity
  public let trainingMax: TrainingMax
  public let loadingIncrement: LoadingIncrement

  public init(
    id: String,
    identity: LiftIdentity,
    trainingMax: TrainingMax,
    loadingIncrement: LoadingIncrement = .default
  ) throws {
    guard identity.displayName.contains(where: { !$0.isWhitespace }) else {
      throw WeightValidationError.invalidLiftName
    }
    self.id = id
    self.identity = identity
    self.trainingMax = trainingMax
    self.loadingIncrement = loadingIncrement
  }

  public init(
    id: String,
    identity: LiftIdentity,
    trainingMaxKg: Double,
    loadingIncrementKg: Double = 2.5
  ) throws {
    try self.init(
      id: id,
      identity: identity,
      trainingMax: try TrainingMax(kg: trainingMaxKg),
      loadingIncrement: try LoadingIncrement(kg: loadingIncrementKg)
    )
  }

  public func prescribedWeight(forPercentage percentage: Double) throws -> LoadableWeight {
    guard percentage.isFinite, percentage > 0 else {
      throw WeightValidationError.invalidPercentage
    }
    let exact = trainingMax.kg * percentage / loadingIncrement.kg
    let lower = exact.rounded(.down)
    let fraction = exact - lower
    let roundedUnits = fraction > 0.5 + 0.000000001 ? lower + 1 : lower
    return LoadableWeight(kg: roundedUnits * loadingIncrement.kg)
  }

  public var snapshot: LiftConfigurationSnapshot {
    LiftConfigurationSnapshot(
      identity: identity,
      trainingMaxKg: trainingMax.kg,
      loadingIncrementKg: loadingIncrement.kg
    )
  }

  public var trainingMaxKg: Double { trainingMax.kg }

  public var loadingIncrementKg: Double { loadingIncrement.kg }
}

public struct LiftConfigurationSnapshot: Codable, Equatable, Sendable {
  public let identity: LiftIdentity
  public let trainingMaxKg: Double
  public let loadingIncrementKg: Double

  public init(identity: LiftIdentity, trainingMaxKg: Double, loadingIncrementKg: Double) {
    self.identity = identity
    self.trainingMaxKg = trainingMaxKg
    self.loadingIncrementKg = loadingIncrementKg
  }

  public var isValid: Bool {
    !identity.displayName.isEmpty
      && trainingMaxKg.isFinite && trainingMaxKg > 0
      && loadingIncrementKg.isFinite && loadingIncrementKg > 0
  }
}

public enum LiftConfigurationAuditAction: String, Codable, Equatable, Sendable {
  case created
  case edited
  case corrected
}

public struct LiftConfigurationAuditEntry: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let liftID: String
  public let action: LiftConfigurationAuditAction
  public let occurredAt: Int64
  public let before: LiftConfigurationSnapshot?
  public let after: LiftConfigurationSnapshot

  public init(
    id: String,
    liftID: String,
    action: LiftConfigurationAuditAction,
    occurredAt: Int64,
    before: LiftConfigurationSnapshot?,
    after: LiftConfigurationSnapshot
  ) {
    self.id = id
    self.liftID = liftID
    self.action = action
    self.occurredAt = occurredAt
    self.before = before
    self.after = after
  }
}
