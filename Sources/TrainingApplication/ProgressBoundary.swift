import Foundation
import TrainingInsights

/// Loads immutable cycle context and current local Set Results, then delegates
/// the derived projection to TrainingInsights. No calculated progress is
/// persisted: it can always be rebuilt from authoritative records.
public struct ProgressBoundary: Sendable {
    private let cycleRepository: any TrainingCycleRepository
    private let resultRepository: any SetResultRepository
    private let liftRepository: any LiftConfigurationRepository
    private let clock: any Clock

    public init(
        cycleRepository: any TrainingCycleRepository,
        resultRepository: any SetResultRepository,
        liftRepository: any LiftConfigurationRepository,
        clock: any Clock = SystemClock(),
    ) {
        self.cycleRepository = cycleRepository
        self.resultRepository = resultRepository
        self.liftRepository = liftRepository
        self.clock = clock
    }

    public init(repository: any TrainingRepository, clock: any Clock = SystemClock()) {
        self.init(
            cycleRepository: repository,
            resultRepository: repository,
            liftRepository: repository,
            clock: clock,
        )
    }

    public func progress(selectedLiftID: String? = nil) async throws -> E1RMProgress {
        let cycles = try await cycleRepository.loadTrainingCycles()
        let activeCycle = cycles.first(where: { $0.lifecycleState == .active })
        let configurations = try await liftRepository.loadLiftConfigurations()
        let contexts = Dictionary(
            uniqueKeysWithValues: configurations.map { configuration in
                (
                    configuration.id,
                    E1RMTrainingMaxContext(
                        liftID: configuration.id,
                        liftName: configuration.identity.displayName,
                        currentTrainingMaxKg: configuration.trainingMax.kg,
                        loadingIncrementKg: configuration.loadingIncrement.kg,
                        activeCycleTrainingMaxKg: activeCycle?.liftSnapshots[configuration.id]?.trainingMaxKg,
                    ),
                )
            },
        )

        var sources: [E1RMSessionRecord] = []
        for cycle in cycles {
            for week in cycle.weeks {
                for session in week.sessions {
                    let correctionAudits = try await resultRepository.sessionCorrectionAuditHistory(
                        for: session.id,
                    )
                    let correctedResultIDs = correctionAudits.flatMap { audit in
                        let before = Dictionary(uniqueKeysWithValues: audit.before.results.map { ($0.id, $0) })
                        let after = Dictionary(uniqueKeysWithValues: audit.after.results.map { ($0.id, $0) })
                        return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
                    }
                    try await sources.append(
                        E1RMSessionRecord(
                            cycleID: cycle.id,
                            cycleState: cycle.lifecycleState,
                            weekID: week.id,
                            weekKind: week.kind,
                            session: session,
                            primaryLiftName: cycle.liftSnapshots[session.primaryLiftID]?.identity.displayName,
                            results: resultRepository.loadSetResults(for: session.id),
                            omissions: resultRepository.loadOmittedSets(for: session.id),
                            additionalSets: resultRepository.loadAdditionalSets(for: session.id),
                            correctedResultIDs: correctedResultIDs,
                        ),
                    )
                }
            }
        }
        return E1RMProgressCalculator().calculate(
            from: sources,
            selectedLiftID: selectedLiftID,
            currentTrainingMaxContexts: contexts,
            asOfDate: TrainingDate(date: clock.now()),
        )
    }

    public func load(selectedLiftID: String? = nil) async throws -> E1RMProgress {
        try await progress(selectedLiftID: selectedLiftID)
    }
}
