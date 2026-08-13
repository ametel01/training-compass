import SwiftUI
import TrainingApplication
import UIKit

struct RootView: View {
  let model: AppModel
  let concealsSensitiveContent: Bool

  var body: some View {
    ZStack {
      TabView {
        NavigationStack {
          TodayView(model: model)
        }
        .tabItem { Label("Today", systemImage: "sun.max") }
        .accessibilityIdentifier("tab.today")

        NavigationStack {
          CycleView(model: model)
        }
        .tabItem { Label("Cycle", systemImage: "calendar") }
        .accessibilityIdentifier("tab.cycle")

        NavigationStack {
          StrengthProgressView(model: model)
        }
        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
        .accessibilityIdentifier("tab.progress")

        NavigationStack {
          TMsView(model: model)
        }
        .tabItem { Label("TMs", systemImage: "scalemass") }
        .accessibilityIdentifier("tab.tms")
      }
      .privacySensitive()
      .task { await model.prepare() }

      if concealsSensitiveContent {
        PrivacyShield()
          .transition(.opacity)
          .zIndex(1)
      }
    }
  }
}

private struct StrengthProgressView: View {
  let model: AppModel

  @State private var progress: E1RMProgress?
  @State private var selectedLiftID: String?
  @State private var showingLongerHistory = false
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if model.phase != .ready {
        ContentUnavailableView(
          "Progress unavailable",
          systemImage: "chart.line.uptrend.xyaxis",
          description: Text("Preparing protected local stores.")
        )
      } else if let progress {
        List {
          if !progress.availableLifts.isEmpty {
            Section("Lift") {
              Picker("Selected Lift", selection: selectedLiftBinding) {
                ForEach(progress.availableLifts) { lift in
                  Text(lift.name).tag(Optional(lift.id))
                }
              }
              .accessibilityIdentifier("progress.lift-picker")
            }
          }

          Section("e1RM Summary") {
            ProgressMetric(label: "Latest", observation: progress.latest)
            ProgressMetric(label: "Previous", observation: progress.previous)
            ProgressMetric(label: "Cycle best", observation: progress.cycleBest)
            LabeledContent(
              "Trailing 90-day direction", value: progress.trailing90DayDirection.displayName)
          }

          if let context = progress.currentTrainingMaxContext {
            Section("Current Training Max") {
              LabeledContent(
                "Current", value: String(format: "%.1f kg", context.currentTrainingMaxKg))
              if let active = context.activeCycleTrainingMaxKg {
                LabeledContent(
                  "Active Cycle Snapshot", value: String(format: "%.1f kg", active))
              }
              LabeledContent(
                "Loading Increment", value: String(format: "%.1f kg", context.loadingIncrementKg))
            }
          }

          Section("History") {
            let visible =
              showingLongerHistory ? progress.observations : Array(progress.observations.suffix(3))
            if visible.isEmpty {
              Text("No eligible Plus Set Results yet.").foregroundStyle(.secondary)
            } else {
              ForEach(visible) { observation in
                NavigationLink {
                  ProgressSourceDetailView(observation: observation)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    HStack {
                      Text(observation.displayValue).font(.headline)
                      Spacer()
                      Text(observation.date.iso8601String).font(.caption).foregroundStyle(
                        .secondary)
                    }
                    Text(
                      "\(observation.repetitions) reps at \(observation.weightKg, specifier: "%.2f") kg · \(observation.weekKind.displayName)"
                    )
                    .font(.caption)
                    Text(
                      "Plus Set Result \(observation.sourceLink.resultID) · Cycle \(observation.sourceLink.cycleID) · \(observation.correctionState.displayName)"
                    )
                    .font(.caption2).foregroundStyle(.secondary)
                  }
                }
                .accessibilityIdentifier("progress.observation.\(observation.id)")
              }
            }
            if progress.hasLongerHistory && !showingLongerHistory {
              Button("Show Longer History") { showingLongerHistory = true }
                .accessibilityIdentifier("progress.show-history")
            }
          }

          Section("Insight Explanation") {
            Text(progress.explanation.text)
              .font(.caption)
            if !progress.excludedRecords.isEmpty {
              DisclosureGroup("Excluded Records (\(progress.excludedRecords.count))") {
                ForEach(progress.excludedRecords) { excluded in
                  Text("\(excluded.label) · \(excluded.reason.displayName)")
                    .font(.caption)
                }
              }
            }
          }
        }
        .refreshable { await reload() }
      } else {
        ContentUnavailableView(
          "No Progress Yet",
          systemImage: "chart.line.uptrend.xyaxis",
          description: Text(
            "Complete an eligible normal-week Primary Plus Set to see e1RM progress.")
        )
      }
    }
    .navigationTitle("Progress")
    .accessibilityIdentifier("progress.destination")
    .task(id: model.phase) {
      if model.phase == .ready { await reload() }
    }
    .alert(
      "Could not load Progress",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Try again.")
    }
  }

  private var selectedLiftBinding: Binding<String?> {
    Binding(
      get: { selectedLiftID ?? progress?.selectedLiftID },
      set: {
        selectedLiftID = $0
        Task { await reload() }
      }
    )
  }

  private func reload() async {
    do {
      progress = try await model.progressBoundary.progress(selectedLiftID: selectedLiftID)
      if selectedLiftID == nil { selectedLiftID = progress?.selectedLiftID }
    } catch {
      progress = nil
      errorMessage = String(describing: error)
    }
  }
}

private struct ProgressSourceDetailView: View {
  let observation: E1RMObservation

  var body: some View {
    List {
      Section("Plus Set Result") {
        LabeledContent("Result ID", value: observation.sourceLink.resultID)
        LabeledContent("Prescription", value: observation.sourceLink.prescriptionID)
        LabeledContent("Session", value: observation.sourceLink.sessionID)
      }
      Section("Cycle Context") {
        LabeledContent("Cycle", value: observation.sourceLink.cycleID)
        LabeledContent("Week", value: observation.sourceLink.weekID)
        LabeledContent("Date", value: observation.date.iso8601String)
        LabeledContent("Correction", value: observation.sourceLink.correctionState.displayName)
      }
    }
    .navigationTitle("Progress Source")
  }
}

private struct ProgressMetric: View {
  let label: String
  let observation: E1RMObservation?

  var body: some View {
    if let observation {
      LabeledContent(label, value: observation.displayValue)
    } else {
      LabeledContent(label, value: "—")
    }
  }
}

private struct TodayView: View {
  let model: AppModel

  @State private var today: TodaySessionSnapshot?
  @State private var weightText: [String: String] = [:]
  @State private var repetitionsText: [String: String] = [:]
  @State private var additionalLiftID = ""
  @State private var additionalWeightText = ""
  @State private var additionalRepetitionsText = ""
  @State private var additionalNote = ""
  @State private var editingAdditionalSetID: String?
  @State private var showingCompletionConfirmation = false
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if model.phase != .ready {
        ContentUnavailableView {
          Label("Training Compass", systemImage: "location.north.circle.fill")
        } description: {
          VStack(spacing: 12) {
            Text("PRE-DATA BUILD")
              .font(.caption.weight(.bold))
              .foregroundStyle(.orange)
              .accessibilityIdentifier("today.preparing")
            status
          }
        }
      } else if let today {
        List {
          Section("Scheduled Session") {
            LabeledContent("Date", value: today.intendedDate.iso8601String)
            LabeledContent("Training Week", value: today.weekKind.displayName)
            LabeledContent("State", value: today.state.displayName)
            Text(
              "Primary: \(today.primaryLift.identity.displayName) · Assistance: \(today.assistanceLift.identity.displayName)"
            )
            .font(.subheadline)
          }

          Section("Training Max Snapshots") {
            LabeledContent(
              today.primaryLift.identity.displayName,
              value: "\(today.primaryLift.trainingMaxKg) kg"
            )
            LabeledContent(
              today.assistanceLift.identity.displayName,
              value: "\(today.assistanceLift.trainingMaxKg) kg"
            )
          }

          Section("Prescribed Sets") {
            ForEach(today.sets) { set in
              TodaySetRow(
                set: set,
                weight: Binding(
                  get: { weightText[set.id] ?? set.result.map { String($0.weightKg) } ?? "" },
                  set: { weightText[set.id] = $0 }
                ),
                repetitions: Binding(
                  get: {
                    repetitionsText[set.id]
                      ?? set.result.map { String($0.repetitions) }
                      ?? String(set.prescription.repetitions)
                  },
                  set: { repetitionsText[set.id] = $0 }
                ),
                onConfirm: { Task { await confirm(set) } },
                onOmit: { Task { await omit(set) } }
              )
            }
          }

          Section("Additional Sets") {
            ForEach(today.additionalSets) { additional in
              VStack(alignment: .leading, spacing: 4) {
                Text(
                  "\(additional.liftID) · \(additional.weightKg, specifier: "%.2f") kg · \(additional.repetitions) reps"
                )
                if let note = additional.note {
                  Text(note).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                  Button("Edit") { beginEditing(additional) }
                  Button("Remove", role: .destructive) { Task { await remove(additional) } }
                }
                .font(.caption)
              }
            }
            .onMove { from, to in
              let ids = today.additionalSets.map(\.id).reordered(fromOffsets: from, toOffset: to)
              Task { await reorderAdditionalSets(ids) }
            }
            TextField("Lift", text: $additionalLiftID)
            TextField("Weight (kg)", text: $additionalWeightText)
              .keyboardType(.decimalPad)
            TextField("Repetitions", text: $additionalRepetitionsText)
              .keyboardType(.numberPad)
            TextField("Note (optional)", text: $additionalNote)
            HStack {
              Button(editingAdditionalSetID == nil ? "Add Additional Set" : "Save Additional Set") {
                Task { await saveAdditionalSet() }
              }
              .buttonStyle(.borderedProminent)
              if editingAdditionalSetID != nil {
                Button("Cancel") { clearAdditionalDraft() }
              }
            }
          }

          if let completion = today.completion {
            Section("Completed Session") {
              LabeledContent("Confirmed", value: String(completion.confirmedAt))
              LabeledContent("Performed", value: "\(today.plannedVersusActual.performed.count)")
              LabeledContent("Omitted", value: "\(today.plannedVersusActual.omitted.count)")
              LabeledContent("Additional", value: "\(today.plannedVersusActual.additional.count)")
              ForEach(today.sets) { set in
                VStack(alignment: .leading, spacing: 2) {
                  Text(
                    "Set \(set.prescription.setNumber) · \(set.prescription.role.rawValue.capitalized)"
                  )
                  Text(
                    "Planned: \(set.prescription.weightKg, specifier: "%.2f") kg × \(set.prescription.repetitions) reps"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  if let result = set.result {
                    Text(
                      "Actual: \(result.weightKg, specifier: "%.2f") kg × \(result.repetitions) reps\(result.repetitions == 0 ? " · Failed" : "")"
                    )
                    .font(.caption)
                  } else if let omission = set.omission {
                    Text(omission.reason.map { "Omitted: \($0)" } ?? "Omitted")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          } else if today.state == .readyToComplete {
            Section {
              Button("Complete Session") { showingCompletionConfirmation = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("today.complete")
            } footer: {
              Text("Every prescribed set has a confirmed result or an Omitted disposition.")
            }
          }
        }
        .refreshable { await reload() }
        .toolbar { EditButton() }
      } else {
        ContentUnavailableView {
          Label("Nothing scheduled today", systemImage: "checkmark.circle")
        } description: {
          Text(
            "Activate a Training Cycle with a Session intended for today to log prescribed work here."
          )
          .multilineTextAlignment(.center)
        }
      }
    }
    .navigationTitle("Today")
    .accessibilityIdentifier("today.destination")
    .task(id: model.phase) {
      if model.phase == .ready { await reload() }
    }
    .alert(
      "Could not record Set Result",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Try again.")
    }
    .confirmationDialog(
      "Complete this Session?",
      isPresented: $showingCompletionConfirmation,
      titleVisibility: .visible
    ) {
      Button("Confirm Completion") { Task { await complete() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Completion records the planned-versus-actual work and every set disposition.")
    }
  }

  @ViewBuilder
  private var status: some View {
    switch model.phase {
    case .preparing:
      ProgressView("Preparing protected local stores")
        .accessibilityIdentifier("pre-data.preparing")
    case .ready:
      Label("Protected local shell ready", systemImage: "lock.shield")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("pre-data.ready")
    case .failed:
      Label("Protected stores could not be prepared", systemImage: "exclamationmark.shield")
        .foregroundStyle(.red)
        .accessibilityIdentifier("today.failed")
    }
  }

  private func reload() async {
    do {
      today = try await model.sessionLoggingBoundary.today()
    } catch {
      today = nil
      errorMessage = String(describing: error)
    }
  }

  private func confirm(_ set: TodaySetSnapshot) async {
    guard let weight = Double(weightText[set.id] ?? set.result.map { String($0.weightKg) } ?? ""),
      let repetitions = Int(
        repetitionsText[set.id]
          ?? set.result.map { String($0.repetitions) }
          ?? String(set.prescription.repetitions)
      )
    else {
      errorMessage = "Enter a positive kilogram weight and whole-number repetitions."
      return
    }
    do {
      _ = try await model.sessionLoggingBoundary.recordSetResult(
        sessionID: today?.session.id ?? "",
        prescriptionID: set.prescription.id,
        weightKg: weight,
        repetitions: repetitions,
        expectedBefore: set.result
      )
      await reload()
    } catch {
      errorMessage =
        (error as? TrainingExportError)?.privacySafeDescription
        ?? "The export could not be prepared."
    }
  }

  private func omit(_ set: TodaySetSnapshot) async {
    do {
      _ = try await model.sessionLoggingBoundary.omitSet(
        sessionID: today?.session.id ?? "",
        prescriptionID: set.prescription.id,
        expectedBefore: set.result
      )
      await reload()
    } catch { errorMessage = String(describing: error) }
  }

  private func complete() async {
    do {
      _ = try await model.sessionLoggingBoundary.confirmSession(sessionID: today?.session.id ?? "")
      await reload()
    } catch { errorMessage = String(describing: error) }
  }

  private func beginEditing(_ set: AdditionalSet) {
    editingAdditionalSetID = set.id
    additionalLiftID = set.liftID
    additionalWeightText = String(set.weightKg)
    additionalRepetitionsText = String(set.repetitions)
    additionalNote = set.note ?? ""
  }

  private func clearAdditionalDraft() {
    editingAdditionalSetID = nil
    additionalLiftID = ""
    additionalWeightText = ""
    additionalRepetitionsText = ""
    additionalNote = ""
  }

  private func saveAdditionalSet() async {
    guard let weight = Double(additionalWeightText),
      let repetitions = Int(additionalRepetitionsText),
      !additionalLiftID.isEmpty
    else {
      errorMessage = "Enter a lift, positive kilogram weight, and non-negative repetitions."
      return
    }
    do {
      if let id = editingAdditionalSetID {
        _ = try await model.sessionLoggingBoundary.editAdditionalSet(
          sessionID: today?.session.id ?? "", id: id, liftID: additionalLiftID,
          weightKg: weight, repetitions: repetitions, note: additionalNote
        )
      } else {
        _ = try await model.sessionLoggingBoundary.addAdditionalSet(
          sessionID: today?.session.id ?? "", liftID: additionalLiftID,
          weightKg: weight, repetitions: repetitions, note: additionalNote
        )
      }
      clearAdditionalDraft()
      await reload()
    } catch { errorMessage = String(describing: error) }
  }

  private func remove(_ set: AdditionalSet) async {
    do {
      try await model.sessionLoggingBoundary.removeAdditionalSet(
        sessionID: today?.session.id ?? "", id: set.id)
      await reload()
    } catch { errorMessage = String(describing: error) }
  }

  private func reorderAdditionalSets(_ ids: [String]) async {
    do {
      try await model.sessionLoggingBoundary.reorderAdditionalSets(
        sessionID: today?.session.id ?? "", orderedIDs: ids)
      await reload()
    } catch { errorMessage = String(describing: error) }
  }
}

private struct TodaySetRow: View {
  let set: TodaySetSnapshot
  @Binding var weight: String
  @Binding var repetitions: String
  let onConfirm: () -> Void
  let onOmit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Set \(set.prescription.setNumber) · \(set.prescription.role.rawValue.capitalized)")
          .font(.headline)
        Spacer()
        Text(
          "Target \(set.prescription.repetitions) reps at \(set.prescription.weightKg, specifier: "%.2f") kg"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      HStack {
        TextField("kg", text: $weight)
          .keyboardType(.decimalPad)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("today.weight.\(set.id)")
        TextField("reps", text: $repetitions)
          .keyboardType(.numberPad)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("today.repetitions.\(set.id)")
        Button(set.result == nil ? "Confirm" : "Update") { onConfirm() }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("today.confirm.\(set.id)")
      }
      if set.omission == nil {
        Button("Omit Set", role: .destructive) { onOmit() }
          .font(.caption)
          .accessibilityIdentifier("today.omit.\(set.id)")
      }
      if set.hasLoadingIncrementWarning {
        Label(
          "Actual weight is outside this lift's Loading Increment; it will still be recorded.",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
      if set.completionState == .recorded {
        Label("Confirmed actual result", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.green)
      }
      if set.completionState == .failed {
        Label("Failed attempt recorded (0 reps)", systemImage: "exclamationmark.circle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
      if let omission = set.omission {
        Label(
          omission.reason.map { "Omitted: \($0)" } ?? "Omitted set",
          systemImage: "minus.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct UnavailableDestinationView: View {
  let title: String
  let systemImage: String
  let detail: String

  var body: some View {
    ContentUnavailableView(
      "\(title) unavailable",
      systemImage: systemImage,
      description: Text(detail)
    )
    .navigationTitle(title)
    .accessibilityIdentifier("pre-data.\(title.lowercased()).unavailable")
  }
}

private struct CycleView: View {
  let model: AppModel

  @State private var template: ScheduleTemplate?
  @State private var draftCycle: TrainingCycle?
  @State private var activeCycle: TrainingCycle?
  @State private var cycleHistory: [TrainingCycleHistoryEntry] = []
  @State private var cycleAudits: [TrainingCycleAuditEntry] = []
  @State private var workingSessions: [ScheduleSession] = []
  @State private var lifts: [LiftConfiguration] = []
  @State private var draft: ScheduleSessionDraft?
  @State private var cycleSessionDraft: CycleSessionDraft?
  @State private var pendingSave: ScheduleTemplateChangePreview?
  @State private var pendingReset: ScheduleTemplateChangePreview?
  @State private var pendingCycleChange: TrainingCycleChangePreview?
  @State private var pendingCycleActivation: TrainingCycleActivationPreview?
  @State private var pendingCycleDiscard: TrainingCycleChangePreview?
  @State private var anchorDate = TrainingDate.monday(containing: Date()).date()
  @State private var showingSaveConfirmation = false
  @State private var showingResetConfirmation = false
  @State private var showingCycleConfirmation = false
  @State private var showingCycleActivationConfirmation = false
  @State private var showingCycleDiscardConfirmation = false
  @State private var pendingLifecycleRequest: CycleLifecycleRequest?
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if template == nil {
        AnyView(
          UnavailableDestinationView(
            title: "Cycle",
            systemImage: "calendar",
            detail:
              "Configure Squat, Deadlift, Bench Press, Overhead Press, and Romanian Deadlift in TMs to initialize the Schedule Template."
          ))
      } else {
        AnyView(
          List {
            Section {
              Text(
                "This reusable normal-week layout is copied into future Training Cycles. Changes stay local until you explicitly save them."
              )
              .font(.footnote)
              .foregroundStyle(.secondary)
            }

            Section("Draft Training Cycle") {
              if let draftCycle {
                DraftCycleSummary(
                  cycle: draftCycle,
                  liftName: liftName,
                  onEdit: {
                    cycleSessionDraft = CycleSessionDraft(
                      session: $0, week: $1, cycleID: draftCycle.id
                    )
                  }
                )
                Button("Replace schedule from current template") {
                  Task { await reviewCycleReplacement() }
                }
                .accessibilityIdentifier("cycle.replace-schedule")
                Button("Regenerate Draft") {
                  Task { await reviewCycleRegeneration() }
                }
                .accessibilityIdentifier("cycle.regenerate")
                Button("Discard Draft", role: .destructive) {
                  Task { await reviewCycleDiscard() }
                }
                .accessibilityIdentifier("cycle.discard")
                if activeCycle == nil {
                  Button("Activate (retain anchor)") {
                    Task { await reviewCycleActivation(anchorChoice: .retain) }
                  }
                  .accessibilityIdentifier("cycle.activate")
                  DatePicker(
                    "Replacement Week 1 Anchor",
                    selection: $anchorDate,
                    displayedComponents: [.date]
                  )
                  Button("Activate using replacement date") {
                    Task {
                      await reviewCycleActivation(
                        anchorChoice: .replace(
                          TrainingDate(date: anchorDate)
                        ))
                    }
                  }
                  .accessibilityIdentifier("cycle.activate-replace-anchor")
                }
              } else {
                DatePicker(
                  "Week 1 Anchor Date",
                  selection: $anchorDate,
                  displayedComponents: [.date]
                )
                Button("Prepare Draft Training Cycle") {
                  Task { await reviewCycleCreation() }
                }
                .accessibilityIdentifier("cycle.create-draft")
                Text("The date is stored without a time zone. It defaults to Monday.")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
              if let activeCycle {
                ActiveCycleSection(
                  cycle: activeCycle,
                  liftName: liftName,
                  onEdit: {
                    cycleSessionDraft = CycleSessionDraft(
                      session: $0, week: $1, cycleID: activeCycle.id
                    )
                  },
                  onRequestLifecycle: { pendingLifecycleRequest = $0 }
                )
              }
            }

            Section("Change History") {
              if cycleAudits.isEmpty {
                Text("No Calendar Changes or Program Edits yet.")
                  .foregroundStyle(.secondary)
              } else {
                ForEach(cycleAudits) { audit in
                  Text(
                    audit.changeKind == .calendarChange
                      ? "Calendar Change"
                      : audit.changeKind == .programEdit ? "Program Edit" : audit.action.rawValue)
                }
              }
            }

            if !cycleHistory.isEmpty {
              Section("Training Cycle History") {
                ForEach(cycleHistory) { entry in
                  DisclosureGroup {
                    ForEach(entry.audits) { audit in
                      Text(audit.action.rawValue + (audit.note.map { " · \($0)" } ?? ""))
                        .font(.caption)
                    }
                    Text("Sessions: \(entry.sessions.count) planned")
                      .font(.caption)
                  } label: {
                    VStack(alignment: .leading) {
                      Text(entry.week1AnchorDate.iso8601String)
                      Text(
                        "\(entry.lifecycleBadge) · \(entry.includesDeloadBadge ? "Deload" : "No Deload")"
                      )
                      .font(.caption)
                      .foregroundStyle(.secondary)
                    }
                  }
                }
              }
            }

            Section("Schedule Template") {
              ForEach(workingSessions) { session in
                Button {
                  draft = ScheduleSessionDraft(session: session)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(session.intendedWeekday.displayName)
                      .font(.headline)
                    Text(
                      "Primary: \(liftName(session.primaryLiftID)) · Assistance: \(liftName(session.assistanceLiftID))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                  }
                }
                .accessibilityIdentifier("schedule.edit.\(session.id)")
                .swipeActions {
                  Button(role: .destructive) {
                    remove(session)
                  } label: {
                    Label("Remove", systemImage: "trash")
                  }
                  .accessibilityIdentifier("schedule.remove.\(session.id)")
                }
              }
              .onMove { offsets, destination in
                workingSessions.move(fromOffsets: offsets, toOffset: destination)
              }

              Button {
                draft = ScheduleSessionDraft.new(liftID: lifts[0].id)
              } label: {
                Label("Add session", systemImage: "plus")
              }
              .accessibilityIdentifier("schedule.add")
            }
          }
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              EditButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
              Button("Reset") {
                Task { await reviewReset() }
              }
              .accessibilityIdentifier("schedule.reset")
              Button("Save") {
                Task { await reviewSave() }
              }
              .disabled(workingSessions.isEmpty)
              .accessibilityIdentifier("schedule.save")
            }
          })
      }
    }
    .navigationTitle("Cycle")
    .accessibilityIdentifier("schedule.destination")
    .task(id: model.phase) {
      if model.phase == .ready {
        await reload()
      }
    }
    .sheet(item: $draft) { draft in
      ScheduleSessionEditor(draft: draft, lifts: lifts) { reviewedDraft in
        self.draft = nil
        apply(reviewedDraft)
      }
    }
    .sheet(item: $cycleSessionDraft) { draft in
      CycleSessionEditor(draft: draft, lifts: lifts) { reviewedDraft in
        self.cycleSessionDraft = nil
        Task { await reviewCycleEdit(reviewedDraft) }
      }
    }
    .alert("Confirm schedule save", isPresented: $showingSaveConfirmation) {
      Button("Cancel", role: .cancel) {
        pendingSave = nil
      }
      Button("Save") {
        guard let pendingSave else { return }
        Task { await confirmSave(pendingSave) }
      }
    } message: {
      Text("Save this Schedule Template for future Training Cycles?")
    }
    .alert("Reset Schedule Template", isPresented: $showingResetConfirmation) {
      Button("Cancel", role: .cancel) {
        pendingReset = nil
      }
      Button("Reset", role: .destructive) {
        guard let pendingReset else { return }
        Task { await confirmReset(pendingReset) }
      }
    } message: {
      Text(defaultPreviewText)
    }
    .alert(
      "Could not update Schedule Template",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Try again.")
    }
    .alert("Confirm Draft Training Cycle", isPresented: $showingCycleConfirmation) {
      Button("Cancel", role: .cancel) { pendingCycleChange = nil }
      Button(cycleConfirmationActionTitle) {
        guard let pendingCycleChange else { return }
        Task { await confirmCycleChange(pendingCycleChange) }
      }
    } message: {
      Text(cyclePreviewText)
    }
    .alert("Activate Training Cycle", isPresented: $showingCycleActivationConfirmation) {
      Button("Cancel", role: .cancel) { pendingCycleActivation = nil }
      Button("Activate") {
        guard let pendingCycleActivation else { return }
        Task { await confirmCycleActivation(pendingCycleActivation) }
      }
    } message: {
      Text(cycleActivationPreviewText)
    }
    .alert("Discard Draft Training Cycle", isPresented: $showingCycleDiscardConfirmation) {
      Button("Cancel", role: .cancel) { pendingCycleDiscard = nil }
      Button("Discard", role: .destructive) {
        guard let pendingCycleDiscard else { return }
        Task { await confirmCycleDiscard(pendingCycleDiscard) }
      }
    } message: {
      Text(
        "This permanently removes the editable draft. The Schedule Template and any Active Training Cycle remain unchanged."
      )
    }
    .confirmationDialog(
      lifecycleRequestTitle,
      isPresented: Binding(
        get: { pendingLifecycleRequest != nil },
        set: { if !$0 { pendingLifecycleRequest = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button(lifecycleRequestConfirmTitle, role: lifecycleRequestIsDestructive ? .destructive : nil)
      {
        let request = pendingLifecycleRequest
        pendingLifecycleRequest = nil
        Task { await perform(request) }
      }
      Button("Cancel", role: .cancel) { pendingLifecycleRequest = nil }
    } message: {
      Text(lifecycleRequestMessage)
    }
  }

  private var defaultPreviewText: String {
    guard let pendingReset else { return "" }
    return pendingReset.after.sessions.map { session in
      "\(session.intendedWeekday.displayName): \(liftName(session.primaryLiftID)) / \(liftName(session.assistanceLiftID))"
    }.joined(separator: "\n")
  }

  private func reload() async {
    do {
      let loadedLifts = try await model.scheduleTemplateBoundary.availableLifts()
      let loadedTemplate = try await model.scheduleTemplateBoundary.list()
      lifts = loadedLifts
      template = loadedTemplate
      workingSessions = loadedTemplate.sessions
      draftCycle = try await model.trainingCycleBoundary.draft()
      activeCycle = try await model.trainingCycleBoundary.active()
      if let cycle = activeCycle ?? draftCycle {
        cycleAudits = try await model.trainingCycleBoundary.auditHistory(for: cycle.id)
      } else {
        cycleAudits = []
      }
      cycleHistory = try await model.trainingCycleBoundary.history()
    } catch {
      template = nil
      draftCycle = nil
      errorMessage = nil
    }
  }

  private var lifecycleRequestTitle: String {
    switch pendingLifecycleRequest {
    case .skipSession: "Skip Session?"
    case .skipWeek: "Skip Remaining Sessions?"
    case .finishWeek: "Finish Training Week?"
    case .complete: "Complete Training Cycle?"
    case .abandon: "Abandon Training Cycle?"
    case nil: "Confirm Cycle Change"
    }
  }

  private var lifecycleRequestConfirmTitle: String {
    switch pendingLifecycleRequest {
    case .skipSession: "Skip Session"
    case .skipWeek: "Skip Remaining Sessions"
    case .finishWeek: "Finish Week"
    case .complete: "Complete Cycle"
    case .abandon: "Abandon Cycle"
    case nil: "Confirm"
    }
  }

  private var lifecycleRequestIsDestructive: Bool {
    if case .abandon = pendingLifecycleRequest { return true }
    return false
  }

  private var lifecycleRequestMessage: String {
    if case .complete = pendingLifecycleRequest, let activeCycle {
      let count = activeCycle.weeks.flatMap(\.sessions).filter { $0.status == .skipped }.count
      return count == 0
        ? "No Sessions were Skipped. This lifecycle change is recorded in cycle history."
        : "\(count) Session\(count == 1 ? "" : "s") will be recorded as Skipped before completion."
    }
    return "This lifecycle change is recorded in the cycle history."
  }

  private func perform(_ request: CycleLifecycleRequest?) async {
    do {
      switch request {
      case .skipSession(let sessionID):
        _ = try await model.trainingCycleBoundary.skipSession(
          sessionID: sessionID, confirmation: .confirmed)
      case .skipWeek(let weekID):
        _ = try await model.trainingCycleBoundary.skipRemainingSessions(
          in: weekID, confirmation: .confirmed)
      case .finishWeek(let weekID):
        _ = try await model.trainingCycleBoundary.finishWeek(
          weekID: weekID, confirmation: .confirmed)
      case .complete:
        _ = try await model.trainingCycleBoundary.completeCycle(confirmation: .confirmed)
      case .abandon:
        _ = try await model.trainingCycleBoundary.abandonCycle(confirmation: .confirmed)
      case nil:
        return
      }
      await reload()
    } catch {
      errorMessage = String(describing: error)
    }
  }

  private func liftName(_ id: String) -> String {
    lifts.first(where: { $0.id == id })?.identity.displayName ?? id
  }

  private func apply(_ draft: ScheduleSessionDraft) {
    let session = draft.session
    if let index = workingSessions.firstIndex(where: { $0.id == session.id }) {
      workingSessions[index] = session
    } else {
      workingSessions.append(session)
    }
  }

  private func remove(_ session: ScheduleSession) {
    guard workingSessions.count > 1 else {
      errorMessage = "A Schedule Template must retain at least one Session."
      return
    }
    workingSessions.removeAll { $0.id == session.id }
  }

  private func reviewSave() async {
    do {
      pendingSave = try await model.scheduleTemplateBoundary.preview(
        ScheduleTemplateRequest(
          sessions: workingSessions.map { session in
            ScheduleSessionRequest(
              id: session.id,
              intendedWeekday: session.intendedWeekday,
              primaryLiftID: session.primaryLiftID,
              assistanceLiftID: session.assistanceLiftID
            )
          })
      )
      showingSaveConfirmation = true
    } catch {
      errorMessage = String(describing: error)
    }
  }

  private func confirmSave(_ preview: ScheduleTemplateChangePreview) async {
    do {
      _ = try await model.scheduleTemplateBoundary.confirm(preview)
      pendingSave = nil
      await reload()
    } catch {
      pendingSave = nil
      errorMessage = String(describing: error)
    }
  }

  private func reviewReset() async {
    do {
      pendingReset = try await model.scheduleTemplateBoundary.previewReset()
      showingResetConfirmation = true
    } catch {
      errorMessage = String(describing: error)
    }
  }

  private func confirmReset(_ preview: ScheduleTemplateChangePreview) async {
    do {
      _ = try await model.scheduleTemplateBoundary.confirm(preview)
      pendingReset = nil
      await reload()
    } catch {
      pendingReset = nil
      errorMessage = String(describing: error)
    }
  }

  private var cyclePreviewText: String {
    guard let preview = pendingCycleChange, let cycle = preview.after else { return "" }
    let deload: String
    if cycle.includesProvisionalDeload {
      deload = "A provisional Deload Week is included."
    } else {
      deload = "No Deload Week is due yet."
    }
    let warning = preview.warning.map { " \($0)" } ?? ""
    return "Week 1 begins \(cycle.week1AnchorDate.iso8601String). The draft contains "
      + "\(cycle.weeks.count) fixed Training Weeks. \(deload)" + warning
  }

  private var cycleConfirmationActionTitle: String {
    switch pendingCycleChange?.action {
    case .created: "Create"
    case .edited: "Save Edits"
    case .calendarChanged: "Apply Calendar Change"
    case .programEdited: "Save Program Edit"
    case .savedWeekToTemplate: "Save to Template"
    case .replacedSchedule: "Replace Schedule"
    case .regenerated: "Regenerate"
    case .activated: "Activate"
    case .sessionSkipped: "Skip Session"
    case .weekFinished: "Finish Week"
    case .completed: "Complete Cycle"
    case .abandoned: "Abandon Cycle"
    case .discarded, .none: "Confirm"
    }
  }

  private var cycleActivationPreviewText: String {
    guard let preview = pendingCycleActivation else { return "" }
    let deload =
      preview.after.includesProvisionalDeload
      ? "A Deload Week is included."
      : "No Deload Week is due."
    let warning =
      preview.deloadRemovalWarning
      ? " Customized Deload work will be removed."
      : ""
    return "Week 1 remains anchored on (preview.after.week1AnchorDate.iso8601String). "
      + "The activated cycle stores immutable Training Max snapshots and prescriptions. "
      + deload + warning
  }

  private func reviewCycleCreation() async {
    do {
      pendingCycleChange = try await model.trainingCycleBoundary.previewCreate(
        anchorDate: anchorDate
      )
      showingCycleConfirmation = true
    } catch { errorMessage = String(describing: error) }
  }

  private func reviewCycleReplacement() async {
    do {
      pendingCycleChange = try await model.trainingCycleBoundary.previewReplaceSchedule()
      showingCycleConfirmation = true
    } catch { errorMessage = String(describing: error) }
  }

  private func reviewCycleRegeneration() async {
    do {
      pendingCycleChange = try await model.trainingCycleBoundary.previewRegenerate()
      showingCycleConfirmation = true
    } catch { errorMessage = String(describing: error) }
  }

  private func reviewCycleDiscard() async {
    do {
      pendingCycleDiscard = try await model.trainingCycleBoundary.previewDiscard()
      showingCycleDiscardConfirmation = true
    } catch { errorMessage = String(describing: error) }
  }

  private func reviewCycleActivation(
    anchorChoice: TrainingCycleActivationAnchorChoice
  ) async {
    do {
      pendingCycleActivation = try await model.trainingCycleBoundary.previewActivation(
        anchorChoice: anchorChoice
      )
      showingCycleActivationConfirmation = true
    } catch { errorMessage = String(describing: error) }
  }

  private func confirmCycleActivation(_ preview: TrainingCycleActivationPreview) async {
    do {
      _ = try await model.trainingCycleBoundary.confirmActivation(preview)
      pendingCycleActivation = nil
      await reload()
    } catch {
      pendingCycleActivation = nil
      errorMessage = String(describing: error)
    }
  }

  private func reviewCycleEdit(_ draft: CycleSessionDraft) async {
    guard
      let cycle = [activeCycle, draftCycle].compactMap({ $0 }).first(where: {
        $0.id == draft.cycleID
      }),
      let weekIndex = cycle.weeks.firstIndex(where: { $0.id == draft.weekID }),
      let sessionIndex = cycle.weeks[weekIndex].sessions.firstIndex(where: { $0.id == draft.id })
    else { return }
    let old = cycle.weeks[weekIndex].sessions[sessionIndex]
    let dateChanged = TrainingDate(date: draft.intendedDate, calendar: .current) != old.intendedDate
    let rolesChanged =
      draft.primaryLiftID != old.primaryLiftID
      || draft.assistanceLiftID != old.assistanceLiftID
    guard dateChanged || rolesChanged else { return }
    if dateChanged && rolesChanged {
      errorMessage =
        "Choose Calendar Change for a date move or Program Edit for lift roles. Save them separately."
      return
    }
    if dateChanged {
      do {
        pendingCycleChange = try await model.trainingCycleBoundary.previewCalendarChange(
          sessionID: old.id,
          intendedDate: TrainingDate(date: draft.intendedDate, calendar: .current)
        )
        showingCycleConfirmation = true
      } catch { errorMessage = String(describing: error) }
      return
    }
    let replacement = TrainingCycleSession(
      id: old.id,
      intendedDate: old.intendedDate,
      sourceTemplateSessionID: old.sourceTemplateSessionID,
      primaryLiftID: draft.primaryLiftID,
      assistanceLiftID: draft.assistanceLiftID,
      prescriptions: old.prescriptions,
      status: old.status
    )
    var weeks = cycle.weeks
    var sessions = weeks[weekIndex].sessions
    sessions[sessionIndex] = replacement
    weeks[weekIndex] = TrainingWeek(
      id: weeks[weekIndex].id,
      position: weeks[weekIndex].position,
      kind: weeks[weekIndex].kind,
      startDate: weeks[weekIndex].startDate,
      sessions: sessions
    )
    let request = TrainingCycleEditRequest(
      id: cycle.id,
      week1AnchorDate: cycle.week1AnchorDate,
      weeks: weeks.map { TrainingWeekRequest(cycleWeek: $0) }
    )
    do {
      pendingCycleChange = try await model.trainingCycleBoundary.previewProgramEdit(request)
      showingCycleConfirmation = true
    } catch { errorMessage = String(describing: error) }
  }

  private func confirmCycleChange(_ preview: TrainingCycleChangePreview) async {
    do {
      switch preview.action {
      case .calendarChanged:
        _ = try await model.trainingCycleBoundary.confirmCalendarChange(
          preview, acknowledgeOutsideWeek: true
        )
      case .programEdited:
        _ = try await model.trainingCycleBoundary.confirmProgramEdit(preview)
      default:
        _ = try await model.trainingCycleBoundary.confirm(preview)
      }
      pendingCycleChange = nil
      await reload()
    } catch {
      pendingCycleChange = nil
      errorMessage = String(describing: error)
    }
  }

  private func confirmCycleDiscard(_ preview: TrainingCycleChangePreview) async {
    do {
      _ = try await model.trainingCycleBoundary.discard()
      pendingCycleDiscard = nil
      await reload()
    } catch {
      pendingCycleDiscard = nil
      errorMessage = String(describing: error)
    }
  }

}

private struct ScheduleSessionDraft: Identifiable, Sendable {
  let id: String
  let existingID: String?
  var intendedWeekday: ScheduleWeekday
  var primaryLiftID: String
  var assistanceLiftID: String

  var session: ScheduleSession {
    ScheduleSession(
      id: existingID ?? id,
      intendedWeekday: intendedWeekday,
      primaryLiftID: primaryLiftID,
      assistanceLiftID: assistanceLiftID
    )
  }

  init(session: ScheduleSession) {
    id = session.id
    existingID = session.id
    intendedWeekday = session.intendedWeekday
    primaryLiftID = session.primaryLiftID
    assistanceLiftID = session.assistanceLiftID
  }

  static func new(liftID: String) -> ScheduleSessionDraft {
    ScheduleSessionDraft(
      id: UUID().uuidString,
      existingID: nil,
      intendedWeekday: .monday,
      primaryLiftID: liftID,
      assistanceLiftID: liftID
    )
  }

  private init(
    id: String,
    existingID: String?,
    intendedWeekday: ScheduleWeekday,
    primaryLiftID: String,
    assistanceLiftID: String
  ) {
    self.id = id
    self.existingID = existingID
    self.intendedWeekday = intendedWeekday
    self.primaryLiftID = primaryLiftID
    self.assistanceLiftID = assistanceLiftID
  }
}

private struct ScheduleSessionEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: ScheduleSessionDraft
  let lifts: [LiftConfiguration]
  let onReview: (ScheduleSessionDraft) -> Void

  init(
    draft: ScheduleSessionDraft,
    lifts: [LiftConfiguration],
    onReview: @escaping (ScheduleSessionDraft) -> Void
  ) {
    _draft = State(initialValue: draft)
    self.lifts = lifts
    self.onReview = onReview
  }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Intended weekday", selection: $draft.intendedWeekday) {
          ForEach(ScheduleWeekday.allCases, id: \.self) { weekday in
            Text(weekday.displayName).tag(weekday)
          }
        }
        Picker("Primary Lift", selection: $draft.primaryLiftID) {
          ForEach(lifts) { lift in
            Text(lift.identity.displayName).tag(lift.id)
          }
        }
        Picker("Assistance Lift", selection: $draft.assistanceLiftID) {
          ForEach(lifts) { lift in
            Text(lift.identity.displayName).tag(lift.id)
          }
        }
        Text("Primary and Assistance may use the same configured lift.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .navigationTitle(draft.existingID == nil ? "Add Session" : "Edit Session")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { onReview(draft) }
            .accessibilityIdentifier("schedule.session.done")
        }
      }
    }
  }
}

private struct DraftCycleSummary: View {
  let cycle: TrainingCycle
  let liftName: (String) -> String
  let onEdit: (TrainingCycleSession, TrainingWeek) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LabeledContent("Lifecycle", value: cycle.lifecycleState.displayName)
      LabeledContent("Week 1 Anchor", value: cycle.week1AnchorDate.iso8601String)
      LabeledContent("Deload", value: cycle.includesProvisionalDeload ? "Provisional" : "Not due")
      ForEach(cycle.weeks) { week in
        VStack(alignment: .leading, spacing: 5) {
          Text("\(week.position). \(week.kind.displayName)")
            .font(.headline)
          Text("\(week.startDate.iso8601String) · \(week.sessions.count) Sessions")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(week.sessions) { session in
            Button {
              onEdit(session, week)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(session.intendedDate.iso8601String)
                  .font(.subheadline)
                Text(
                  "Primary: \(liftName(session.primaryLiftID)) · "
                    + "Assistance: \(liftName(session.assistanceLiftID))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
            .accessibilityIdentifier("cycle.edit.\(session.id)")
          }
        }
        .padding(.vertical, 4)
      }
    }
  }
}

private struct ActiveCycleSection: View {
  let cycle: TrainingCycle
  let liftName: (String) -> String
  let onEdit: (TrainingCycleSession, TrainingWeek) -> Void
  let onRequestLifecycle: (CycleLifecycleRequest) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Active Training Cycle", systemImage: "play.circle")
        .font(.headline)
      Text("\(cycle.week1AnchorDate.iso8601String) · \(cycle.weeks.count) Training Weeks")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Text("Calendar Changes and Program Edits affect Scheduled Sessions only.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      ForEach(cycle.weeks) { week in
        VStack(alignment: .leading, spacing: 5) {
          Text("\(week.position). \(week.kind.displayName)").font(.headline)
          ForEach(week.sessions) { session in
            Button {
              onEdit(session, week)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(session.intendedDate.iso8601String)
                Text(
                  "\(session.status.rawValue.capitalized) · Primary: \(liftName(session.primaryLiftID)) · Assistance: \(liftName(session.assistanceLiftID))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
            if session.status == .scheduled {
              Button("Skip Session") { onRequestLifecycle(.skipSession(session.id)) }
                .font(.caption)
                .accessibilityIdentifier("cycle.skip.\(session.id)")
            }
          }
          if week.sessions.contains(where: { $0.status == .scheduled }) {
            Button("Skip Remaining Sessions in Week") {
              onRequestLifecycle(.skipWeek(week.id))
            }
            .font(.caption)
            .accessibilityIdentifier("cycle.skip-week.\(week.id)")
          }
          if week.isFinishable {
            Button("Finish Week") { onRequestLifecycle(.finishWeek(week.id)) }
              .font(.caption)
              .accessibilityIdentifier("cycle.finish-week.(week.id)")
          }
        }
      }
      Button("Complete Training Cycle") { onRequestLifecycle(.complete) }
        .buttonStyle(.borderedProminent)
        .disabled(!cycle.weeks.allSatisfy(\.isFinished))
        .accessibilityIdentifier("cycle.complete")
      Button("Abandon Training Cycle", role: .destructive) { onRequestLifecycle(.abandon) }
        .accessibilityIdentifier("cycle.abandon")
    }
  }
}

private enum CycleLifecycleRequest {
  case skipSession(String)
  case skipWeek(String)
  case finishWeek(String)
  case complete
  case abandon
}

private struct CycleHistorySection: View {
  let audits: [TrainingCycleAuditEntry]
  let title: (TrainingCycleAuditEntry) -> String

  var body: some View {
    Section("Change History") {
      if audits.isEmpty {
        Text("No Calendar Changes or Program Edits yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(audits) { audit in
          VStack(alignment: .leading, spacing: 3) {
            Text(title(audit)).font(.headline)
            Text(String(audit.occurredAt)).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

private struct CycleSessionDraft: Identifiable, Sendable {
  let id: String
  let weekID: String
  let cycleID: String
  var intendedDate: Date
  var primaryLiftID: String
  var assistanceLiftID: String

  init(session: TrainingCycleSession, week: TrainingWeek, cycleID: String = "") {
    id = session.id
    weekID = week.id
    self.cycleID = cycleID
    intendedDate = session.intendedDate.date(in: .current)
    primaryLiftID = session.primaryLiftID
    assistanceLiftID = session.assistanceLiftID
  }
}

private struct CycleSessionEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: CycleSessionDraft
  let lifts: [LiftConfiguration]
  let onReview: (CycleSessionDraft) -> Void

  init(
    draft: CycleSessionDraft,
    lifts: [LiftConfiguration],
    onReview: @escaping (CycleSessionDraft) -> Void
  ) {
    _draft = State(initialValue: draft)
    self.lifts = lifts
    self.onReview = onReview
  }

  var body: some View {
    NavigationStack {
      Form {
        DatePicker("Intended date", selection: $draft.intendedDate, displayedComponents: [.date])
        Picker("Primary Lift", selection: $draft.primaryLiftID) {
          ForEach(lifts) { lift in
            Text(lift.identity.displayName).tag(lift.id)
          }
        }
        Picker("Assistance Lift", selection: $draft.assistanceLiftID) {
          ForEach(lifts) { lift in
            Text(lift.identity.displayName).tag(lift.id)
          }
        }
        Text("This changes only this Draft Training Cycle, not the Schedule Template.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .navigationTitle("Edit Draft Session")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Review") { onReview(draft) }
            .accessibilityIdentifier("cycle.session.review")
        }
      }
    }
  }
}

extension TrainingWeekRequest {
  init(cycleWeek: TrainingWeek) {
    self.init(
      id: cycleWeek.id,
      position: cycleWeek.position,
      kind: cycleWeek.kind,
      startDate: cycleWeek.startDate,
      sessions: cycleWeek.sessions.map {
        TrainingCycleSessionRequest(
          id: $0.id,
          intendedDate: TrainingDate(date: $0.intendedDate.date(in: .current), calendar: .current),
          primaryLiftID: $0.primaryLiftID,
          assistanceLiftID: $0.assistanceLiftID
        )
      }
    )
  }
}

extension Array {
  fileprivate
    func reordered(fromOffsets offsets: IndexSet, toOffset destination: Int) -> [Element]
  {
    var copy = self
    let moving = offsets.sorted(by: >).map { copy.remove(at: $0) }.reversed()
    let adjustedDestination = Swift.min(destination, copy.count)
    copy.insert(contentsOf: moving, at: adjustedDestination)
    return copy
  }
}

private struct TMsView: View {
  private struct ImportURL: Identifiable {
    let url: URL
    var id: URL { url }
  }

  let model: AppModel

  @State private var rows: [LiftConfigurationListItem] = LiftCatalog.progressionIdentities.map {
    LiftConfigurationListItem(identity: $0, configuration: nil)
  }
  @State private var draft: TMDraft?
  @State private var pendingPreview: LiftConfigurationChangePreview?
  @State private var proposals: [TrainingMaxProposal] = []
  @State private var manualProposal: TrainingMaxProposal?
  @State private var manualValue = ""
  @State private var showingConfirmation = false
  @State private var errorMessage: String?
  @State private var showingExport = false
  @State private var showingImport = false
  @State private var importURL: ImportURL?

  var body: some View {
    List {
      Section {
        Text(
          "Kilograms are the only equipment unit. Training Maxes are calculation references; Set Results may be entered at any positive load."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Progression Lifts") {
        ForEach(rows.filter { $0.identity.progressionLift != nil }) { item in
          TMRow(item: item) {
            draft = TMDraft(item: item)
          }
        }
      }

      Section("Training Max Proposals") {
        if proposals.isEmpty {
          Text("No completed-cycle proposals are waiting for review.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(proposals) { proposal in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(proposal.liftName).font(.headline)
                Spacer()
                Text(proposal.status.rawValue.capitalized)
                  .font(.caption).foregroundStyle(.secondary)
              }
              Text(
                "\(proposal.currentTrainingMaxKg, specifier: "%.1f") → \(proposal.proposedTrainingMaxKg, specifier: "%.1f") kg · Cycle \(proposal.sourceCycleID)"
              )
              .font(.subheadline)
              Text(
                "Evidence: \(proposal.evidence.eligibleE1RM.count) eligible e1RM · \(proposal.evidence.excludedWork.count) excluded records"
              )
              .font(.caption).foregroundStyle(.secondary)
              DisclosureGroup("Review evidence") {
                ForEach(proposal.evidence.eligibleE1RM) { observation in
                  let displayValue = observation.displayValue
                  let date = observation.date.iso8601String
                  Text("e1RM \(displayValue) · \(date)")
                    .font(.caption)
                }
                ForEach(proposal.evidence.excludedWork) { work in
                  Text("\(work.kind.displayName) · \(work.note ?? work.id)")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Text(proposal.evidence.explanation.text)
                  .font(.caption2).foregroundStyle(.secondary)
              }
              if proposal.status == .pending {
                HStack {
                  Button("Accept") { Task { await decide(proposal, .accept) } }
                    .accessibilityIdentifier("tm.proposal.accept.\(proposal.id)")
                  Button("Reject") { Task { await decide(proposal, .reject) } }
                    .accessibilityIdentifier("tm.proposal.reject.\(proposal.id)")
                  Button("Replace") {
                    manualProposal = proposal
                    manualValue = String(format: "%.1f", proposal.proposedTrainingMaxKg)
                  }
                  .accessibilityIdentifier("tm.proposal.replace.\(proposal.id)")
                }
              }
            }
            .accessibilityIdentifier("tm.proposal.\(proposal.id)")
          }
        }
      }

      Section("Other Lifts") {
        let customRows = rows.filter { $0.identity.progressionLift == nil }
        if customRows.isEmpty {
          Text("No variants or custom lifts yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(customRows) { item in
            TMRow(item: item) {
              draft = TMDraft(item: item)
            }
          }
        }
      }
    }
    .refreshable { await reload() }
    .navigationTitle("TMs")
    .accessibilityIdentifier("tms.destination")
    .toolbar {
      ToolbarItemGroup(placement: .topBarLeading) {
        Button("Add custom", systemImage: "plus") {
          draft = TMDraft.newCustom()
        }
        .accessibilityIdentifier("tm.add-custom")
        Button("Add variant", systemImage: "plus") {
          draft = TMDraft.newVariant()
        }
        .accessibilityIdentifier("tm.add-variant")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Export", systemImage: "square.and.arrow.up") {
            showingExport = true
          }
          if model.trainingImportBoundary != nil {
            Button("Restore Export", systemImage: "arrow.down.doc") {
              showingImport = true
            }
            .accessibilityIdentifier("tm.import")
          }
        } label: {
          Label("Data Recovery", systemImage: "externaldrive")
        }
        .accessibilityIdentifier("tm.data-recovery")
      }
    }
    .task(id: model.phase) {
      if model.phase == .ready {
        await reload()
      }
    }
    .sheet(item: $draft) { draft in
      LiftEditor(draft: draft) { reviewedDraft in
        self.draft = nil
        Task { await review(reviewedDraft) }
      }
    }
    .sheet(item: $manualProposal) { proposal in
      NavigationStack {
        Form {
          Section("Manual Training Max") {
            TextField("Kilograms", text: $manualValue)
              .keyboardType(.decimalPad)
          }
        }
        .navigationTitle("Replace \(proposal.liftName)")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { manualProposal = nil }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              guard let value = Double(manualValue) else { return }
              manualProposal = nil
              Task { await decide(proposal, .replace(kg: value)) }
            }
          }
        }
      }
    }
    .sheet(isPresented: $showingExport) {
      TrainingExportView(boundary: model.trainingExportBoundary)
    }
    .fileImporter(
      isPresented: $showingImport,
      allowedContentTypes: [],
      allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result {
        importURL = urls.first.map(ImportURL.init(url:))
      }
    }
    .sheet(item: $importURL) { importURL in
      if let boundary = model.trainingImportBoundary {
        TrainingImportView(boundary: boundary, url: importURL.url)
      }
    }
    .alert("Confirm lift change", isPresented: $showingConfirmation) {
      Button("Cancel", role: .cancel) {
        pendingPreview = nil
      }
      Button("Confirm") {
        guard let pendingPreview else { return }
        Task { await confirm(pendingPreview) }
      }
    } message: {
      if let pendingPreview {
        Text(
          "Save \(pendingPreview.after.identity.displayName) with Training Max \(pendingPreview.after.trainingMaxKg, specifier: "%.2f") kg and Loading Increment \(pendingPreview.after.loadingIncrementKg, specifier: "%.2f") kg?"
        )
      }
    }
    .alert(
      "Could not save lift",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Try again.")
    }
  }

  private func reload() async {
    do {
      rows = try await model.liftConfigurationBoundary.listTMs()
      proposals = try await model.trainingMaxProposalBoundary.proposals()
    } catch {
      errorMessage = String(describing: error)
    }
  }

  private func decide(
    _ proposal: TrainingMaxProposal,
    _ decision: TrainingMaxProposalDecision
  ) async {
    do {
      _ = try await model.trainingMaxProposalBoundary.decide(
        proposalID: proposal.id, decision: decision)
      await reload()
    } catch {
      errorMessage = String(describing: error)
    }
  }

  private func review(_ draft: TMDraft) async {
    do {
      pendingPreview = try await model.liftConfigurationBoundary.preview(draft.request)
      showingConfirmation = true
    } catch {
      errorMessage = String(describing: error)
    }
  }

  private func confirm(_ preview: LiftConfigurationChangePreview) async {
    do {
      _ = try await model.liftConfigurationBoundary.confirm(preview)
      pendingPreview = nil
      await reload()
    } catch {
      pendingPreview = nil
      errorMessage = String(describing: error)
    }
  }
}

private struct TrainingExportView: View {
  @Environment(\.dismiss) private var dismiss
  let boundary: TrainingExportBoundary

  @State private var preview: TrainingExportPreview?
  @State private var artifact: TrainingExportArtifact?
  @State private var includeMirror = false
  @State private var showingWarning = false
  @State private var showingShare = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Group {
        if let artifact {
          List {
            Section("Inspect Archive") {
              Text(artifact.archive.summary.readableText)
                .font(.caption)
                .textSelection(.enabled)
              LabeledContent("SHA-256", value: artifact.archive.integrity.digest)
              LabeledContent("File", value: artifact.url.lastPathComponent)
            }
            Section {
              Button("Share Archive", systemImage: "square.and.arrow.up") {
                showingShare = true
              }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("export.share")
            }
          }
        } else if let preview {
          List {
            Section("Sensitive Data") {
              Text(preview.warning)
                .font(.callout)
              Toggle("Include optional HealthKit Mirror reference", isOn: $includeMirror)
                .onChange(of: includeMirror) { _, _ in
                  Task { await loadPreview() }
                }
            }
            Section("Preview") {
              Text(preview.summary.readableText)
                .font(.caption)
              Button("Create Export") { showingWarning = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("export.create")
            }
          }
        } else {
          ProgressView("Preparing export preview…")
        }
      }
      .navigationTitle("Training Compass Export")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      .task { await loadPreview() }
      .alert("Sensitive fitness data", isPresented: $showingWarning) {
        Button("Cancel", role: .cancel) {}
        Button("Create Unencrypted Archive") {
          guard let preview else { return }
          do {
            artifact = try boundary.create(preview, confirmation: .confirmed)
          } catch {
            errorMessage =
              (error as? TrainingExportError)?.privacySafeDescription
              ?? "The export could not be created."
          }
        }
      } message: {
        Text(preview?.warning ?? "This archive contains sensitive fitness data.")
      }
      .sheet(isPresented: $showingShare) {
        if let artifact {
          TrainingExportShareSheet(url: artifact.url) { outcome in
            do {
              _ = try boundary.completeShare(artifact, outcome: outcome)
              self.artifact = nil
              showingShare = false
            } catch {
              errorMessage =
                (error as? TrainingExportError)?.privacySafeDescription
                ?? "The export could not be shared."
            }
          }
        }
      }
      .alert(
        "Could not export data",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Try again.")
      }
      .onDisappear {
        if let artifact {
          try? boundary.cleanup(artifact)
          self.artifact = nil
        }
      }
    }
  }

  private func loadPreview() async {
    do {
      preview = try await boundary.preview(includeHealthKitMirror: includeMirror)
    } catch {
      errorMessage =
        (error as? TrainingExportError)?.privacySafeDescription
        ?? "The export preview could not be prepared."
    }
  }
}

private struct TrainingImportView: View {
  @Environment(\.dismiss) private var dismiss
  let boundary: TrainingImportBoundary
  let url: URL

  @State private var preview: TrainingImportPreview?
  @State private var errorMessage: String?
  @State private var isImporting = false

  var body: some View {
    NavigationStack {
      Group {
        if let preview {
          List {
            Section("Validated Archive") {
              Text(preview.summary.readableText).font(.caption)
              Text(preview.warning).font(.callout)
            }
            Section("Replace Current Data") {
              Text(preview.replacementWarning).font(.callout)
              Button("Export Current Data First") { dismiss() }
              Button("Replace Current Data", role: .destructive) {
                Task { await importArchive() }
              }
              .disabled(isImporting)
              .accessibilityIdentifier("import.replace")
            }
          }
        } else {
          ProgressView("Validating import…")
        }
      }
      .navigationTitle("Restore Training Compass")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .task {
        do {
          preview = try boundary.preview(at: url)
        } catch {
          errorMessage =
            (error as? TrainingImportError)?.privacySafeDescription
            ?? "The import could not be validated."
        }
      }
      .alert(
        "Could not restore data",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Try again.")
      }
    }
  }

  private func importArchive() async {
    isImporting = true
    defer { isImporting = false }
    do {
      _ = try await boundary.importArchive(at: url, confirmation: .confirmedAfterExport)
      dismiss()
    } catch {
      errorMessage =
        (error as? TrainingImportError)?.privacySafeDescription
        ?? "The import could not be completed."
    }
  }
}

private struct TrainingExportShareSheet: UIViewControllerRepresentable {
  let url: URL
  let completion: (TrainingExportShareOutcome) -> Void

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.completionWithItemsHandler = { activityType, completed, _, _ in
      completion(activityType != nil && completed ? .shared : .cancelled)
    }
    return controller
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct TMRow: View {
  let item: LiftConfigurationListItem
  let onEdit: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.identity.displayName)
          .font(.headline)
        if let configuration = item.configuration {
          Text(
            "TM \(configuration.trainingMaxKg, specifier: "%.2f") kg · Increment \(configuration.loadingIncrementKg, specifier: "%.2f") kg"
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        } else {
          Text("Not configured")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button(item.configuration == nil ? "Configure" : "Edit", action: onEdit)
        .accessibilityIdentifier("tm.edit.\(item.id)")
    }
  }
}

private struct TMDraft: Identifiable, Sendable {
  enum Kind: String, CaseIterable, Identifiable, Sendable {
    case variant
    case custom

    var id: String { rawValue }
  }

  let id: String
  let existingID: String?
  let progression: ProgressionLift?
  var kind: Kind
  var name: String
  var trainingMax: String
  var loadingIncrement: String
  var isCorrection: Bool

  var identity: LiftIdentity {
    if let progression {
      return .progression(progression)
    }
    switch kind {
    case .variant:
      return .variant(name: name)
    case .custom:
      return .custom(name: name)
    }
  }

  var request: LiftConfigurationRequest {
    LiftConfigurationRequest(
      id: existingID,
      identity: identity,
      trainingMaxKg: Double(trainingMax) ?? 0,
      loadingIncrementKg: Double(loadingIncrement) ?? 0,
      isCorrection: isCorrection
    )
  }

  init(item: LiftConfigurationListItem) {
    id = item.id
    existingID = item.configuration?.id
    progression = item.identity.progressionLift
    kind = item.identity.kind == .variant ? .variant : .custom
    name = item.identity.displayName
    trainingMax = item.configuration.map { String($0.trainingMaxKg) } ?? ""
    loadingIncrement = item.configuration.map { String($0.loadingIncrementKg) } ?? "2.5"
    isCorrection = false
  }

  private init(
    id: String,
    existingID: String?,
    progression: ProgressionLift?,
    kind: Kind,
    name: String,
    trainingMax: String,
    loadingIncrement: String,
    isCorrection: Bool
  ) {
    self.id = id
    self.existingID = existingID
    self.progression = progression
    self.kind = kind
    self.name = name
    self.trainingMax = trainingMax
    self.loadingIncrement = loadingIncrement
    self.isCorrection = isCorrection
  }

  static func newCustom() -> TMDraft {
    TMDraft(
      id: "new-custom",
      existingID: nil,
      progression: nil,
      kind: .custom,
      name: "",
      trainingMax: "",
      loadingIncrement: "2.5",
      isCorrection: false
    )
  }

  static func newVariant() -> TMDraft {
    TMDraft(
      id: "new-variant",
      existingID: nil,
      progression: nil,
      kind: .variant,
      name: "",
      trainingMax: "",
      loadingIncrement: "2.5",
      isCorrection: false
    )
  }
}

private struct LiftEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: TMDraft
  let onReview: (TMDraft) -> Void

  init(draft: TMDraft, onReview: @escaping (TMDraft) -> Void) {
    _draft = State(initialValue: draft)
    self.onReview = onReview
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Lift") {
          if let progression = draft.progression {
            LabeledContent("Progression Lift", value: progression.displayName)
          } else {
            Picker("Identity", selection: $draft.kind) {
              ForEach(TMDraft.Kind.allCases) { kind in
                Text(kind.rawValue.capitalized).tag(kind)
              }
            }
            TextField("Lift name", text: $draft.name)
              .textInputAutocapitalization(.words)
          }
        }
        Section("Kilograms") {
          TextField("Training Max", text: $draft.trainingMax)
            .keyboardType(.decimalPad)
            .accessibilityIdentifier("tm.training-max")
          TextField("Loading Increment", text: $draft.loadingIncrement)
            .keyboardType(.decimalPad)
            .accessibilityIdentifier("tm.loading-increment")
          Text(
            "Training Max is a calculation reference and does not need to align to the Loading Increment."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        if draft.existingID != nil {
          Toggle("This is a corrective edit", isOn: $draft.isCorrection)
        }
      }
      .navigationTitle(draft.existingID == nil ? "Configure Lift" : "Edit Lift")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Review") {
            onReview(draft)
          }
          .accessibilityIdentifier("tm.review")
        }
      }
    }
  }
}

private struct PrivacyShield: View {
  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      VStack(spacing: 16) {
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 48))
        Text("Training Compass")
          .font(.title2.bold())
        Text("Private content concealed")
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("privacy.shield")
  }
}
