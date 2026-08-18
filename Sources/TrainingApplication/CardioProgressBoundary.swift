import TrainingInsights

public struct CardioProgressBoundary: Sendable {
    private let repository: any HealthWorkoutRepository

    public init(repository: any HealthWorkoutRepository) {
        self.repository = repository
    }

    public func progress() async throws -> CardioProgress {
        let deleted = try await Set(repository.loadHealthWorkoutDeletionUUIDs())
        let workouts = try await repository.loadHealthWorkouts()
        var records: [CardioWorkoutRecord] = []
        for workout in workouts where !deleted.contains(workout.healthKitUUID) && Self.isCardio(workout) {
            let enrichment = try? await repository.loadHealthWorkoutEnrichment(for: workout.healthKitUUID)
            records.append(
                CardioWorkoutRecord(
                    id: workout.healthKitUUID,
                    localDate: Self.trainingDate(workout.localDate),
                    activityType: workout.activityType,
                    startDate: workout.startDate.timeIntervalSince1970,
                    endDate: workout.endDate.timeIntervalSince1970,
                    distanceMeters: Self.distance(enrichment?.distance),
                    heartRateSamples: enrichment?.heartRate.samples.map {
                        HeartRateSample(
                            id: $0.id,
                            startDate: $0.startDate.timeIntervalSince1970,
                            endDate: $0.endDate.timeIntervalSince1970,
                            beatsPerMinute: $0.beatsPerMinute,
                            source: $0.provenance.displayName,
                        )
                    } ?? [],
                ),
            )
        }
        return CardioProgressCalculator().calculate(records: records)
    }

    private static func isCardio(_ workout: HealthWorkout) -> Bool {
        switch workout.activityType.lowercased() {
        case "running", "cycling", "walking", "hiking", "elliptical", "rowing", "swimming",
             "stair climbing", "high intensity interval training", "mixed cardio", "cross training":
            true
        default:
            false
        }
    }

    private static func distance(_ detail: HealthWorkoutQuantityDetail?) -> Double? {
        guard let detail, detail.state == .available, let quantity = detail.quantity,
              quantity.unit == .meters
        else { return nil }
        return quantity.value
    }

    private static func trainingDate(_ value: String) -> TrainingDate {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return TrainingDate(year: 1970, month: 1, day: 1) }
        return TrainingDate(year: parts[0], month: parts[1], day: parts[2])
    }
}
