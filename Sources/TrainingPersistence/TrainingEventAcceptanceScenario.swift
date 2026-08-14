import Foundation
import TrainingApplication

extension GRDBTrainingRepository {
  /// Installs deterministic local data for the Training Event XCUITest journey.
  /// Production composition calls this only when the explicit test launch
  /// environment is present.
  public func seedTrainingEventAcceptanceScenario(now: Date) async throws {
    try await eraseAllData(progress: nil)
    try await prepareStores()

    let today = TrainingDate(date: now)
    let template = ScheduleTemplate(sessions: [
      ScheduleSession(
        id: "ui-template-session",
        intendedWeekday: .monday,
        primaryLiftID: "ui-squat",
        assistanceLiftID: "ui-bench"
      )
    ])
    let session = TrainingCycleSession(
      id: "ui-session",
      intendedDate: today,
      sourceTemplateSessionID: "ui-template-session",
      primaryLiftID: "ui-squat",
      assistanceLiftID: "ui-bench"
    )
    let timestamp = Int64(now.timeIntervalSince1970)
    let cycle = TrainingCycle(
      id: "ui-cycle",
      week1AnchorDate: today,
      weeks: [
        TrainingWeek(
          id: "ui-week",
          position: 1,
          kind: .week1,
          startDate: today,
          sessions: [session]
        )
      ],
      sourceTemplate: template.snapshot,
      includesProvisionalDeload: false,
      lifecycleState: .active,
      createdAt: timestamp - 60,
      updatedAt: timestamp - 30,
      liftSnapshots: [
        "ui-squat": LiftConfigurationSnapshot(
          identity: .progression(.squat),
          trainingMaxKg: 100,
          loadingIncrementKg: 2.5
        ),
        "ui-bench": LiftConfigurationSnapshot(
          identity: .progression(.benchPress),
          trainingMaxKg: 75,
          loadingIncrementKg: 2.5
        ),
      ]
    )
    _ = try await saveTrainingCycle(
      cycle,
      expectedBefore: nil,
      auditID: "ui-cycle-audit",
      occurredAt: timestamp - 30,
      action: .activated
    )
    _ = try await completeSession(
      CompletedSession(sessionID: session.id, confirmedAt: timestamp),
      confirmation: .confirmed
    )

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let unusualStart = calendar.date(byAdding: .day, value: -2, to: now) ?? now
    let workouts = [
      HealthWorkout(
        healthKitUUID: "ui-likely",
        activityType: "traditional-strength-training",
        startDate: now.addingTimeInterval(-3_600),
        endDate: now.addingTimeInterval(-1_800),
        duration: 1_800,
        sourceName: "Acceptance Watch",
        sourceBundleIdentifier: "com.example.acceptance",
        sourceProductType: "Watch",
        deviceName: "Acceptance Device",
        localDate: today.iso8601String,
        firstImportedAt: now,
        reconciliationContext: "ui-scenario"
      ),
      HealthWorkout(
        healthKitUUID: "ui-unusual",
        activityType: "running",
        startDate: unusualStart,
        endDate: unusualStart.addingTimeInterval(1_800),
        duration: 1_800,
        sourceName: "Acceptance Watch",
        sourceBundleIdentifier: "com.example.acceptance",
        sourceProductType: "Watch",
        deviceName: "Acceptance Device",
        localDate: TrainingDate(date: unusualStart, calendar: calendar).iso8601String,
        firstImportedAt: now,
        reconciliationContext: "ui-scenario"
      ),
    ]
    try await upsertHealthWorkouts(workouts, reconciliationContext: "ui-scenario")
  }
}
