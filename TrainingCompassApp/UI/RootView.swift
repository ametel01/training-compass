import SwiftUI
import TrainingApplication
import UIKit

struct RootView: View {
  let model: AppModel
  let concealsSensitiveContent: Bool
  @Environment(\.scenePhase) private var scenePhase

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

        NavigationStack {
          HealthView(model: model)
        }
        .tabItem { Label("Health", systemImage: "heart.text.square") }
        .accessibilityIdentifier("tab.health")
      }
      .privacySensitive()
      .task { await model.prepare() }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task {
          _ = try? await model.healthWorkoutImportBoundary?.refreshHealthData(
            trigger: .foreground)
        }
      }

      if concealsSensitiveContent {
        PrivacyShield()
          .transition(.opacity)
          .zIndex(1)
      }
    }
  }
}

private struct HealthView: View {
  let model: AppModel
  @Environment(\.scenePhase) private var scenePhase

  @State private var authorization = HealthAuthorizationSnapshot(state: .notRequested)
  @State private var healthStatus = HealthDataStatus()
  @State private var healthHistory = HealthWorkoutHistorySnapshot(state: .loading)
  @State private var isConnecting = false
  @State private var isImporting = false
  @State private var errorMessage: String?

  var body: some View {
    List {
      Section("Health Data Status") {
        HealthStatusSection(
          status: healthStatus,
          isRefreshing: isImporting,
          canRefresh: model.healthWorkoutImportBoundary != nil,
          onRefresh: { Task { await refreshHealthData() } }
        )
      }

      Section("Connect Health") {
        Text(
          "Training Compass can read Health Workouts and selected recovery evidence from Apple Health. Local planning, logging, history, export, import, and restoration remain available without access."
        )
        .font(.subheadline)
        if authorization.state == .notRequested || authorization.state == .postponed {
          Text(
            "Requested read types: \(HealthAuthorizationRequest.core.readTypes.map(\.displayName).joined(separator: ", ")). Write-back is off."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Button(isConnecting ? "Connecting…" : "Connect Health") {
            Task { await connect() }
          }
          .disabled(isConnecting || model.healthWorkoutImportBoundary == nil)
          .accessibilityIdentifier("health.connect")
          Button("Not now") {
            Task { await model.healthWorkoutImportBoundary?.postponeHealth() }
            authorization = .init(state: .postponed)
            Task { await model.healthDataRebuildBoundary?.setAuthorization(authorization) }
          }
          .disabled(isConnecting)
          .accessibilityIdentifier("health.postpone")
        } else if authorization.state == .authorized {
          Label("Health access connected", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
          if authorization.hasLimitedHistory {
            Text(
              "Health reports that only limited recent history is available. Training Compass will show that coverage context and keep local training usable."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          Text("Use Refresh Health Data above to reconcile every requested stream.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Health data is unavailable on this device. Local training remains fully available.")
            .foregroundStyle(.secondary)
        }
      }

      Section("Deep repair") {
        NavigationLink {
          HealthDataRebuildView(model: model)
        } label: {
          Label("Rebuild Health Data", systemImage: "arrow.triangle.2.circlepath")
        }
        .accessibilityIdentifier("health.rebuild")
      }

      Section("Health Workouts") {
        if healthHistory.state != .available {
          Label(healthHistory.state.displayName, systemImage: healthHistoryStateIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(
              healthHistory.state == .delayedUpdate ? Color.orange : Color.secondary
            )
            .accessibilityIdentifier("health.workouts.state")
        }
        if isImporting {
          ProgressView("Importing the first durable batch…")
          Button("Continue in background") {
            isImporting = false
          }
          .accessibilityIdentifier("health.dismiss-progress")
        } else if healthHistory.events.isEmpty {
          ContentUnavailableView(
            "No Health data is currently available",
            systemImage: "heart.slash",
            description: Text(healthHistoryDescription)
          )
          Button("Check Health access") {
            Task { await connect() }
          }
          .accessibilityIdentifier("health.check-access")
          Button("Refresh Health Workouts") {
            Task { await importWorkouts() }
          }
          .disabled(isImporting)
          .accessibilityIdentifier("health.refresh-empty")
        } else {
          ForEach(healthHistory.events) { entry in
            NavigationLink {
              HealthWorkoutHistoryDetailView(entry: entry, model: model)
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                HStack {
                  Text(entry.event.activityType).font(.headline)
                  Spacer()
                  Text(entry.event.sourceBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                }
                Text("\(entry.event.localDate) · \(Int(entry.event.duration / 60)) min")
                  .font(.subheadline)
                Text("Health Workout · \(entry.provenance.displayName)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(entry.provenance.detailLabel)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text(
                  "Heart rate: \(entry.enrichment.heartRate.state.displayName) · Distance: \(entry.enrichment.distance.state.displayName) · Active energy: \(entry.enrichment.activeEnergy.state.displayName)"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let context = entry.event.reconciliationContext {
                  Text("Last reconciliation: \(context)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .accessibilityIdentifier("health.workout.\(entry.id)")
          }
        }
      }
    }
    .navigationTitle("Health Data Status")
    .accessibilityIdentifier("health.destination")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Refresh Health Data") {
          Task { await refreshHealthData() }
        }
        .disabled(isImporting || model.healthWorkoutImportBoundary == nil)
        .accessibilityIdentifier("health.refresh-data.toolbar")
      }
    }
    .task(id: "\(model.phase)-\(scenePhase)") {
      guard model.phase == .ready, let boundary = model.healthWorkoutImportBoundary else { return }
      authorization = await boundary.authorizationSnapshot()
      await model.healthDataRebuildBoundary?.setAuthorization(authorization)
      healthStatus = await boundary.healthDataStatus()
      healthHistory =
        (try? await boundary.healthWorkoutHistory())
        ?? HealthWorkoutHistorySnapshot(state: .unavailable)
      if scenePhase == .active, authorization.state == .authorized {
        try? await boundary.registerHealthObserver()
        await refreshHealthData()
      }
    }
    .alert(
      "Health connection unavailable",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Try again later.")
    }
  }

  private func connect() async {
    guard let boundary = model.healthWorkoutImportBoundary else { return }
    isConnecting = true
    defer { isConnecting = false }
    do {
      authorization = try await boundary.connectHealth()
      await model.healthDataRebuildBoundary?.setAuthorization(authorization)
      healthStatus = await boundary.healthDataStatus()
      if authorization.state == .authorized {
        try? await boundary.registerHealthObserver()
        await importWorkouts()
      }
    } catch {
      errorMessage =
        "Health did not complete the connection request. Local training is still available."
    }
  }

  private func importWorkouts() async {
    guard let boundary = model.healthWorkoutImportBoundary else { return }
    guard !isImporting else { return }
    isImporting = true
    Task {
      do {
        let result = try await boundary.importWorkouts { update in
          let cached =
            (try? await boundary.healthWorkoutHistory())
            ?? HealthWorkoutHistorySnapshot(state: .loading)
          await MainActor.run {
            healthHistory = cached
            if update.state == .limitedHistory {
              authorization = HealthAuthorizationSnapshot(
                state: .authorized, requested: .core, hasLimitedHistory: true)
            }
          }
        }
        authorization = await boundary.authorizationSnapshot()
        await model.healthDataRebuildBoundary?.setAuthorization(authorization)
        healthStatus = await boundary.healthDataStatus()
        healthHistory = try await boundary.healthWorkoutHistory()
        if result.state == .successfulEmpty {
          healthHistory = HealthWorkoutHistorySnapshot(state: .successfulEmpty)
        }
        isImporting = false
      } catch {
        isImporting = false
        errorMessage =
          "Health data could not be refreshed. Cached local training remains available."
      }
    }
  }

  private func refreshHealthData() async {
    guard let boundary = model.healthWorkoutImportBoundary else { return }
    guard !isImporting else { return }
    isImporting = true
    healthStatus = HealthDataStatus(
      authorization: healthStatus.authorization,
      streams: healthStatus.streams.map { stream in
        HealthStreamStatus(
          stream: stream.stream,
          requested: stream.requested,
          authorization: stream.authorization,
          coverage: stream.coverage,
          mirroredContent: stream.mirroredContent,
          reconciliation: .updating,
          lastSuccessfulCheck: stream.lastSuccessfulCheck,
          failure: stream.failure,
          attemptCount: stream.attemptCount + 1
        )
      }
    )
    do {
      _ = try await boundary.refreshHealthData(trigger: .manualInvalidation)
      authorization = await boundary.authorizationSnapshot()
      healthStatus = await boundary.healthDataStatus()
      healthHistory = (try? await boundary.healthWorkoutHistory()) ?? healthHistory
    } catch {
      healthStatus = await boundary.healthDataStatus()
      errorMessage =
        "Health data could not be refreshed. Cached Health content and local training remain available."
    }
    isImporting = false
  }

  private var healthHistoryDescription: String {
    switch healthHistory.state {
    case .firstFailure:
      "The first Health check failed. Local training remains available; try Refresh Health Data."
    case .delayedUpdate:
      "Health has not refreshed successfully yet. Cached local views remain available."
    case .limitedHistory:
      "Health reports limited recent history. Refresh to check for more available data."
    case .unavailableProvenance:
      "Health data is available, but its source provenance is unavailable."
    case .unavailable:
      "Health data is unavailable on this device. Local training remains fully available."
    case .deleted:
      "The last Health workout was deleted in Health. Refresh to reconcile current events."
    default:
      "This successful empty result does not reveal whether a read type is denied. Check access in Health settings, then refresh."
    }
  }

  private var healthHistoryStateIcon: String {
    switch healthHistory.state {
    case .loading: "arrow.triangle.2.circlepath"
    case .cached: "internaldrive"
    case .successfulEmpty: "heart.slash"
    case .limitedHistory: "clock"
    case .delayedUpdate: "clock.badge.exclamationmark"
    case .firstFailure: "exclamationmark.triangle"
    case .deleted: "trash"
    case .unavailableProvenance: "questionmark.circle"
    case .unavailable: "heart.slash"
    case .available: "checkmark.circle"
    }
  }
}

private struct HealthStatusRow: View {
  let status: HealthStreamStatus

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(status.stream.displayName).font(.headline)
        Spacer()
        Text(status.statusLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(status.failure == nil ? Color.secondary : Color.orange)
      }
      Text(status.lastCheckedLabel).font(.caption)
      Text("\(status.historyLabel) · \(status.contentLabel)")
        .font(.caption2)
        .foregroundStyle(.secondary)
      if let attention = status.attentionLabel {
        Text(attention).font(.caption2).foregroundStyle(.orange)
      }
    }
    .accessibilityIdentifier("health.status.\(status.stream.rawValue)")
  }
}

private struct HealthStatusSection: View {
  let status: HealthDataStatus
  let isRefreshing: Bool
  let canRefresh: Bool
  let onRefresh: () -> Void

  var body: some View {
    Text(
      "Each requested Health Data Stream reconciles independently. A check describes Health's response and mirror state—not the newest sample and not hidden read permission."
    )
    .font(.subheadline)
    ForEach(status.streams) { stream in
      HealthStatusRow(status: stream)
    }
    Button(isRefreshing ? "Updating Health Data…" : "Refresh Health Data", action: onRefresh)
      .disabled(isRefreshing || !canRefresh)
      .accessibilityIdentifier("health.refresh-data")
    if status.isUpdating {
      ProgressView("Reconciliation is active; cached views remain available.")
        .font(.caption)
    }
  }
}

private struct HealthDataRebuildView: View {
  let model: AppModel

  @State private var state: HealthRebuildState?
  @State private var progress: HealthRebuildProgress?
  @State private var isRebuilding = false
  @State private var showingConfirmation = false
  @State private var errorMessage: String?

  var body: some View {
    List {
      Section("Rebuild Health data") {
        Text(
          "This is a confirmed deep repair. It discards the HealthKit Mirror, derived projections, stream anchors, and reconstructible checkpoints. Locally Authoritative Data—your training, Sessions, results, and audit history—is preserved."
        )
        .font(.subheadline)

        if let progress {
          VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress.fraction)
            Text(progress.message).font(.caption)
            if let stream = progress.stream {
              Text("Area: \(stream.displayName)").font(.caption2).foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("health.rebuild.progress")
        } else if let state, state.phase == .paused || state.phase == .failed {
          Text(
            state.phase == .paused
              ? "A previous rebuild paused safely. Continue to resume from its last committed batch."
              : "The previous rebuild did not complete. Confirm again to retry safely."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Button(isRebuilding ? "Rebuilding Health data…" : "Rebuild Health data") {
          showingConfirmation = true
        }
        .disabled(isRebuilding || model.healthDataRebuildBoundary == nil)
        .accessibilityIdentifier("health.rebuild.confirm")
      }
    }
    .navigationTitle("Health Data Rebuild")
    .confirmationDialog(
      "Rebuild Health data?",
      isPresented: $showingConfirmation,
      titleVisibility: .visible
    ) {
      Button("Rebuild Health data", role: .destructive) {
        Task { await rebuild() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "The HealthKit Mirror, derived projections, anchors, and reconstructible checkpoints will be discarded and regenerated. Locally Authoritative Data will remain."
      )
    }
    .task {
      if let healthBoundary = model.healthWorkoutImportBoundary,
        let rebuildBoundary = model.healthDataRebuildBoundary
      {
        let authorization = await healthBoundary.authorizationSnapshot()
        await rebuildBoundary.setAuthorization(authorization)
      }
      state = await model.healthDataRebuildBoundary?.currentState()
    }
    .alert(
      "Health rebuild unavailable",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Try again later.")
    }
  }

  private func rebuild() async {
    guard let boundary = model.healthDataRebuildBoundary else { return }
    isRebuilding = true
    defer { isRebuilding = false }
    do {
      let result = try await boundary.rebuild(confirmation: .confirmed) { update in
        await MainActor.run { progress = update }
      }
      state = result.state
      progress = nil
    } catch HealthRebuildError.cancelled {
      state = await boundary.currentState()
    } catch HealthRebuildError.insufficientStorage(let required, let available) {
      errorMessage =
        "Not enough staging space is available (requires \(required) bytes, has \(available) bytes)."
    } catch {
      state = await boundary.currentState()
      errorMessage =
        "Health data could not be rebuilt. Local training and authoritative history remain available."
    }
  }
}

private struct StrengthProgressView: View {
  let model: AppModel

  @State private var progress: E1RMProgress?
  @State private var eventTimeline: TrainingEventTimelineSnapshot?
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
          Section {
            NavigationLink {
              HealthView(model: model)
            } label: {
              Label("Health Data Status", systemImage: "heart.text.square")
            }
            .accessibilityIdentifier("progress.health-status")
          }

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

          trainingEventHistorySection

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
        List {
          Section("e1RM Progress") {
            ContentUnavailableView(
              "No Progress Yet",
              systemImage: "chart.line.uptrend.xyaxis",
              description: Text(
                "Complete an eligible normal-week Primary Plus Set to see e1RM progress.")
            )
          }
          trainingEventHistorySection
        }
        .refreshable { await reload() }
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

  @ViewBuilder
  private var trainingEventHistorySection: some View {
    Section("Training Event History") {
      if let eventTimeline {
        if eventTimeline.events.isEmpty {
          Text("No completed Sessions or Health Workouts yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(eventTimeline.events) { event in
            NavigationLink {
              UnifiedTrainingEventDetailView(event: event, model: model)
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                HStack {
                  Text(trainingEventTitle(event)).font(.headline)
                  Spacer()
                  Text(event.sourceBadges.map(\.displayName).joined(separator: " + "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                }
                Text(event.localDate)
                  .font(.caption)
                if event.linkState == .linked {
                  Text("Linked one-to-one · counted once")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                if let context = event.reconciliationContext {
                  Text("Last reconciliation: \(context)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .accessibilityIdentifier("progress.training-event.\(event.id)")
          }
        }
      } else {
        ProgressView("Loading Training Event history…")
      }
    }
  }

  private func trainingEventTitle(_ event: UnifiedTrainingEvent) -> String {
    if event.session != nil, event.healthWorkout != nil { return "Linked Training Event" }
    if event.session != nil { return "5/3/1 Session" }
    return event.healthWorkout?.activityType ?? "Health Workout"
  }

  private func reload() async {
    do {
      progress = try await model.progressBoundary.progress(selectedLiftID: selectedLiftID)
      if selectedLiftID == nil { selectedLiftID = progress?.selectedLiftID }
    } catch {
      progress = nil
      errorMessage = String(describing: error)
    }
    eventTimeline = try? await model.trainingEventLinkBoundary?.timeline()
    if eventTimeline == nil { eventTimeline = TrainingEventTimelineSnapshot(events: []) }
  }
}

private struct UnifiedTrainingEventDetailView: View {
  let event: UnifiedTrainingEvent
  let model: AppModel

  @State private var showingUnlinkConfirmation = false
  @State private var wasUnlinked = false
  @State private var errorMessage: String?

  var body: some View {
    List {
      Section("Training Event") {
        LabeledContent("Link state", value: wasUnlinked ? "Unlinked" : linkStateLabel)
        LabeledContent(
          "Sources",
          value: event.sourceBadges.map(\.displayName).joined(separator: " + ")
        )
        if let link = event.link {
          LabeledContent("Link identity", value: link.id)
          LabeledContent("Session identity", value: link.localEntityID)
          LabeledContent("HealthKit UUID", value: link.healthKitUUID)
          LabeledContent(
            "Write-back",
            value: link.writeBackDisposition
              == .suppressedExternalWorkoutLinkedAtCompletion
              ? "No Training Compass summary created"
              : "Not affected by this link"
          )
          if event.linkState == .linked && link.isActive && !wasUnlinked {
            Button("Unlink Training Event", role: .destructive) {
              showingUnlinkConfirmation = true
            }
            .accessibilityIdentifier("training-event.unlink")
          }
        }
      }

      if let session = event.session {
        Section("5/3/1 Session · Training Compass authoritative") {
          LabeledContent("Status", value: session.session.status.rawValue)
          LabeledContent("Intended date", value: session.session.intendedDate.iso8601String)
          LabeledContent("Primary Lift", value: session.session.primaryLiftID)
          LabeledContent("Assistance Lift", value: session.session.assistanceLiftID)
          LabeledContent("Completed", value: String(session.completion.confirmedAt))
          LabeledContent("Set Results", value: "\(session.results.count)")
          LabeledContent("Omitted Sets", value: "\(session.omissions.count)")
          LabeledContent("Additional Sets", value: "\(session.additionalSets.count)")
        }
      }

      if let workout = event.healthWorkout {
        let provenance = HealthWorkoutProvenance(workout: workout)
        Section("Health Workout · HealthKit authoritative") {
          LabeledContent("Activity", value: workout.activityType)
          LabeledContent("Health date", value: workout.localDate)
          LabeledContent("Start", value: workout.startDate.formatted())
          LabeledContent("End", value: workout.endDate.formatted())
          LabeledContent("Duration", value: "\(Int(workout.duration / 60)) min")
          LabeledContent("HealthKit UUID", value: workout.healthKitUUID)
        }
        Section("Available Health Provenance") {
          LabeledContent("Source", value: provenance.displayName)
          LabeledContent("Details", value: provenance.detailLabel)
          LabeledContent("Timezone", value: workout.timeZoneSource.displayName)
          LabeledContent("Coverage", value: event.healthCoverage?.displayName ?? "Unknown")
        }
        if let enrichment = event.healthWorkoutEnrichment {
          HealthWorkoutEnrichmentView(enrichment: enrichment)
        }
        HealthWorkoutRouteView(healthKitUUID: workout.healthKitUUID, model: model)
      } else if event.link != nil {
        Section("Health Workout") {
          Text("The exact linked HealthKit UUID is not currently available in the mirror.")
            .foregroundStyle(.secondary)
        }
      }

      Section("Disagreements") {
        if event.disagreements.isEmpty {
          Text("No disagreement is available for comparable source-owned facts.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(event.disagreements.enumerated()), id: \.offset) { _, disagreement in
            Text(disagreement.message)
          }
        }
        Text("Neither source is silently overwritten.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Reconciliation") {
        if let context = event.reconciliationContext {
          LabeledContent("Context", value: context)
        } else {
          LabeledContent("Context", value: "Unavailable")
        }
        if let date = event.lastSuccessfulReconciliation {
          LabeledContent("Last successful check", value: date.formatted())
        } else {
          LabeledContent("Last successful check", value: "Unavailable")
        }
      }
    }
    .navigationTitle("Training Event")
    .accessibilityIdentifier("training-event.detail")
    .confirmationDialog(
      "Unlink this Training Event?",
      isPresented: $showingUnlinkConfirmation,
      titleVisibility: .visible
    ) {
      Button("Confirm Unlink", role: .destructive) { Task { await unlink() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "The Session and external Health Workout will appear as two Training Events. Neither record is deleted."
      )
    }
    .alert(
      "Could not update Training Event",
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

  private var linkStateLabel: String {
    switch event.linkState {
    case .unlinked: "Unlinked"
    case .linked: "Linked one-to-one"
    case .formerLinkWorkoutUnavailable: "Former link · Health Workout currently unavailable"
    }
  }

  private func unlink() async {
    guard let link = event.link, let boundary = model.trainingEventLinkBoundary else { return }
    do {
      _ = try await boundary.unlink(link, confirmation: .confirmed)
      wasUnlinked = true
    } catch {
      errorMessage = "The link changed before confirmation. Reload and try again."
    }
  }
}

private struct HealthWorkoutHistoryDetailView: View {
  let entry: HealthWorkoutHistoryEntry
  let model: AppModel

  var body: some View {
    List {
      Section("Health Workout") {
        LabeledContent("Activity", value: entry.event.activityType)
        LabeledContent("Source", value: entry.provenance.displayName)
        LabeledContent("Source badge", value: entry.event.sourceBadge)
        LabeledContent("Date", value: entry.event.localDate)
        LabeledContent("Duration", value: "\(Int(entry.event.duration / 60)) min")
        LabeledContent("HealthKit UUID", value: entry.event.healthKitUUID)
      }
      Section("Available Provenance") {
        LabeledContent("Details", value: entry.provenance.detailLabel)
        LabeledContent("Timezone", value: entry.event.timeZoneSource.displayName)
        if let timezone = entry.event.sourceTimeZoneIdentifier {
          LabeledContent("Timezone identifier", value: timezone)
        }
        LabeledContent("Coverage", value: entry.event.healthCoverage.displayName)
      }
      HealthWorkoutEnrichmentView(enrichment: entry.enrichment)
      HealthWorkoutRouteView(healthKitUUID: entry.event.healthKitUUID, model: model)
      Section("Reconciliation") {
        LabeledContent("State", value: entry.state.displayName)
        if let context = entry.event.reconciliationContext {
          LabeledContent("Context", value: context)
        }
        if let date = entry.event.lastSuccessfulReconciliation {
          LabeledContent(
            "Last successful check", value: date.formatted(date: .abbreviated, time: .shortened))
        }
      }
    }
    .navigationTitle("Health Workout")
  }
}

private struct HealthWorkoutRouteView: View {
  let healthKitUUID: String
  let model: AppModel

  @State private var snapshot = HealthWorkoutRouteSnapshot.loading

  var body: some View {
    Section("Workout Route") {
      switch snapshot.state {
      case .loading:
        ProgressView("Loading route from Health…")
          .accessibilityIdentifier("health.route.loading")
        Button("Cancel Route") {
          Task { await model.healthWorkoutRouteBoundary?.cancelRoute(for: healthKitUUID) }
        }
        .accessibilityIdentifier("health.route.cancel")
      case .unavailable:
        Label("No route is currently available from Health.", systemImage: "map")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("health.route.unavailable")
        retryButton
      case .failed:
        Label(
          "Route loading failed. No partial route was retained.",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("health.route.failed")
        retryButton
      case .cancelled:
        Label("Route loading was cancelled.", systemImage: "xmark.circle")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("health.route.cancelled")
        retryButton
      case .ready:
        if let route = snapshot.route {
          HealthWorkoutRoutePlot(segments: route.segments)
            .frame(minHeight: 260)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityIdentifier("health.route.ready")
          LabeledContent(
            "Retained points", value: "\(route.points.count) of \(route.originalPointCount)")
          LabeledContent(
            "Source",
            value: route.sources.map(\.provenance.displayName).joined(separator: ", "))
          if let duration = snapshot.appProcessingDurationMilliseconds {
            LabeledContent("App processing", value: "\(Int(duration.rounded())) ms")
          }
          Text("Only simplified, reconstructible geometry is retained locally.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .task { await load() }
    .onDisappear {
      Task { await model.healthWorkoutRouteBoundary?.cancelRoute(for: healthKitUUID) }
    }
  }

  private var retryButton: some View {
    Button("Retry Route") { Task { await load() } }
      .accessibilityIdentifier("health.route.retry")
  }

  private func load() async {
    guard let boundary = model.healthWorkoutRouteBoundary else {
      snapshot = .unavailable
      return
    }
    snapshot = .loading
    snapshot = await boundary.openRoute(for: healthKitUUID)
  }
}

private struct HealthWorkoutRoutePlot: View {
  let segments: [HealthWorkoutRouteSegment]

  var body: some View {
    Canvas { context, size in
      let points = segments.flatMap(\.points)
      guard let first = points.first else { return }
      let northValues = points.map(\.northSouthDegrees)
      let eastValues = points.map(\.eastWestDegrees)
      let minimumNorth = northValues.min() ?? first.northSouthDegrees
      let maximumNorth = northValues.max() ?? first.northSouthDegrees
      let minimumEast = eastValues.min() ?? first.eastWestDegrees
      let maximumEast = eastValues.max() ?? first.eastWestDegrees
      let northSpan = max(maximumNorth - minimumNorth, .leastNonzeroMagnitude)
      let averageNorth = (minimumNorth + maximumNorth) / 2
      let eastScale = cos(averageNorth * .pi / 180)
      let eastSpan = max(
        (maximumEast - minimumEast) * eastScale, .leastNonzeroMagnitude)
      let inset: CGFloat = 16
      let drawingWidth = max(1, size.width - inset * 2)
      let drawingHeight = max(1, size.height - inset * 2)
      let drawingScale = min(
        drawingWidth / CGFloat(eastSpan),
        drawingHeight / CGFloat(northSpan))
      let horizontalOffset = inset + (drawingWidth - CGFloat(eastSpan) * drawingScale) / 2
      let verticalOffset = inset + (drawingHeight - CGFloat(northSpan) * drawingScale) / 2
      func displayPoint(_ point: HealthWorkoutRoutePoint) -> CGPoint {
        CGPoint(
          x: horizontalOffset
            + CGFloat((point.eastWestDegrees - minimumEast) * eastScale) * drawingScale,
          y: verticalOffset
            + CGFloat(maximumNorth - point.northSouthDegrees) * drawingScale
        )
      }
      for segment in segments {
        guard let segmentFirst = segment.points.first else { continue }
        var path = Path()
        path.move(to: displayPoint(segmentFirst))
        for point in segment.points.dropFirst() { path.addLine(to: displayPoint(point)) }
        context.stroke(path, with: .color(.blue), style: .init(lineWidth: 4, lineCap: .round))
      }
    }
    .background(.quaternary)
    .accessibilityLabel("Simplified workout route")
  }
}

private struct HealthWorkoutEnrichmentView: View {
  let enrichment: HealthWorkoutEnrichment

  var body: some View {
    Section("Workout Enrichment") {
      LabeledContent("Heart rate", value: heartRateValue)
      if enrichment.heartRate.state == .available {
        Text(
          "Only source-observed sample intervals are retained; gaps and workout edges are not inferred."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      enrichmentContext(
        lastSuccessfulCheck: enrichment.heartRate.lastSuccessfulCheck,
        reconciliationContext: enrichment.heartRate.reconciliationContext,
        label: "Heart rate"
      )

      LabeledContent("Distance", value: quantityValue(enrichment.distance))
      enrichmentContext(
        lastSuccessfulCheck: enrichment.distance.lastSuccessfulCheck,
        reconciliationContext: enrichment.distance.reconciliationContext,
        label: "Distance"
      )

      LabeledContent("Active energy", value: quantityValue(enrichment.activeEnergy))
      enrichmentContext(
        lastSuccessfulCheck: enrichment.activeEnergy.lastSuccessfulCheck,
        reconciliationContext: enrichment.activeEnergy.reconciliationContext,
        label: "Active energy"
      )
    }
  }

  private var heartRateValue: String {
    let detail = enrichment.heartRate
    guard !detail.samples.isEmpty else { return detail.state.displayName }
    let cached = detail.state == .failed ? "Update failed · cached " : ""
    return
      "\(cached)\(detail.samples.count) observed interval\(detail.samples.count == 1 ? "" : "s")"
  }

  private func quantityValue(_ detail: HealthWorkoutQuantityDetail) -> String {
    guard let quantity = detail.quantity else { return detail.state.displayName }
    let formatted: String
    switch quantity.unit {
    case .meters:
      formatted = String(format: "%.2f km", quantity.value / 1_000)
    case .kilocalories:
      formatted = String(format: "%.0f kcal", quantity.value)
    }
    return detail.state == .failed ? "Update failed · cached \(formatted)" : formatted
  }

  @ViewBuilder
  private func enrichmentContext(
    lastSuccessfulCheck: Date?,
    reconciliationContext: String?,
    label: String
  ) -> some View {
    if let lastSuccessfulCheck {
      Text(
        "\(label) last successful check: \(lastSuccessfulCheck.formatted(date: .abbreviated, time: .shortened))"
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    if let reconciliationContext {
      Text("\(label) reconciliation: \(reconciliationContext)")
        .font(.caption2)
        .foregroundStyle(.secondary)
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
  @State private var todayEvents: [UnifiedTrainingEvent] = []
  @State private var linkingSnapshot: TrainingEventLinkingSnapshot?
  @State private var selectedCompletionCandidateID: String?
  @State private var pendingCandidate: TrainingEventLinkCandidate?
  @State private var pendingCandidateLinksDuringCompletion = false
  @State private var showingUnusualMatchConfirmation = false
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
          Section {
            NavigationLink {
              HealthView(model: model)
            } label: {
              Label("Health Data Status", systemImage: "heart.text.square")
            }
            .accessibilityIdentifier("today.health-status")
          }

          Section("Today’s Training Events") {
            if todayEvents.isEmpty {
              Text("No completed Sessions or imported Health Workouts for this local date.")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              ForEach(todayEvents) { event in
                TodayTrainingEventRow(event: event, model: model)
              }
            }
          }

          Section("Scheduled Session") {
            Label("5/3/1 Session", systemImage: "figure.strengthtraining.traditional")
              .font(.headline)
              .foregroundStyle(.tint)
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
            trainingEventLinkControls
          } else if today.state == .readyToComplete {
            completionLinkPicker
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
        List {
          Section("Today’s Training Events") {
            if todayEvents.isEmpty {
              ContentUnavailableView {
                Label("Nothing scheduled today", systemImage: "checkmark.circle")
              } description: {
                Text(
                  "No local Session or imported Health Workout is available for today."
                )
                .multilineTextAlignment(.center)
              }
            } else {
              ForEach(todayEvents) { event in
                TodayTrainingEventRow(event: event, model: model)
              }
            }
          }
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
      Button("Confirm Completion") { Task { await beginCompletion() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Completion records the planned-versus-actual work and every set disposition.")
    }
    .confirmationDialog(
      "Confirm unusual Training Event match?",
      isPresented: $showingUnusualMatchConfirmation,
      titleVisibility: .visible
    ) {
      Button("Confirm Unusual Match") {
        guard let candidate = pendingCandidate else { return }
        Task {
          await performLink(
            candidate,
            duringCompletion: pendingCandidateLinksDuringCompletion,
            confirmation: .confirmedUnusualMatch
          )
        }
      }
      Button("Cancel", role: .cancel) { pendingCandidate = nil }
    } message: {
      Text(
        pendingCandidate?.warnings.map(\.message).joined(separator: " ")
          ?? "Review both sources before linking.")
    }
  }

  @ViewBuilder
  private var trainingEventLinkControls: some View {
    if let activeLink = linkingSnapshot?.activeLink {
      Section("Training Event Link") {
        Label("Linked one-to-one", systemImage: "link")
          .foregroundStyle(.tint)
        LabeledContent("HealthKit UUID", value: activeLink.healthKitUUID)
        Text("Open the linked Training Event above to inspect both sources or unlink it.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } else if let candidates = linkingSnapshot?.candidates, !candidates.isEmpty {
      Section("Link External Health Workout") {
        Text(
          "Choose explicitly. Ranking is advisory and Training Compass never links automatically."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        ForEach(candidates) { candidate in
          Button {
            startLink(candidate, duringCompletion: false)
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              Text(candidate.workout.activityType)
              Text(candidateLabel(candidate))
                .font(.caption)
                .foregroundStyle(.secondary)
              if candidate.requiresWarningAcknowledgement {
                Label(
                  "Unusual match · confirmation required", systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
              }
            }
          }
          .accessibilityIdentifier("training-event.candidate.\(candidate.id)")
        }
      }
    }
  }

  @ViewBuilder
  private var completionLinkPicker: some View {
    if let candidates = linkingSnapshot?.candidates, !candidates.isEmpty {
      Section("External Health Workout (Optional)") {
        Picker("Link when completing", selection: $selectedCompletionCandidateID) {
          Text("Do not link").tag(Optional<String>.none)
          ForEach(candidates) { candidate in
            Text(
              "\(candidate.workout.activityType) · \(candidate.workout.localDate)\(candidate.requiresWarningAcknowledgement ? " · Warning" : "")"
            )
            .tag(Optional(candidate.id))
          }
        }
        .accessibilityIdentifier("training-event.completion-candidate")
        Text(
          "Every currently unlinked external workout remains selectable; no candidate is preselected."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private func candidateLabel(_ candidate: TrainingEventLinkCandidate) -> String {
    let minutes = Int(candidate.timingDifference / 60)
    return
      "\(candidate.workout.localDate) · \(Int(candidate.workout.duration / 60)) min · \(minutes) min from completion"
  }

  private func startLink(
    _ candidate: TrainingEventLinkCandidate,
    duringCompletion: Bool
  ) {
    if candidate.requiresWarningAcknowledgement {
      pendingCandidate = candidate
      pendingCandidateLinksDuringCompletion = duringCompletion
      showingUnusualMatchConfirmation = true
    } else {
      Task {
        await performLink(
          candidate,
          duringCompletion: duringCompletion,
          confirmation: .confirmed
        )
      }
    }
  }

  private func beginCompletion() async {
    guard let candidateID = selectedCompletionCandidateID,
      let candidate = linkingSnapshot?.candidates.first(where: { $0.id == candidateID })
    else {
      await completeWithoutLink()
      return
    }
    startLink(candidate, duringCompletion: true)
  }

  private func performLink(
    _ candidate: TrainingEventLinkCandidate,
    duringCompletion: Bool,
    confirmation: TrainingEventLinkConfirmation
  ) async {
    guard let boundary = model.trainingEventLinkBoundary,
      let sessionID = today?.session.id
    else { return }
    do {
      if duringCompletion {
        _ = try await boundary.completeSession(
          linking: candidate,
          to: sessionID,
          confirmation: confirmation
        )
      } else {
        _ = try await boundary.confirmLink(
          candidate,
          to: sessionID,
          confirmation: confirmation
        )
      }
      pendingCandidate = nil
      selectedCompletionCandidateID = nil
      await reload()
    } catch TrainingEventLinkError.staleCandidate {
      errorMessage = "The Session or Health Workout changed. Review the candidates again."
      await reload()
    } catch {
      errorMessage = "The Training Event link could not be saved."
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
      let date = today?.intendedDate ?? TrainingDate(date: Date())
      todayEvents =
        (try? await model.trainingEventLinkBoundary?.timeline(on: date).events) ?? []
      if let today, let boundary = model.trainingEventLinkBoundary {
        if today.state == .completed {
          linkingSnapshot = try? await boundary.linkingSnapshot(for: today.session.id)
        } else if today.state == .readyToComplete {
          linkingSnapshot = try? await boundary.completionLinkingSnapshot(for: today.session.id)
        } else {
          linkingSnapshot = nil
        }
      } else {
        linkingSnapshot = nil
      }
    } catch {
      today = nil
      todayEvents = []
      linkingSnapshot = nil
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

  private func completeWithoutLink() async {
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

private struct TodayTrainingEventRow: View {
  let event: UnifiedTrainingEvent
  let model: AppModel

  var body: some View {
    NavigationLink {
      UnifiedTrainingEventDetailView(event: event, model: model)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Label(title, systemImage: icon)
            .font(.headline)
          Spacer()
          Text(event.sourceBadges.map(\.displayName).joined(separator: " + "))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
        }
        if let workout = event.healthWorkout {
          Text(workout.activityType).font(.subheadline)
          Text("\(workout.localDate) · \(Int(workout.duration / 60)) min")
            .font(.caption)
        } else if let session = event.session {
          Text(session.session.intendedDate.iso8601String).font(.caption)
        }
        if event.linkState == .linked {
          Text("Linked one-to-one · counted once")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityIdentifier("today.training-event.\(event.id)")
  }

  private var title: String {
    if event.session != nil, event.healthWorkout != nil { return "Linked Training Event" }
    if event.session != nil { return "5/3/1 Session" }
    return "Health Workout"
  }

  private var icon: String {
    event.session != nil && event.healthWorkout != nil
      ? "link"
      : (event.session != nil ? "figure.strengthtraining.traditional" : "heart.text.square")
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
  @State private var showingErasure = false
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
          NavigationLink {
            HealthView(model: model)
          } label: {
            Label("Health Data Status", systemImage: "heart.text.square")
          }
          NavigationLink {
            SettingsView(model: model)
          } label: {
            Label("Settings", systemImage: "gearshape")
          }
          .accessibilityIdentifier("tm.settings")
          Button("Export", systemImage: "square.and.arrow.up") {
            showingExport = true
          }
          if model.trainingImportBoundary != nil {
            Button("Restore Export", systemImage: "arrow.down.doc") {
              showingImport = true
            }
            .accessibilityIdentifier("tm.import")
          }
          if model.trainingErasureBoundary != nil {
            Divider()
            Button(TrainingErasureCopy.title, systemImage: "trash", role: .destructive) {
              showingErasure = true
            }
            .accessibilityIdentifier("tm.erase-all")
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
    .sheet(isPresented: $showingErasure) {
      TrainingErasureView(model: model)
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

private struct SettingsView: View {
  let model: AppModel

  var body: some View {
    List {
      Section("Health") {
        NavigationLink {
          HealthView(model: model)
        } label: {
          Label("Health Data Status", systemImage: "heart.text.square")
        }
        .accessibilityIdentifier("settings.health-status")
        NavigationLink {
          HealthDataRebuildView(model: model)
        } label: {
          Label("Rebuild Health Data", systemImage: "arrow.triangle.2.circlepath")
        }
        .accessibilityIdentifier("settings.health-rebuild")
      }
    }
    .navigationTitle("Settings")
    .accessibilityIdentifier("settings.destination")
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

private struct TrainingErasureView: View {
  @Environment(\.dismiss) private var dismiss
  let model: AppModel

  @State private var showingConfirmation = false
  @State private var isErasing = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        Section("Erase this installation") {
          Text(TrainingErasureCopy.confirmationMessage)
            .font(.callout)
          Text(TrainingErasureCopy.externalCopiesMessage)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Section {
          Button(TrainingErasureCopy.title, role: .destructive) {
            showingConfirmation = true
          }
          .disabled(isErasing)
          .accessibilityIdentifier("erase.confirm")
        }
      }
      .privacySensitive()
      .navigationTitle(TrainingErasureCopy.title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .alert(TrainingErasureCopy.title, isPresented: $showingConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Erase Everything", role: .destructive) {
          Task { await erase() }
        }
        .accessibilityIdentifier("erase.confirmation")
      } message: {
        Text(
          TrainingErasureCopy.confirmationMessage + "\n\n"
            + TrainingErasureCopy.externalCopiesMessage
        )
      }
      .alert(
        "Could not erase app data",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? TrainingErasureError.cleanupFailed.privacySafeDescription)
      }
    }
  }

  private func erase() async {
    isErasing = true
    defer { isErasing = false }
    do {
      try await model.eraseAllData()
      dismiss()
    } catch let error as TrainingErasureError {
      errorMessage = error.privacySafeDescription
    } catch {
      errorMessage = TrainingErasureError.cleanupFailed.privacySafeDescription
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
