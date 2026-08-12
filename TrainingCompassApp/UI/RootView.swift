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
          UnavailableDestinationView(
            title: "Cycle",
            systemImage: "calendar",
            detail: "Training Cycles become available in Local Training Core."
          )
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
