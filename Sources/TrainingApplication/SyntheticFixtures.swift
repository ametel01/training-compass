import Foundation

public struct SyntheticFixtureManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: String
    public let seed: UInt64
    public let ownerDataAccepted: Bool
    public let referenceDate: Date
    public let timeZoneIdentifier: String
    public let identifiers: [UUID]
}

/// The deterministic, privacy-safe scale envelope used for release
/// verification. It describes the size of the data set without materializing
/// HealthKit samples or owner records in the repository.
public struct VerificationDataEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: String
    public let seed: UInt64
    public let ownerDataAccepted: Bool
    public let referenceDate: Date
    public let timeZoneIdentifier: String
    public let coverageYears: Int
    public let healthWorkouts: Int
    public let heartRateSamples: Int
    public let sleepIntervals: Int
    public let restingHeartRateSamples: Int
    public let hrvSamples: Int
    public let trainingCycles: Int
    public let sessions: Int
    public let sets: Int
    public let routes: Int
    public let routeRetainedPoints: Int
    public let identifierSamples: [UUID]

    public init(
        seed: UInt64,
        referenceDate: Date,
        identifierSamples: [UUID],
    ) {
        schemaVersion = 1
        algorithmVersion = "verification-envelope-lcg-v1"
        self.seed = seed
        ownerDataAccepted = false
        self.referenceDate = referenceDate
        timeZoneIdentifier = "Etc/UTC"
        coverageYears = 15
        healthWorkouts = 25000
        heartRateSamples = 10_000_000
        sleepIntervals = 250_000
        restingHeartRateSamples = 50000
        hrvSamples = 100_000
        trainingCycles = 500
        sessions = 10000
        sets = 250_000
        routes = 2000
        routeRetainedPoints = 2000
        self.identifierSamples = identifierSamples
    }

    public var matchesResolvedScale: Bool {
        schemaVersion == 1
            && algorithmVersion == "verification-envelope-lcg-v1"
            && !ownerDataAccepted
            && timeZoneIdentifier == "Etc/UTC"
            && coverageYears == 15
            && healthWorkouts == 25000
            && heartRateSamples == 10_000_000
            && sleepIntervals == 250_000
            && restingHeartRateSamples == 50000
            && hrvSamples == 100_000
            && trainingCycles == 500
            && sessions == 10000
            && sets == 250_000
            && routes == 2000
            && routeRetainedPoints == 2000
    }
}

public struct SyntheticFixtureGenerator: Sendable {
    public init() {}

    public func manifest(seed: UInt64) -> SyntheticFixtureManifest {
        var generator = LinearCongruentialGenerator(state: seed)
        return SyntheticFixtureManifest(
            schemaVersion: 1,
            algorithmVersion: "gate-zero-lcg-v1",
            seed: seed,
            ownerDataAccepted: false,
            referenceDate: Date(timeIntervalSince1970: 1_767_225_600),
            timeZoneIdentifier: "Etc/UTC",
            identifiers: (0 ..< 4).map { _ in generator.nextUUID() },
        )
    }

    public func verificationEnvelope(seed: UInt64) -> VerificationDataEnvelope {
        var generator = LinearCongruentialGenerator(state: seed)
        return VerificationDataEnvelope(
            seed: seed,
            referenceDate: Date(timeIntervalSince1970: 1_767_225_600),
            identifierSamples: (0 ..< 4).map { _ in generator.nextUUID() },
        )
    }
}

private struct LinearCongruentialGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
        return state
    }

    mutating func nextUUID() -> UUID {
        let high = next()
        let low = next()
        let bytes: uuid_t = (
            UInt8(truncatingIfNeeded: high >> 56),
            UInt8(truncatingIfNeeded: high >> 48),
            UInt8(truncatingIfNeeded: high >> 40),
            UInt8(truncatingIfNeeded: high >> 32),
            UInt8(truncatingIfNeeded: high >> 24),
            UInt8(truncatingIfNeeded: high >> 16),
            UInt8(truncatingIfNeeded: high >> 8),
            UInt8(truncatingIfNeeded: high),
            UInt8(truncatingIfNeeded: low >> 56),
            UInt8(truncatingIfNeeded: low >> 48),
            UInt8(truncatingIfNeeded: low >> 40),
            UInt8(truncatingIfNeeded: low >> 32),
            UInt8(truncatingIfNeeded: low >> 24),
            UInt8(truncatingIfNeeded: low >> 16),
            UInt8(truncatingIfNeeded: low >> 8),
            UInt8(truncatingIfNeeded: low),
        )
        return UUID(uuid: bytes)
    }
}
