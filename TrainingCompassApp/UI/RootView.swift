import SwiftUI
import TrainingApplication

struct RootView: View {
  let model: AppModel
  let concealsSensitiveContent: Bool

  var body: some View {
    ZStack {
      TabView {
        NavigationStack {
          TodayPreDataView(phase: model.phase)
        }
        .tabItem { Label("Today", systemImage: "sun.max") }
        .accessibilityIdentifier("tab.today")

        NavigationStack {
          CycleView(model: model)
        }
        .tabItem { Label("Cycle", systemImage: "calendar") }
        .accessibilityIdentifier("tab.cycle")

        NavigationStack {
          UnavailableDestinationView(
            title: "Progress",
            systemImage: "chart.xyaxis.line",
            detail: "Insights remain unavailable until their verified milestones ship."
          )
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

private struct TodayPreDataView: View {
  let phase: AppModel.Phase

  var body: some View {
    ContentUnavailableView {
      Label("Training Compass", systemImage: "location.north.circle.fill")
    } description: {
      VStack(spacing: 12) {
        Text("PRE-DATA BUILD")
          .font(.caption.weight(.bold))
          .foregroundStyle(.orange)
          .accessibilityIdentifier("pre-data.badge")
        Text(
          "Training workflows and Health data remain unavailable. TMs configuration is the only supported owner-data surface in this build."
        )
        .multilineTextAlignment(.center)
        status
      }
    }
    .navigationTitle("Today")
  }

  @ViewBuilder
  private var status: some View {
    switch phase {
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
        .accessibilityIdentifier("pre-data.failed")
    }
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
  @State private var workingSessions: [ScheduleSession] = []
  @State private var lifts: [LiftConfiguration] = []
  @State private var draft: ScheduleSessionDraft?
  @State private var cycleSessionDraft: CycleSessionDraft?
  @State private var pendingSave: ScheduleTemplateChangePreview?
  @State private var pendingReset: ScheduleTemplateChangePreview?
  @State private var pendingCycleChange: TrainingCycleChangePreview?
  @State private var pendingCycleDiscard: TrainingCycleChangePreview?
  @State private var anchorDate = TrainingDate.monday(containing: Date()).date()
  @State private var showingSaveConfirmation = false
  @State private var showingResetConfirmation = false
  @State private var showingCycleConfirmation = false
  @State private var showingCycleDiscardConfirmation = false
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if template == nil {
        UnavailableDestinationView(
          title: "Cycle",
          systemImage: "calendar",
          detail:
            "Configure Squat, Deadlift, Bench Press, Overhead Press, and Romanian Deadlift in TMs to initialize the Schedule Template."
        )
      } else {
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
                onEdit: { cycleSessionDraft = CycleSessionDraft(session: $0, week: $1) }
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
              VStack(alignment: .leading, spacing: 4) {
                Label("Active Training Cycle", systemImage: "play.circle")
                  .font(.headline)
                Text(
                  "\(activeCycle.week1AnchorDate.iso8601String) · "
                    + "\(activeCycle.weeks.count) Training Weeks"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text("An Active Training Cycle remains independent while you prepare this draft.")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
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
        }
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
    } catch {
      template = nil
      draftCycle = nil
      errorMessage = nil
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
    guard let cycle = pendingCycleChange?.after else { return "" }
    let deload: String
    if cycle.includesProvisionalDeload {
      deload = "A provisional Deload Week is included."
    } else {
      deload = "No Deload Week is due yet."
    }
    return "Week 1 begins \(cycle.week1AnchorDate.iso8601String). The draft contains "
      + "\(cycle.weeks.count) fixed Training Weeks. \(deload)"
  }

  private var cycleConfirmationActionTitle: String {
    switch pendingCycleChange?.action {
    case .created: "Create"
    case .edited: "Save Edits"
    case .replacedSchedule: "Replace Schedule"
    case .regenerated: "Regenerate"
    case .discarded, .none: "Confirm"
    }
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

  private func reviewCycleEdit(_ draft: CycleSessionDraft) async {
    guard let cycle = draftCycle,
      let weekIndex = cycle.weeks.firstIndex(where: { $0.id == draft.weekID }),
      let sessionIndex = cycle.weeks[weekIndex].sessions.firstIndex(where: { $0.id == draft.id })
    else { return }
    let old = cycle.weeks[weekIndex].sessions[sessionIndex]
    let replacement = TrainingCycleSession(
      id: old.id,
      intendedDate: TrainingDate(date: draft.intendedDate),
      sourceTemplateSessionID: old.sourceTemplateSessionID,
      primaryLiftID: draft.primaryLiftID,
      assistanceLiftID: draft.assistanceLiftID
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
      pendingCycleChange = try await model.trainingCycleBoundary.previewEdit(request)
      showingCycleConfirmation = true
    } catch { errorMessage = String(describing: error) }
  }

  private func confirmCycleChange(_ preview: TrainingCycleChangePreview) async {
    do {
      _ = try await model.trainingCycleBoundary.confirm(preview)
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

private struct CycleSessionDraft: Identifiable, Sendable {
  let id: String
  let weekID: String
  var intendedDate: Date
  var primaryLiftID: String
  var assistanceLiftID: String

  init(session: TrainingCycleSession, week: TrainingWeek) {
    id = session.id
    weekID = week.id
    intendedDate = session.intendedDate.date()
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
          intendedDate: TrainingDate(date: $0.intendedDate.date()),
          primaryLiftID: $0.primaryLiftID,
          assistanceLiftID: $0.assistanceLiftID
        )
      }
    )
  }
}

private struct TMsView: View {
  let model: AppModel

  @State private var rows: [LiftConfigurationListItem] = LiftCatalog.progressionIdentities.map {
    LiftConfigurationListItem(identity: $0, configuration: nil)
  }
  @State private var draft: TMDraft?
  @State private var pendingPreview: LiftConfigurationChangePreview?
  @State private var showingConfirmation = false
  @State private var errorMessage: String?

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
        Button {
          draft = TMDraft.newCustom()
        } label: {
          Label("Add custom lift", systemImage: "plus")
        }
        .accessibilityIdentifier("tm.add-custom")
        Button {
          draft = TMDraft.newVariant()
        } label: {
          Label("Add variant", systemImage: "plus")
        }
        .accessibilityIdentifier("tm.add-variant")
      }
    }
    .refreshable { await reload() }
    .navigationTitle("TMs")
    .accessibilityIdentifier("tms.destination")
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
