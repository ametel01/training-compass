import Foundation
import TrainingApplication

extension GRDBTrainingRepository {
  /// Installs only the lift prerequisites needed to exercise the owner-visible
  /// new-cycle journey. The schedule itself is still produced by the same
  /// default-template boundary used in the live app.
  func seedCyclePlanningAcceptanceScenario(now: Date) async throws {
    try await eraseAllData(progress: nil)
    try await prepareStores()

    let configurations: [(String, LiftIdentity, Double, Double)] = [
      ("ui-squat", .progression(.squat), 100, 2.5),
      ("ui-deadlift", .progression(.deadlift), 120, 5),
      ("ui-bench", .progression(.benchPress), 75, 2.5),
      ("ui-overhead-press", .progression(.overheadPress), 50, 2.5),
      ("ui-romanian-deadlift", .variant(name: "Romanian Deadlift"), 90, 5)
    ]
    let timestamp = Int64(now.timeIntervalSince1970)
    for (index, fixture) in configurations.enumerated() {
      let configuration = try LiftConfiguration(
        id: fixture.0,
        identity: fixture.1,
        trainingMaxKg: fixture.2,
        loadingIncrementKg: fixture.3
      )
      _ = try await saveLiftConfiguration(
        configuration,
        expectedBefore: nil,
        auditID: "ui-lift-audit-\(index)",
        occurredAt: timestamp + Int64(index),
        action: .created
      )
    }
  }

  /// Starts a real cycle one week in the past so XCUITest can exercise the
  /// spreadsheet-to-local-record import journey through production boundaries.
  func seedCycleImportAcceptanceScenario(now: Date) async throws {
    try await seedCyclePlanningAcceptanceScenario(now: now)

    let clock = SystemClock()
    let calendar = CurrentCalendarProvider()
    let uuidGenerator = RandomUUIDGenerator()
    let boundary = TrainingCycleBoundary(
      repository: self,
      clock: clock,
      calendar: calendar,
      uuidGenerator: uuidGenerator
    )
    let calendarValue = calendar.calendar()
    let previousWeek = calendarValue.date(byAdding: .day, value: -7, to: now) ?? now
    let anchor = TrainingDate.monday(containing: previousWeek, calendar: calendarValue)
    let creation = try await boundary.previewCreate(anchorDate: anchor)
    _ = try await boundary.confirm(creation)
    let activation = try await boundary.previewActivation(anchorChoice: .retain)
    _ = try await boundary.confirmActivation(activation)
  }

  /// Installs deterministic local data for the Training Event XCUITest journey.
  /// The application repository enables it only for the explicit test launch
  /// environment, keeping test orchestration out of the app model.
  func seedTrainingEventAcceptanceScenario(now: Date) async throws {
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
        )
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
      )
    ]
    try await upsertHealthWorkouts(workouts, reconciliationContext: "ui-scenario")
  }
}
