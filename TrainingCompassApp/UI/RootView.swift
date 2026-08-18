import SwiftUI
import TrainingApplication
import UIKit

// DESIGN CONTRACT · seed bdb3937c · operate / user-pinned reference replacement
// THESIS: Training Compass is a compact native training log, matching the approved four-iPhone
//         reference rather than presenting a generic fitness dashboard.
// OWN-WORLD: warm off-white field, crisp white cards, editorial navy serif headings, compact SF data,
//            compass-blue actions, verified green, omission red, and hairline structure.
// STORY: Today records the session; Cycle orients the plan; Progress explains recent evidence;
//        Training Maxes supports review; Health audits the local evidence mirror.
// FIRST VIEWPORT: a left-aligned editorial heading leads directly into one dense reference-shaped
//                 work card, with native actions visible and supporting detail below the fold.
// FORM: exact visual translation of the user-pinned Training Compass four-phone board, seed bdb3937c.
// RAISE — comparison board: each tab reads as one member of the same compact visual system.
// RAISE — native utility: retain Health, accessibility, and state controls while matching the board.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
struct RootView: View {
    private enum AppTab: Hashable {
        case today
        case cycle
        case progress
        case trainingMaxes
        case health
    }

    let model: AppModel
    let concealsSensitiveContent: Bool
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("health.readAccessApproved") private var healthReadAccessApproved = false
    @State private var selectedTab: AppTab = .today

    init(model: AppModel, concealsSensitiveContent: Bool) {
        self.model = model
        self.concealsSensitiveContent = concealsSensitiveContent
        let requestedTab = ProcessInfo.processInfo.environment["TRAINING_COMPASS_INITIAL_TAB"]
        let initialTab: AppTab = switch requestedTab {
        case "cycle": .cycle
        case "progress": .progress
        case "training-maxes": .trainingMaxes
        case "health": .health
        default: .today
        }
        _selectedTab = State(initialValue: initialTab)
        CompassAppearance.apply()
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    TodayView(model: model)
                }
                .tag(AppTab.today)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .accessibilityIdentifier("tab.today")

                NavigationStack {
                    CycleView(model: model) {
                        selectedTab = .trainingMaxes
                    }
                }
                .tag(AppTab.cycle)
                .tabItem { Label("Cycle", systemImage: "calendar") }
                .accessibilityIdentifier("tab.cycle")

                NavigationStack {
                    StrengthProgressView(model: model)
                }
                .tag(AppTab.progress)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .accessibilityIdentifier("tab.progress")

                NavigationStack {
                    TMsView(model: model)
                }
                .tag(AppTab.trainingMaxes)
                .tabItem { Label("TMs", systemImage: "scalemass") }
                .accessibilityIdentifier("tab.tms")

                NavigationStack {
                    HealthView(model: model)
                }
                .tag(AppTab.health)
                .tabItem { Label("Health", systemImage: "heart.text.square") }
                .accessibilityIdentifier("tab.health")
            }
            .tint(CompassPalette.blue)
            .privacySensitive()
            .task {
                await model.prepare()
                await refreshHealthDataIfDue()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await model.prepare()
                    await model.resumeHealthWorkoutWriteBacks()
                    await refreshHealthDataIfDue()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.protectedDataDidBecomeAvailableNotification,
                ),
            ) { _ in
                Task {
                    await model.prepare()
                    await model.resumeHealthWorkoutWriteBacks()
                }
            }

            if concealsSensitiveContent {
                PrivacyShield()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }

    private func refreshHealthDataIfDue() async {
        guard healthReadAccessApproved,
              let boundary = model.healthWorkoutImportBoundary
        else { return }
        await boundary.resumePreviouslyApprovedHealthAccess()
        try? await boundary.registerHealthObserver()
        _ = try? await boundary.refreshHealthDataIfDue()
    }
}

private struct HealthView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("health.readAccessApproved") private var healthReadAccessApproved = false

    @State private var authorization = HealthAuthorizationSnapshot(state: .notRequested)
    @State private var healthStatus = HealthDataStatus()
    @State private var healthHistory = HealthWorkoutHistorySnapshot(state: .loading)
    @State private var isConnecting = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var writeBackPreference = HealthWorkoutWriteBackPreference()
    @State private var writeBackError: String?

    var body: some View {
        List {
            Section {
                healthControlCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .compassScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .compassTopBarTitle("Health")
        .compassNavigationTitle("Health")
        .accessibilityIdentifier("health.destination")
        .task(id: "\(model.phase)-\(scenePhase)") {
            guard model.phase == .ready else { return }
            if let writeBackBoundary = model.healthWorkoutWriteBackBoundary {
                writeBackPreference = await (try? writeBackBoundary.preference()) ?? .init()
            }
            guard let boundary = model.healthWorkoutImportBoundary else { return }
            if healthReadAccessApproved {
                await boundary.resumePreviouslyApprovedHealthAccess()
            }
            authorization = await boundary.authorizationSnapshot()
            await model.healthDataRebuildBoundary?.setAuthorization(authorization)
            await loadHealthState()
            if scenePhase == .active, authorization.state == .authorized {
                try? await boundary.registerHealthObserver()
                if await (try? boundary.refreshHealthDataIfDue()) != nil {
                    await loadHealthState()
                }
            }
        }
        .alert(
            "Health connection unavailable",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again later.")
        }
    }

    private var healthControlCard: some View {
        CompassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    HStack(spacing: 9) {
                        CompassRoundSymbol(
                            systemImage: "heart.fill",
                            color: authorization.state == .authorized
                                ? CompassPalette.green
                                : CompassPalette.blue,
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health")
                                .font(.system(.headline, design: .serif).weight(.bold))
                                .foregroundStyle(CompassPalette.navy)
                            Text(freshnessLabel)
                                .font(.caption2)
                                .foregroundStyle(CompassPalette.inkMuted)
                        }
                    }
                    Spacer()
                    CompassStatusPill(
                        title: authorizationLabel,
                        color: authorization.state == .authorized
                            ? CompassPalette.green
                            : CompassPalette.inkMuted,
                    )
                }

                Text(healthSummary)
                    .font(.subheadline)
                    .foregroundStyle(CompassPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("health.workouts.count")
                    .accessibilityValue("\(healthHistory.events.count)")

                if authorization.state == .authorized {
                    Button {
                        Task { await refreshHealthData() }
                    } label: {
                        Label(
                            isImporting ? "Refreshing Health Data…" : "Refresh Health Data",
                            systemImage: "arrow.clockwise",
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting || model.healthWorkoutImportBoundary == nil)
                    .accessibilityIdentifier("health.refresh-data")

                    Divider()

                    Toggle(
                        "Add completed sessions to Health",
                        isOn: Binding(
                            get: { writeBackPreference.enabled },
                            set: { enabled in Task { await setWriteBackEnabled(enabled) } },
                        ),
                    )
                    .disabled(model.healthWorkoutWriteBackBoundary == nil)
                    .accessibilityIdentifier("health.write-back.enabled")
                    Text("Adds only a strength-workout summary. Sets, loads, notes, and training maxes stay in Training Compass.")
                        .font(.caption2)
                        .foregroundStyle(CompassPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if authorization.state == .unavailable {
                    Label("Apple Health is unavailable on this device.", systemImage: "heart.slash")
                        .font(.subheadline)
                        .foregroundStyle(CompassPalette.inkMuted)
                } else {
                    Button {
                        Task { await connect() }
                    } label: {
                        Label(
                            isConnecting ? "Requesting Health Access…" : "Approve Health Access",
                            systemImage: "checkmark.shield",
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnecting || model.healthWorkoutImportBoundary == nil)
                    .accessibilityIdentifier("health.connect")
                }

                if let writeBackError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(writeBackError)
                            .font(.caption)
                            .foregroundStyle(CompassPalette.red)
                        Button("Check Health Access") {
                            Task { await checkWriteAccess() }
                        }
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("health.write-back.check-access")
                    }
                }
            }
        }
    }

    private var freshnessLabel: String {
        if isImporting {
            return "Refreshing now"
        }
        if healthStatus.hasActionableAttention {
            return "Refresh needs attention"
        }
        if healthStatus.requestedStreams.contains(where: { stream in
            guard let lastSuccessfulCheck = stream.lastSuccessfulCheck else { return false }
            return Calendar.current.isDateInToday(lastSuccessfulCheck)
        }) {
            return "Updated today"
        }
        if let lastCheck = healthStatus.requestedStreams.compactMap(\.lastSuccessfulCheck).max() {
            return "Updated \(lastCheck.formatted(date: .abbreviated, time: .omitted))"
        }
        return authorization.state == .authorized ? "Ready to refresh" : "Approval required"
    }

    private var healthSummary: String {
        guard authorization.state == .authorized else {
            return "Approve read access once. Training Compass will then refresh Health data on the first app open each day."
        }
        let count = healthHistory.events.count
        let workoutCopy = "\(count) workout\(count == 1 ? "" : "s") available."
        if authorization.hasLimitedHistory {
            return "\(workoutCopy) Apple Health is providing limited history. Refresh remains available at any time."
        }
        return "\(workoutCopy) Automatic refresh runs once each day; you can refresh now at any time."
    }

    private var authorizationLabel: String {
        switch authorization.state {
        case .authorized: "Connected"
        case .notRequested: "Not connected"
        case .postponed: "Not now"
        case .unavailable: "Unavailable"
        }
    }

    private func connect() async {
        guard let boundary = model.healthWorkoutImportBoundary else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            authorization = try await boundary.connectHealth()
            healthReadAccessApproved = authorization.state == .authorized
            await model.healthDataRebuildBoundary?.setAuthorization(authorization)
            if authorization.state == .authorized {
                try? await boundary.registerHealthObserver()
                await refreshHealthData()
            } else {
                await loadHealthState()
            }
        } catch {
            errorMessage =
                "Health did not complete the connection request. Local training is still available."
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
                    attemptCount: stream.attemptCount + 1,
                )
            },
        )
        do {
            _ = try await boundary.refreshHealthData(trigger: .manualInvalidation)
            authorization = await boundary.authorizationSnapshot()
            await loadHealthState()
        } catch {
            healthStatus = await boundary.healthDataStatus()
            errorMessage =
                "Health data could not be refreshed. Cached Health content and local training remain available."
        }
        isImporting = false
    }

    private func loadHealthState() async {
        guard let boundary = model.healthWorkoutImportBoundary else { return }
        authorization = await boundary.authorizationSnapshot()
        healthStatus = await boundary.healthDataStatus()
        healthHistory = await (try? boundary.healthWorkoutHistory()) ?? healthHistory
    }

    private func setWriteBackEnabled(_ enabled: Bool) async {
        guard let boundary = model.healthWorkoutWriteBackBoundary else { return }
        do {
            _ = try await boundary.setEnabled(enabled)
            writeBackPreference = try await boundary.preference()
            writeBackError = nil
        } catch {
            writeBackPreference = await (try? boundary.preference()) ?? .init()
            writeBackError =
                "Health write-back permission was not completed. Local training remains available."
        }
    }

    private func checkWriteAccess() async {
        guard let boundary = model.healthWorkoutWriteBackBoundary else { return }
        do {
            _ = try await boundary.checkWriteAccess()
            writeBackError = nil
        } catch {
            writeBackError =
                "Health write access is still unavailable. Choose Try Again on the affected Session after checking Health settings."
        }
    }
}

private struct MaximumHeartRateConfigurationView: View {
    let model: AppModel

    @State private var maximumHeartRateText = ""
    @State private var maximumHeartRate: HeartRateConfiguration?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Maximum heart rate (bpm)", text: $maximumHeartRateText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("health.maximum-heart-rate")
                Button("Save Maximum Heart Rate") {
                    Task { await saveMaximumHeartRate() }
                }
                .disabled(model.heartRateConfigurationBoundary == nil)
                .accessibilityIdentifier("health.maximum-heart-rate.save")
                if let maximumHeartRate {
                    LabeledContent(
                        "Current",
                        value: "\(String(format: "%.1f", maximumHeartRate.maximumHeartRateBPM)) bpm",
                    )
                    Button("Clear Maximum Heart Rate", role: .destructive) {
                        Task { await clearMaximumHeartRate() }
                    }
                    .accessibilityIdentifier("health.maximum-heart-rate.clear")
                }
            } footer: {
                Text("Progress uses this value to calculate time in heart-rate zones.")
            }
        }
        .compassScreen()
        .navigationTitle("Maximum Heart Rate")
        .task {
            maximumHeartRate = try? await model.heartRateConfigurationBoundary?.current()
            if let maximumHeartRate {
                maximumHeartRateText = String(maximumHeartRate.maximumHeartRateBPM)
            }
        }
        .alert("Could not save maximum heart rate", isPresented: Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            },
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    private func saveMaximumHeartRate() async {
        guard let boundary = model.heartRateConfigurationBoundary,
              let value = Double(maximumHeartRateText.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            errorMessage = "Enter a positive maximum heart rate in beats per minute."
            return
        }
        do {
            maximumHeartRate = try await boundary.configure(maximumHeartRateBPM: value)
            model.heartRateConfigurationDidChange()
        } catch {
            errorMessage = "Maximum heart rate must be a finite positive number."
        }
    }

    private func clearMaximumHeartRate() async {
        do {
            try await model.heartRateConfigurationBoundary?.clear()
            maximumHeartRate = nil
            maximumHeartRateText = ""
            model.heartRateConfigurationDidChange()
        } catch {
            errorMessage = "The maximum heart rate could not be cleared."
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
                    "This is a confirmed deep repair. It discards the HealthKit Mirror, derived projections, stream anchors, and reconstructible checkpoints. Locally Authoritative Data—your training, Sessions, results, and audit history—is preserved.",
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
                            : "The previous rebuild did not complete. Confirm again to retry safely.",
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
        .compassScreen()
        .navigationTitle("Health Data Rebuild")
        .confirmationDialog(
            "Rebuild Health data?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Rebuild Health data", role: .destructive) {
                Task { await rebuild() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The HealthKit Mirror, derived projections, anchors, and reconstructible checkpoints will be discarded and regenerated. Locally Authoritative Data will remain.",
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
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again later.")
        }
    }

    private func rebuild() async {
        guard let boundary = model.healthDataRebuildBoundary else { return }
        isRebuilding = true
        progress = nil
        defer { isRebuilding = false }
        do {
            let result = try await boundary.rebuild(confirmation: .confirmed) { update in
                await MainActor.run { progress = update }
            }
            state = result.state
            progress = nil
        } catch HealthRebuildError.cancelled {
            state = await boundary.currentState()
        } catch HealthRebuildError.resourcePressure {
            state = await boundary.currentState()
            progress = HealthRebuildProgress(
                phase: .paused,
                area: .healthMirror,
                message: HealthRebuildError.resourcePressure.privacySafeDescription,
            )
        } catch let HealthRebuildError.insufficientStorage(required, available) {
            errorMessage =
                "Not enough staging space is available (requires \(required) bytes, has \(available) bytes)."
        } catch let error as HealthRebuildError {
            state = await boundary.currentState()
            let stage = progress?.stream.map { " Last stage: \($0.displayName)." } ?? ""
            errorMessage = "\(error.privacySafeDescription)\(stage) Local training remains available."
        } catch {
            state = await boundary.currentState()
            errorMessage =
                "Health data could not be rebuilt. Local training and authoritative history remain available."
        }
    }
}

private struct StrengthProgressView: View {
    let model: AppModel

    @State private var liftSummaries: [LiftE1RMSummary] = []
    @State private var rollingOverview: RollingWorkoutOverview?
    @State private var cardioProgress: CardioProgress?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if model.phase != .ready {
                ContentUnavailableView(
                    "Progress unavailable",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Preparing protected local stores."),
                )
            } else {
                List {
                    e1RMSection
                    heartRateZonesSection
                    cardioEfficiencySection
                    heartRateDriftSection
                }
                .refreshable { await reload() }
            }
        }
        .compassScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .compassTopBarTitle("Progress")
        .compassNavigationTitle("Progress")
        .accessibilityIdentifier("progress.destination")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    HealthView(model: model)
                } label: {
                    Label("Health Data", systemImage: "calendar.badge.clock")
                }
                .accessibilityIdentifier("progress.health-status")
            }
        }
        .task(id: "\(model.phase)-\(model.heartRateConfigurationRevision)") {
            if model.phase == .ready {
                await reload()
            }
        }
        .alert(
            "Could not load Progress",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Pull to refresh and try again.")
        }
    }

    private var e1RMSection: some View {
        progressCard {
            CompassSectionTitle(title: "Are my estimated 1RMs increasing?", trailing: "Trailing 90 days")
            if isLoading, liftSummaries.isEmpty {
                ProgressView("Calculating lift trends…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(Array(liftSummaries.enumerated()), id: \.element.id) { index, lift in
                    if index > 0 {
                        Divider()
                    }
                    HStack(spacing: 12) {
                        CompassRoundSymbol(
                            systemImage: lift.symbol,
                            color: lift.directionColor,
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lift.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CompassPalette.navy)
                            Text(lift.directionText)
                                .font(.caption)
                                .foregroundStyle(lift.directionColor)
                        }
                        Spacer()
                        Text(lift.latestText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(CompassPalette.navy)
                    }
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("progress.e1rm.\(lift.id)")
                }
            }
        }
        .accessibilityIdentifier("progress.e1rm-summary")
    }

    private var heartRateZonesSection: some View {
        progressCard {
            CompassSectionTitle(
                title: "How much training is in each HR zone?",
                trailing: rollingOverview.map(\.currentWindow.displayName),
            )
            Text("Last 7 Days")
                .font(.caption)
                .foregroundStyle(CompassPalette.inkMuted)
                .accessibilityIdentifier("progress.rolling-overview.window")

            if let overview = rollingOverview, !overview.zoneMetrics.isEmpty {
                let metrics = Dictionary(uniqueKeysWithValues: overview.zoneMetrics.map { ($0.zone, $0) })
                ForEach(Array(RollingWorkoutZone.cardioZones.enumerated()), id: \.element) { index, zone in
                    let metric = metrics[zone]
                    if index > 0 {
                        Divider()
                    }
                    HeartRateZoneRow(
                        zone: zone,
                        duration: metric?.coveredSeconds ?? 0,
                        percentage: metric?.percentOfCoveredTime ?? 0,
                        emphasis: Double(index + 1) / 5,
                    )
                }
                if let coverage = overview.zoneMetrics.first?.coverageOfTotalWorkoutDuration {
                    Text("\(coverage.formatted(.number.precision(.fractionLength(0))))% of workout time has measured heart rate.")
                        .font(.caption2)
                        .foregroundStyle(CompassPalette.inkMuted)
                        .padding(.top, 2)
                }
            } else if isLoading {
                ProgressView("Calculating zone time…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if rollingOverview?.maximumHeartRateBPM == nil {
                Text("Set your maximum heart rate to calculate zone time.")
                    .font(.caption)
                    .foregroundStyle(CompassPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                NavigationLink {
                    MaximumHeartRateConfigurationView(model: model)
                } label: {
                    Label("Set maximum heart rate", systemImage: "heart.text.square")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("progress.set-maximum-heart-rate")
            } else {
                Text("No measured workout heart rate is available for this seven-day window.")
                    .font(.caption)
                    .foregroundStyle(CompassPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
        }
        .accessibilityIdentifier("progress.rolling-overview")
    }

    private var cardioEfficiencySection: some View {
        progressCard {
            CompassSectionTitle(title: "Is my cardio efficiency improving?")
            if let efficiency = cardioProgress?.efficiency {
                HStack(alignment: .center, spacing: 14) {
                    CompassRoundSymbol(
                        systemImage: efficiencySymbol(efficiency.direction),
                        color: efficiencyColor(efficiency.direction),
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(efficiency.direction.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(efficiencyColor(efficiency.direction))
                        Text(efficiency.activityType ?? "Distance-based cardio")
                            .font(.caption)
                            .foregroundStyle(CompassPalette.inkMuted)
                    }
                    Spacer()
                    if let change = efficiency.percentChange {
                        Text(change, format: .percent.scale(1).precision(.fractionLength(1)).sign(strategy: .always()))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(efficiencyColor(efficiency.direction))
                    }
                }
                .padding(.vertical, 6)

                Divider()

                if let latest = efficiency.latestMetersPerHeartbeat {
                    HStack {
                        CompassMetricValue(
                            label: "LATEST",
                            value: "\(latest.formatted(.number.precision(.fractionLength(2)))) m/beat",
                        )
                        if let baseline = efficiency.baselineMetersPerHeartbeat {
                            CompassMetricValue(
                                label: "PRIOR \(efficiency.comparisonCount)",
                                value: "\(baseline.formatted(.number.precision(.fractionLength(2)))) m/beat",
                                detail: "same activity median",
                                detailColor: CompassPalette.inkMuted,
                            )
                        }
                    }
                } else {
                    Text("Efficiency needs distance and at least 80% heart-rate coverage.")
                        .font(.caption)
                        .foregroundStyle(CompassPalette.inkMuted)
                }
            } else {
                ProgressView("Calculating cardio efficiency…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .accessibilityIdentifier("progress.cardio-efficiency")
    }

    private var heartRateDriftSection: some View {
        progressCard {
            CompassSectionTitle(title: "How is my heart rate drifting?", trailing: "Last 7 days")
            let drifts = recentDrifts
            if !drifts.isEmpty {
                ForEach(Array(drifts.enumerated()), id: \.element.id) { index, drift in
                    if index > 0 {
                        Divider()
                    }
                    HeartRateDriftRow(drift: drift)
                }
            } else if isLoading {
                ProgressView("Calculating session drift…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Text("No cardio sessions are available in the last 7 days.")
                    .font(.caption)
                    .foregroundStyle(CompassPalette.inkMuted)
                    .padding(.vertical, 12)
            }
            Text("First 10 minutes removed. The remaining elapsed time is split equally; drift = (second-half average − first-half average) ÷ first-half average.")
                .font(.caption2)
                .foregroundStyle(CompassPalette.inkMuted)
                .padding(.top, 4)
        }
        .accessibilityIdentifier("progress.heart-rate-drift")
    }

    private var recentDrifts: [CardioHeartRateDrift] {
        guard let start = rollingOverview?.currentWindow.start else {
            return Array(cardioProgress?.heartRateDrifts.prefix(7) ?? [])
        }
        return cardioProgress?.heartRateDrifts.filter { $0.localDate >= start } ?? []
    }

    private func progressCard(
        @ViewBuilder content: () -> some View,
    ) -> some View {
        Section {
            CompassCard {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let overview = model.rollingWorkoutOverviewBoundary?.overview()
            async let cardio = model.cardioProgressBoundary?.progress()
            async let liftItems = model.liftConfigurationBoundary.listTMs()

            rollingOverview = try await overview
            cardioProgress = try await cardio
            let items = try await liftItems
            var summaries: [LiftE1RMSummary] = []
            for item in items where item.identity.progressionLift != nil {
                if let configuration = item.configuration {
                    let progress = try await model.progressBoundary.progress(
                        selectedLiftID: configuration.id,
                    )
                    summaries.append(LiftE1RMSummary(configuration: configuration, progress: progress))
                } else {
                    summaries.append(LiftE1RMSummary(identity: item.identity))
                }
            }
            liftSummaries = summaries
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func efficiencyColor(_ direction: CardioInsightDirection) -> Color {
        switch direction {
        case .improving: CompassPalette.green
        case .declining: CompassPalette.red
        case .unchanged: CompassPalette.blue
        case .unavailable: CompassPalette.inkMuted
        }
    }

    private func efficiencySymbol(_ direction: CardioInsightDirection) -> String {
        switch direction {
        case .improving: "arrow.up.right"
        case .declining: "arrow.down.right"
        case .unchanged: "arrow.right"
        case .unavailable: "minus"
        }
    }
}

private struct LiftE1RMSummary: Identifiable {
    let id: String
    let name: String
    let latestKg: Double?
    let direction: E1RMTrendDirection

    init(configuration: LiftConfiguration, progress: E1RMProgress) {
        id = configuration.id
        name = configuration.identity.displayName
        latestKg = progress.latest?.estimatedKg
        direction = progress.trailing90DayDirection
    }

    init(identity: LiftIdentity) {
        id = identity.displayName
        name = identity.displayName
        latestKg = nil
        direction = .insufficientData
    }

    var latestText: String {
        latestKg.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "—"
    }

    var directionText: String {
        switch direction {
        case .upward: "Increasing"
        case .downward: "Decreasing"
        case .unchanged: "Holding steady"
        case .insufficientData: "Not enough results"
        }
    }

    var symbol: String {
        switch direction {
        case .upward: "arrow.up.right"
        case .downward: "arrow.down.right"
        case .unchanged: "arrow.right"
        case .insufficientData: "minus"
        }
    }

    var directionColor: Color {
        switch direction {
        case .upward: CompassPalette.green
        case .downward: CompassPalette.red
        case .unchanged: CompassPalette.blue
        case .insufficientData: CompassPalette.inkMuted
        }
    }
}

private struct HeartRateZoneRow: View {
    let zone: RollingWorkoutZone
    let duration: Double
    let percentage: Double
    let emphasis: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(zone.shortName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CompassPalette.navy)
                Spacer()
                Text(compactDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CompassPalette.navy)
                Text(percentage, format: .percent.scale(1).precision(.fractionLength(0)))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(CompassPalette.blue)
                    .frame(width: 42, alignment: .trailing)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(CompassPalette.line.opacity(0.55))
                    Capsule()
                        .fill(CompassPalette.blue.opacity(0.38 + emphasis * 0.62))
                        .frame(width: geometry.size.width * min(max(percentage / 100, 0), 1))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }

    private func compactDuration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

private struct HeartRateDriftRow: View {
    let drift: CardioHeartRateDrift

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(drift.activityType)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CompassPalette.navy)
                Text(drift.localDate.iso8601String)
                    .font(.caption2)
                    .foregroundStyle(CompassPalette.inkMuted)
            }
            Spacer()
            switch drift.availability {
            case .available:
                if let first = drift.firstHalfAverageBPM,
                   let second = drift.secondHalfAverageBPM,
                   let percent = drift.driftPercent
                {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(percent, format: .percent.scale(1).precision(.fractionLength(1)).sign(strategy: .always()))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(CompassPalette.blue)
                        Text("\(first.formatted(.number.precision(.fractionLength(0)))) → \(second.formatted(.number.precision(.fractionLength(0)))) bpm")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(CompassPalette.inkMuted)
                    }
                }
            case .unavailable:
                Text("Not enough HR data")
                    .font(.caption)
                    .foregroundStyle(CompassPalette.inkMuted)
            }
        }
        .padding(.vertical, 5)
        .accessibilityIdentifier("progress.heart-rate-drift.\(drift.id)")
    }
}

private extension RollingWorkoutZone {
    static let cardioZones: [RollingWorkoutZone] = [.zone1, .zone2, .zone3, .zone4, .zone5]

    var shortName: String {
        switch self {
        case .below50: "Below 50%"
        case .zone1: "Zone 1 · 50–59%"
        case .zone2: "Zone 2 · 60–69%"
        case .zone3: "Zone 3 · 70–79%"
        case .zone4: "Zone 4 · 80–89%"
        case .zone5: "Zone 5 · 90–100%"
        }
    }
}

private struct RunningRunDetailView: View {
    let summary: RunningRunSummary
    let model: AppModel
    let isExcluded: Bool

    @State private var exclusionError: String?
    @State private var excluded: Bool

    init(summary: RunningRunSummary, model: AppModel, isExcluded: Bool) {
        self.summary = summary
        self.model = model
        self.isExcluded = isExcluded
        _excluded = State(initialValue: isExcluded)
    }

    var body: some View {
        List {
            Section("Run") {
                LabeledContent("Run Date", value: summary.record.localDate.iso8601String)
                LabeledContent("Environment", value: summary.record.environment.displayName)
                LabeledContent("Source", value: summary.record.source)
                LabeledContent(
                    "Duration",
                    value: summary.record.durationSeconds.map { String(format: "%.1f min", $0 / 60) }
                        ?? "Unavailable",
                )
                LabeledContent(
                    "Distance",
                    value: summary.record.distanceMeters.map { String(format: "%.1f m", $0) } ?? "Unavailable",
                )
                LabeledContent(
                    "Average Running Pace", value: summary.averageRunningPace?.displayValue ?? "Unavailable",
                )
                LabeledContent(
                    "Elevation",
                    value: summary.record.elevationMeters.map { String(format: "%.1f m", $0) }
                        ?? "Unavailable",
                )
                LabeledContent("Route", value: summary.record.routeAvailability.displayName)
                LabeledContent(
                    "Heart-rate context",
                    value: summary.record.heartRate.averageBeatsPerMinute.map {
                        String(
                            format: "%.1f bpm (%.0f%% covered)", $0,
                            (summary.record.heartRate.coverage ?? 0) * 100,
                        )
                    } ?? "Unavailable",
                )
            }
            Section("Insight Explanation") {
                NavigationLink {
                    InsightExplanationDetailView(explanation: summary.explanation)
                } label: {
                    Label("Explain this run", systemImage: "info.circle")
                }
            }
            Section("Comparable Runs") {
                Text(
                    excluded
                        ? "Excluded from comparable trends; the run remains visible in history and Running Volume."
                        : "Included in comparable trends when its source-owned environment and distance match the reference.",
                )
                .font(.caption)
                Button(excluded ? "Restore to Comparable Runs" : "Exclude from Comparable Runs") {
                    Task {
                        do {
                            if excluded {
                                try await model.runningPerformanceBoundary?.includeRunningComparison(summary.id)
                            } else {
                                try await model.runningPerformanceBoundary?.excludeRunningComparison(summary.id)
                            }
                            excluded.toggle()
                        } catch {
                            exclusionError = String(describing: error)
                        }
                    }
                }
                .accessibilityIdentifier("progress.running.exclusion")
            }
        }
        .compassScreen()
        .navigationTitle("Run Details")
        .alert(
            "Could not update Running Comparison",
            isPresented: Binding(
                get: { exclusionError != nil },
                set: {
                    if !$0 {
                        exclusionError = nil
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exclusionError ?? "Try again.")
        }
    }
}

private struct InsightExplanationDetailView: View {
    let explanation: InsightExplanation

    var body: some View {
        List {
            Section("Question") { Text(explanation.question) }
            Section("Calculation") {
                Text(explanation.calculationRule)
                LabeledContent("Dates", value: explanation.dateRange)
                if let baseline = explanation.comparisonBaseline {
                    LabeledContent("Comparison", value: baseline)
                }
            }
            Section("Source and coverage") {
                Text(explanation.sourceCoverage)
                LabeledContent(
                    "Last reconciliation", value: explanation.lastReconciliation ?? "Not provided by source",
                )
                LabeledContent(
                    "Configuration", value: explanation.configuration ?? "No additional configuration",
                )
            }
            if !explanation.includedRecordIDs.isEmpty {
                Section("Included records") {
                    ForEach(explanation.includedRecordIDs, id: \.self) { Text($0).font(.caption) }
                }
            }
            if !explanation.missingData.isEmpty {
                Section("Missing data") {
                    ForEach(explanation.missingData, id: \.self) { Text($0).font(.caption) }
                }
            }
            if !explanation.exclusions.isEmpty {
                Section("Excluded records") {
                    ForEach(explanation.exclusions) { exclusion in
                        Text("\(exclusion.recordID) · \(exclusion.reason)").font(.caption)
                    }
                }
            }
        }
        .compassScreen()
        .navigationTitle("Insight Explanation")
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
                    value: event.sourceBadges.map(\.displayName).joined(separator: " + "),
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
                            : "Not affected by this link",
                    )
                    if event.linkState == .linked, link.isActive, !wasUnlinked {
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
                if model.healthWorkoutRouteBoundary != nil {
                    HealthWorkoutRouteView(healthKitUUID: workout.healthKitUUID, model: model)
                }
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
        .compassScreen()
        .navigationTitle("Training Event")
        .accessibilityIdentifier("training-event.detail")
        .onDisappear {
            guard let healthKitUUID = event.healthWorkout?.healthKitUUID else { return }
            Task { await model.healthWorkoutRouteBoundary?.cancelRoute(for: healthKitUUID) }
        }
        .confirmationDialog(
            "Unlink this Training Event?",
            isPresented: $showingUnlinkConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Confirm Unlink", role: .destructive) { Task { await unlink() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The Session and external Health Workout will appear as two Training Events. Neither record is deleted.",
            )
        }
        .alert(
            "Could not update Training Event",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
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
            HeartRateZoneDetailView(
                startDate: entry.event.startDate,
                endDate: entry.event.endDate,
                enrichment: entry.enrichment,
                provider: model.heartRateZoneProvider,
            )
            if model.healthWorkoutRouteBoundary != nil {
                HealthWorkoutRouteView(healthKitUUID: entry.event.healthKitUUID, model: model)
            }
            Section("Reconciliation") {
                LabeledContent("State", value: entry.state.displayName)
                if let context = entry.event.reconciliationContext {
                    LabeledContent("Context", value: context)
                }
                if let date = entry.event.lastSuccessfulReconciliation {
                    LabeledContent(
                        "Last successful check", value: date.formatted(date: .abbreviated, time: .shortened),
                    )
                }
            }
        }
        .compassScreen()
        .navigationTitle("Health Workout")
        .onDisappear {
            Task {
                await model.healthWorkoutRouteBoundary?.cancelRoute(for: entry.event.healthKitUUID)
            }
        }
    }
}

private struct HeartRateZoneDetailView: View {
    let startDate: Date
    let endDate: Date
    let enrichment: HealthWorkoutEnrichment
    let provider: HealthWorkoutHeartRateZoneProvider?

    @State private var projection: HeartRateZoneProjection?

    var body: some View {
        Section("Heart-Rate Zones") {
            if let projection {
                if let maximum = projection.maximumHeartRateBPM {
                    LabeledContent("Maximum used", value: "\(String(format: "%.1f", maximum)) bpm")
                }
                ForEach(RollingWorkoutZone.allCases, id: \.self) { zone in
                    let seconds = projection.zoneDurations[zone] ?? 0
                    LabeledContent(
                        zone.displayName,
                        value: String(
                            format: "%.1f min · %.1f%% covered",
                            seconds / 60,
                            projection.zonePercentagesOfCoveredTime[zone] ?? 0,
                        ),
                    )
                }
                LabeledContent(
                    "Covered duration",
                    value: "\(String(format: "%.1f", projection.coveredSeconds / 60)) min",
                )
                LabeledContent(
                    "Workout coverage",
                    value: "\(String(format: "%.1f", projection.coverageOfWorkoutPercentage))%",
                )
                ForEach(projection.sourceSummaries) { source in
                    Text(
                        "Source: \(source.source) · \(String(format: "%.1f", source.coveredSeconds / 60)) min",
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if projection.unclassifiedSeconds > 0 {
                    LabeledContent(
                        "Above maximum / unclassified",
                        value: "\(String(format: "%.1f", projection.unclassifiedSeconds / 60)) min",
                    )
                }
                ForEach(projection.intervals) { interval in
                    Text(
                        "Interval · \(interval.source) · \(String(format: "%.1f", interval.durationSeconds / 60)) min · \(interval.zone?.displayName ?? "Above maximum")",
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                ForEach(projection.unavailableIntervals) { interval in
                    Text(
                        "Unavailable · \(interval.reason) · \(String(format: "%.1f", interval.durationSeconds / 60)) min",
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                NavigationLink {
                    InsightExplanationDetailView(explanation: projection.explanation)
                } label: {
                    Label("Explain Heart-Rate Zone calculation", systemImage: "info.circle")
                }
                Text(
                    "Only source-observed intervals are counted. Gaps over 60 seconds and workout edges remain unavailable.",
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if enrichment.heartRate.state == .available {
                Text("Configure a positive maximum heart rate to calculate zones.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Heart-rate zones are unavailable until associated samples are available.")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard let provider else { return }
            let availability = await provider.zoneTimes(
                startDate: startDate, endDate: endDate, enrichment: enrichment,
            )
            if case let .projected(result) = availability {
                projection = result
            }
        }
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
                    systemImage: "exclamationmark.triangle",
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
                        "Retained points", value: "\(route.points.count) of \(route.originalPointCount)",
                    )
                    LabeledContent(
                        "Source",
                        value: route.sources.map(\.provenance.displayName).joined(separator: ", "),
                    )
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
            let minimumSpanDegrees = 0.000_1
            let northSpan = max(maximumNorth - minimumNorth, minimumSpanDegrees)
            let averageNorth = (minimumNorth + maximumNorth) / 2
            let eastScale = cos(averageNorth * .pi / 180)
            let eastSpan = max(
                (maximumEast - minimumEast) * eastScale, minimumSpanDegrees,
            )
            let inset: CGFloat = 16
            let drawingWidth = max(1, size.width - inset * 2)
            let drawingHeight = max(1, size.height - inset * 2)
            let drawingScale = min(
                drawingWidth / CGFloat(eastSpan),
                drawingHeight / CGFloat(northSpan),
            )
            let horizontalOffset = inset + (drawingWidth - CGFloat(eastSpan) * drawingScale) / 2
            let verticalOffset = inset + (drawingHeight - CGFloat(northSpan) * drawingScale) / 2
            func displayPoint(_ point: HealthWorkoutRoutePoint) -> CGPoint {
                CGPoint(
                    x: horizontalOffset
                        + CGFloat((point.eastWestDegrees - minimumEast) * eastScale) * drawingScale,
                    y: verticalOffset
                        + CGFloat(maximumNorth - point.northSouthDegrees) * drawingScale,
                )
            }
            for segment in segments {
                guard let segmentFirst = segment.points.first else { continue }
                var path = Path()
                path.move(to: displayPoint(segmentFirst))
                for point in segment.points.dropFirst() {
                    path.addLine(to: displayPoint(point))
                }
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
                    "Only source-observed sample intervals are retained; gaps and workout edges are not inferred.",
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            enrichmentContext(
                lastSuccessfulCheck: enrichment.heartRate.lastSuccessfulCheck,
                reconciliationContext: enrichment.heartRate.reconciliationContext,
                label: "Heart rate",
            )

            LabeledContent("Distance", value: quantityValue(enrichment.distance))
            enrichmentContext(
                lastSuccessfulCheck: enrichment.distance.lastSuccessfulCheck,
                reconciliationContext: enrichment.distance.reconciliationContext,
                label: "Distance",
            )

            LabeledContent("Active energy", value: quantityValue(enrichment.activeEnergy))
            enrichmentContext(
                lastSuccessfulCheck: enrichment.activeEnergy.lastSuccessfulCheck,
                reconciliationContext: enrichment.activeEnergy.reconciliationContext,
                label: "Active energy",
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
        let formatted = switch quantity.unit {
        case .meters:
            String(format: "%.2f km", quantity.value / 1000)
        case .kilocalories:
            String(format: "%.0f kcal", quantity.value)
        }
        return detail.state == .failed ? "Update failed · cached \(formatted)" : formatted
    }

    @ViewBuilder
    private func enrichmentContext(
        lastSuccessfulCheck: Date?,
        reconciliationContext: String?,
        label: String,
    ) -> some View {
        if let lastSuccessfulCheck {
            Text(
                "\(label) last successful check: \(lastSuccessfulCheck.formatted(date: .abbreviated, time: .shortened))",
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
    let explanation: InsightExplanation

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
            Section("Insight Explanation") {
                NavigationLink {
                    InsightExplanationDetailView(explanation: explanation)
                } label: {
                    Label("Explain this e1RM point", systemImage: "info.circle")
                }
            }
        }
        .compassScreen()
        .navigationTitle("Progress Source")
    }
}

private struct ProgressMetric: View {
    let label: String
    let observation: E1RMObservation?
    let explanation: InsightExplanation

    var body: some View {
        NavigationLink {
            InsightExplanationDetailView(explanation: explanation)
        } label: {
            LabeledContent(label, value: observation?.displayValue ?? "—")
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
    @State private var showingWriteBackChoice = false
    @State private var pendingWriteBackChoice: SessionWriteBackChoice = .doNotShare
    @State private var writeBackPreference = HealthWorkoutWriteBackPreference()
    @State private var writeBackRecord: HealthWorkoutWriteBackRecord?
    @State private var writeBackAccessMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if model.phase != .ready {
                ContentUnavailableView {
                    Label {
                        Text("Training Compass")
                    } icon: {
                        CompassBrandMark()
                            .frame(width: 32, height: 32)
                    }
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
                        todayPlanCard(today)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Section {
                        assistanceCard(today)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Section {
                        trainingMaxCard(today)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if !todayEvents.isEmpty {
                        Section("Today’s Training Events") {
                            ForEach(todayEvents) { event in
                                TodayTrainingEventRow(event: event, model: model)
                            }
                        }
                    }

                    Section("Assistance Sets") {
                        ForEach(today.sets.filter { $0.prescription.role == .assistance }) { set in
                            TodaySetRow(
                                set: set,
                                weight: Binding(
                                    get: { weightText[set.id] ?? set.result.map { String($0.weightKg) } ?? "" },
                                    set: { weightText[set.id] = $0 },
                                ),
                                repetitions: Binding(
                                    get: {
                                        repetitionsText[set.id]
                                            ?? set.result.map { String($0.repetitions) }
                                            ?? String(set.prescription.repetitions)
                                    },
                                    set: { repetitionsText[set.id] = $0 },
                                ),
                                onConfirm: { Task { await confirm(set) } },
                                onOmit: { Task { await omit(set) } },
                            )
                        }
                    }

                    Section("Additional Sets") {
                        if !today.additionalSets.isEmpty {
                            EditButton()
                        }
                        ForEach(today.additionalSets) { additional in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    "\(additional.liftID) · \(additional.weightKg, specifier: "%.2f") kg · \(additional.repetitions) reps",
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
                                        "Set \(set.prescription.setNumber) · \(set.prescription.role.rawValue.capitalized)",
                                    )
                                    Text(
                                        "Planned: \(set.prescription.weightKg, specifier: "%.2f") kg × \(set.prescription.repetitions) reps",
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    if let result = set.result {
                                        Text(
                                            "Actual: \(result.weightKg, specifier: "%.2f") kg × \(result.repetitions) reps\(result.repetitions == 0 ? " · Failed" : "")",
                                        )
                                        .font(.caption)
                                    } else if let omission = set.omission {
                                        Text(omission.reason.map { "Omitted: \($0)" } ?? "Omitted")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if let writeBackRecord {
                                LabeledContent("HealthKit summary", value: writeBackRecord.state.displayName)
                                    .accessibilityIdentifier("today.write-back.state")
                                writeBackRecoveryActions(for: writeBackRecord)
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            HealthView(model: model)
                        } label: {
                            Label("Health", systemImage: "heart.fill")
                                .foregroundStyle(CompassPalette.green)
                        }
                        .accessibilityIdentifier("today.health-status")
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if todayEvents.isEmpty {
                            CompassEmptyState(
                                title: "Nothing scheduled today",
                                message: "No local Session or imported Health Workout is available for today.",
                                systemImage: "checkmark.circle",
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Today’s Training Events")
                                    .font(.headline)
                                    .foregroundStyle(CompassPalette.navy)
                                ForEach(todayEvents) { event in
                                    TodayTrainingEventRow(event: event, model: model)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 128)
                }
            }
        }
        .compassScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .compassTopBarTitle(
            "Today",
            subtitle: Date.now.formatted(
                .dateTime.weekday(.wide).month(.abbreviated).day().year(),
            ),
        )
        .compassNavigationTitle("Today")
        .accessibilityIdentifier("today.destination")
        .task(id: model.phase) {
            if model.phase == .ready {
                await reload()
            }
        }
        .alert(
            "Could not record Set Result",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
        .confirmationDialog(
            "Complete this Session?",
            isPresented: $showingCompletionConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Confirm Completion") { Task { await beginCompletionDecision() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Completion records the planned-versus-actual work and every set disposition. Local completion never depends on Health access.",
            )
        }
        .confirmationDialog(
            "Share a summary with Health?",
            isPresented: $showingWriteBackChoice,
            titleVisibility: .visible,
        ) {
            Button("Share summary") {
                pendingWriteBackChoice = .share
                Task { await beginCompletion() }
            }
            Button("Keep this Session local") {
                pendingWriteBackChoice = .doNotShare
                Task { await beginCompletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Only the Traditional Strength Training start, end, duration, and stable sync identifier/version are shared. Sets, loads, prescriptions, Training Maxes, e1RM, notes, and audit history remain local.",
            )
        }
        .confirmationDialog(
            "Confirm unusual Training Event match?",
            isPresented: $showingUnusualMatchConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Confirm Unusual Match") {
                guard let candidate = pendingCandidate else { return }
                Task {
                    await performLink(
                        candidate,
                        duringCompletion: pendingCandidateLinksDuringCompletion,
                        confirmation: .confirmedUnusualMatch,
                    )
                }
            }
            Button("Cancel", role: .cancel) { pendingCandidate = nil }
        } message: {
            Text(
                pendingCandidate?.warnings.map(\.message).joined(separator: " ")
                    ?? "Review both sources before linking.",
            )
        }
    }

    private func todayPlanCard(_ today: TodaySessionSnapshot) -> some View {
        CompassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        CompassSectionTitle(title: "Today’s Plan")
                        Text("5/3/1 – \(today.weekKind.displayName)")
                            .font(.system(.headline, design: .serif).weight(.bold))
                            .foregroundStyle(CompassPalette.navy)
                    }
                    Spacer()
                    CompassStatusPill(title: today.state.displayName)
                }

                if today.completion != nil {
                    Label("5/3/1 Session saved locally", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CompassPalette.green)
                        .accessibilityIdentifier("today.session.saved")
                }

                Divider()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRIMARY LIFT")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CompassPalette.inkMuted)
                        HStack(spacing: 7) {
                            Text(today.primaryLift.identity.displayName)
                                .font(.system(.title3, design: .serif).weight(.bold))
                                .foregroundStyle(CompassPalette.navy)
                            CompassStatusPill(title: "5/3/1", color: CompassPalette.inkMuted)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("TM")
                            .font(.caption2)
                            .foregroundStyle(CompassPalette.inkMuted)
                        Text("\(today.primaryLift.trainingMaxKg, specifier: "%.1f") kg")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(CompassPalette.navy)
                    }
                }

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text("SET").frame(width: 24, alignment: .leading)
                        Text("PLANNED").frame(width: 58, alignment: .leading)
                        Text("TARGET").frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 4) {
                            Text("KG").frame(width: 40)
                            Text("REPS").frame(width: 30)
                            Text("✓").frame(width: 18)
                            Text("−").frame(width: 18)
                        }
                        .frame(width: 118, alignment: .leading)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CompassPalette.inkMuted)

                    ForEach(today.sets.filter { $0.prescription.role == .primary }) { set in
                        HStack(spacing: 4) {
                            Text("\(set.prescription.setNumber)")
                                .frame(width: 24, alignment: .leading)
                            Text(
                                "\(set.prescription.repetitions)\(set.prescription.isPlusSetEligible ? "+" : "") · \(set.prescription.percentage * 100, specifier: "%.0f")%",
                            )
                            .frame(width: 58, alignment: .leading)
                            Text("\(set.prescription.weightKg, specifier: "%.1f") kg")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            TextField(
                                "kg",
                                text: Binding(
                                    get: { weightText[set.id] ?? set.result.map { String($0.weightKg) } ?? "" },
                                    set: { weightText[set.id] = $0 },
                                ),
                            )
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption2.monospacedDigit())
                            .frame(width: 40, height: 26)
                            .accessibilityIdentifier("today.weight.\(set.id)")
                            TextField(
                                "reps",
                                text: Binding(
                                    get: {
                                        repetitionsText[set.id]
                                            ?? set.result.map { String($0.repetitions) }
                                            ?? String(set.prescription.repetitions)
                                    },
                                    set: { repetitionsText[set.id] = $0 },
                                ),
                            )
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption2.monospacedDigit())
                            .frame(width: 30, height: 26)
                            .accessibilityIdentifier("today.repetitions.\(set.id)")
                            Button {
                                if set.omission == nil {
                                    Task { await confirm(set) }
                                } else {
                                    Task { await omit(set) }
                                }
                            } label: {
                                Image(
                                    systemName: set.completionState == .recorded
                                        ? "checkmark.circle.fill"
                                        : set.omission == nil ? "checkmark.circle" : "minus.circle.fill",
                                )
                                .foregroundStyle(
                                    set.completionState == .recorded
                                        ? CompassPalette.green
                                        : set.omission == nil ? CompassPalette.blue : CompassPalette.red,
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(set.omission != nil)
                            .accessibilityLabel("Confirm")
                            .accessibilityIdentifier("today.confirm.\(set.id)")
                            Button {
                                Task { await omit(set) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(CompassPalette.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Omit Set")
                            .accessibilityIdentifier("today.omit.\(set.id)")
                        }
                        .font(.caption.monospacedDigit())
                        .background(
                            set.completionState == .failed || set.completionState == .omitted
                                ? CompassPalette.red.opacity(0.06)
                                : Color.clear,
                        )
                    }
                }

                Button {
                    additionalLiftID = today.assistanceLift.identity.displayName
                } label: {
                    Label("Add Additional Set", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func assistanceCard(_ today: TodaySessionSnapshot) -> some View {
        let assistanceSets = today.sets.filter { $0.prescription.role == .assistance }
        return CompassCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    CompassSectionTitle(title: "Assistance Lift")
                    Text(today.assistanceLift.identity.displayName)
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundStyle(CompassPalette.navy)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let first = assistanceSets.first {
                        Text("\(assistanceSets.count) × \(first.prescription.repetitions)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(CompassPalette.navy)
                    }
                    Text("\(today.assistanceLift.trainingMaxKg, specifier: "%.1f") kg TM")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CompassPalette.inkMuted)
                }
            }
        }
    }

    private func trainingMaxCard(_ today: TodaySessionSnapshot) -> some View {
        CompassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CompassSectionTitle(title: "Training Max (TM)")
                    Spacer()
                    Text("Frozen for this cycle")
                        .font(.caption2)
                        .foregroundStyle(CompassPalette.blue)
                }
                HStack(spacing: 0) {
                    CompassMetricValue(
                        label: today.primaryLift.identity.displayName,
                        value: String(format: "%.1f kg", today.primaryLift.trainingMaxKg),
                    )
                    Divider().frame(height: 34)
                    CompassMetricValue(
                        label: today.assistanceLift.identity.displayName,
                        value: String(format: "%.1f kg", today.assistanceLift.trainingMaxKg),
                    )
                    .padding(.leading, 12)
                }
            }
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
            Section("Optional: Link External Health Workout") {
                Label(
                    "Your 5/3/1 Session is already saved locally. "
                        + "These are separate Apple Health workouts; linking is optional.",
                    systemImage: "info.circle",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    "Choose explicitly. Ranking is advisory and Training Compass never links automatically.",
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
                                    "Unusual match · confirmation required", systemImage: "exclamationmark.triangle",
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
                    Text("Do not link").tag(String?.none)
                    ForEach(candidates) { candidate in
                        Text(
                            "\(candidate.workout.activityType) · \(candidate.workout.localDate)\(candidate.requiresWarningAcknowledgement ? " · Warning" : "")",
                        )
                        .tag(Optional(candidate.id))
                    }
                }
                .accessibilityIdentifier("training-event.completion-candidate")
                Text(
                    "Every currently unlinked external workout remains selectable; no candidate is preselected.",
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
        duringCompletion: Bool,
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
                    confirmation: .confirmed,
                )
            }
        }
    }

    private func beginCompletionDecision() async {
        guard let boundary = model.healthWorkoutWriteBackBoundary else {
            pendingWriteBackChoice = .doNotShare
            await beginCompletion()
            return
        }
        writeBackPreference = await (try? boundary.preference()) ?? .init()
        if writeBackPreference.enabled {
            showingWriteBackChoice = true
        } else {
            pendingWriteBackChoice = .doNotShare
            await beginCompletion()
        }
    }

    @ViewBuilder
    private func writeBackRecoveryActions(for record: HealthWorkoutWriteBackRecord) -> some View {
        if record.state == .deletedFromHealth {
            Button("Restore to Health") {
                Task { await restoreDeletedWriteBack(record.sessionID) }
            }
            .accessibilityIdentifier("today.write-back.restore")
            Text(
                "The Health summary was deleted outside Training Compass. Restore creates a new version only when you choose it.",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if record.state == .healthAccessNeeded {
            Button("Check Health Access") {
                Task { await checkWriteBackAccess() }
            }
            .accessibilityIdentifier("today.write-back.check-access")
        }
        if record.state == .healthAccessNeeded || record.state == .couldntSave {
            Button("Try Again") {
                Task { await retryWriteBack(record.sessionID) }
            }
            .accessibilityIdentifier("today.write-back.try-again")
        }
        if let writeBackAccessMessage {
            Text(writeBackAccessMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkWriteBackAccess() async {
        guard let boundary = model.healthWorkoutWriteBackBoundary else { return }
        do {
            _ = try await boundary.checkWriteAccess()
            writeBackAccessMessage = nil
        } catch {
            writeBackAccessMessage =
                "Health write access is still unavailable. Check Health settings, then try again."
        }
    }

    private func retryWriteBack(_ sessionID: String) async {
        guard let boundary = model.healthWorkoutWriteBackBoundary else { return }
        writeBackRecord = await boundary.retry(sessionID: sessionID)
        writeBackAccessMessage = nil
        await reload()
    }

    private func restoreDeletedWriteBack(_ sessionID: String) async {
        guard let today, today.session.id == sessionID,
              let completion = today.completion,
              let boundary = model.healthWorkoutWriteBackBoundary
        else { return }
        writeBackRecord = await boundary.restoreToHealth(
            session: today,
            completedAt: Date(timeIntervalSince1970: TimeInterval(completion.confirmedAt)),
        )
        await reload()
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
        confirmation: TrainingEventLinkConfirmation,
    ) async {
        guard let boundary = model.trainingEventLinkBoundary,
              let sessionID = today?.session.id
        else { return }
        do {
            if duringCompletion {
                _ = try await boundary.completeSession(
                    linking: candidate,
                    to: sessionID,
                    confirmation: confirmation,
                )
                await queueWriteBack()
            } else {
                _ = try await boundary.confirmLink(
                    candidate,
                    to: sessionID,
                    confirmation: confirmation,
                )
            }
            pendingCandidate = nil
            selectedCompletionCandidateID = nil
            await reload()
        } catch TrainingEventLinkError.staleCandidate {
            errorMessage = "The Session or Health Workout changed. Review the candidates again."
            await reload()
        } catch TrainingEventLinkError.appAuthoredSummaryDeletionFailed {
            errorMessage =
                "The Training Compass Health summary could not be deleted. No external link was created; try again."
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
            if let sessionID = today?.session.id,
               let writeBackBoundary = model.healthWorkoutWriteBackBoundary
            {
                writeBackPreference = await (try? writeBackBoundary.preference()) ?? .init()
                writeBackRecord = try? await writeBackBoundary.state(for: sessionID)
            } else {
                writeBackRecord = nil
            }
            let date = today?.intendedDate ?? TrainingDate(date: Date())
            await todayEvents =
                (try? model.trainingEventLinkBoundary?.timeline(on: date).events) ?? []
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
                      ?? String(set.prescription.repetitions),
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
                expectedBefore: set.result,
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
                expectedBefore: set.result,
            )
            await reload()
        } catch { errorMessage = String(describing: error) }
    }

    private func completeWithoutLink() async {
        do {
            _ = try await model.sessionLoggingBoundary.confirmSession(sessionID: today?.session.id ?? "")
            await queueWriteBack()
        } catch { errorMessage = String(describing: error) }
    }

    private func queueWriteBack() async {
        await reload()
        guard let today, let boundary = model.healthWorkoutWriteBackBoundary,
              let completion = today.completion
        else { return }
        writeBackRecord = await boundary.queue(
            session: today,
            completedAt: Date(timeIntervalSince1970: TimeInterval(completion.confirmedAt)),
            choice: pendingWriteBackChoice,
        )
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
                    weightKg: weight, repetitions: repetitions, note: additionalNote,
                )
            } else {
                _ = try await model.sessionLoggingBoundary.addAdditionalSet(
                    sessionID: today?.session.id ?? "", liftID: additionalLiftID,
                    weightKg: weight, repetitions: repetitions, note: additionalNote,
                )
            }
            clearAdditionalDraft()
            await reload()
        } catch { errorMessage = String(describing: error) }
    }

    private func remove(_ set: AdditionalSet) async {
        do {
            try await model.sessionLoggingBoundary.removeAdditionalSet(
                sessionID: today?.session.id ?? "", id: set.id,
            )
            await reload()
        } catch { errorMessage = String(describing: error) }
    }

    private func reorderAdditionalSets(_ ids: [String]) async {
        do {
            try await model.sessionLoggingBoundary.reorderAdditionalSets(
                sessionID: today?.session.id ?? "", orderedIDs: ids,
            )
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
        if event.session != nil, event.healthWorkout != nil {
            return "Linked Training Event"
        }
        if event.session != nil {
            return "5/3/1 Session"
        }
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
                    "Target \(set.prescription.repetitions) reps at \(set.prescription.weightKg, specifier: "%.2f") kg",
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
                    systemImage: "exclamationmark.triangle",
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
                    systemImage: "minus.circle",
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
            description: Text(detail),
        )
        .compassScreen()
        .navigationTitle(title)
        .accessibilityIdentifier("pre-data.\(title.lowercased()).unavailable")
    }
}

private struct CycleSetupView: View {
    let lifts: [LiftConfiguration]
    let onConfigureTrainingMaxes: () -> Void

    private let requiredLifts = LiftCatalog.progressionIdentities

    private var missingLifts: [String] {
        let configured = Set(lifts.map(\.identity))
        return requiredLifts.compactMap { identity in
            configured.contains(identity) ? nil : identity.displayName
        }
    }

    private var readyLiftCount: Int {
        requiredLifts.count - missingLifts.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CompassCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CompassPalette.blue)
                            .frame(width: 44, height: 44)
                            .background(CompassPalette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Set up your first cycle")
                                .font(.system(.title2, design: .serif).weight(.bold))
                                .foregroundStyle(CompassPalette.navy)
                            Text(
                                "Training Maxes are needed to calculate the schedule and freeze the prescriptions used when a cycle starts.",
                            )
                            .font(.body)
                            .foregroundStyle(CompassPalette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(readyLiftCount) of \(requiredLifts.count) lifts ready")
                                .font(.headline)
                                .foregroundStyle(CompassPalette.navy)
                            ProgressView(
                                value: Double(readyLiftCount),
                                total: Double(requiredLifts.count),
                            )
                            ForEach(missingLifts, id: \.self) { name in
                                Label(name, systemImage: "circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button("Set Up Training Maxes") {
                            onConfigureTrainingMaxes()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("cycle.setup-training-maxes")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 96)
        }
        .accessibilityIdentifier("cycle.setup")
    }
}

private struct NewCycleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var anchorDate: Date

    let template: ScheduleTemplate
    let liftName: (String) -> String
    let canStartImmediately: Bool
    let onCommit: (Date, Bool) -> Void

    init(
        anchorDate: Date,
        template: ScheduleTemplate,
        liftName: @escaping (String) -> String,
        canStartImmediately: Bool,
        onCommit: @escaping (Date, Bool) -> Void,
    ) {
        _anchorDate = State(initialValue: anchorDate)
        self.template = template
        self.liftName = liftName
        self.canStartImmediately = canStartImmediately
        self.onCommit = onCommit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Week 1") {
                    DatePicker(
                        "Starts",
                        selection: $anchorDate,
                        displayedComponents: [.date],
                    )
                    .accessibilityIdentifier("cycle.new.anchor")
                    Text("Dates are stored without a time zone. Monday is the recommended anchor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Weekly Schedule") {
                    ForEach(template.sessions) { session in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.intendedWeekday.displayName)
                                .font(.headline)
                            Text(
                                "\(liftName(session.primaryLiftID)) · \(liftName(session.assistanceLiftID))",
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if canStartImmediately {
                        Button(isHistoricalStart ? "Start & Add Past Results" : "Start Cycle") {
                            onCommit(anchorDate, true)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("cycle.new.start")
                    }

                    Button(canStartImmediately ? "Save as Draft" : "Save Next Cycle as Draft") {
                        onCommit(anchorDate, false)
                    }
                    .accessibilityIdentifier("cycle.new.save-draft")
                } footer: {
                    Text(
                        canStartImmediately
                            ? isHistoricalStart
                            ? "Starting keeps this past Week 1 date. Next, add top-set reps for sessions you already completed."
                            : "Starting snapshots the current Training Maxes. A draft remains editable until it is started."
                            : "The active cycle is unchanged. This draft can start after the active cycle is completed or abandoned.",
                    )
                }
            }
            .compassScreen()
            .navigationTitle("New Training Cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isHistoricalStart: Bool {
        TrainingDate(date: anchorDate) < TrainingDate(date: Date())
    }
}

private struct NewCycleCommit {
    let anchorDate: Date
    let startsImmediately: Bool
}

private struct HistoricalSessionImportDraft: Identifiable {
    let id: String
    let intendedDate: TrainingDate
    let weekName: String
    let primaryLiftName: String
    let topSetWeightKg: Double
    let minimumRepetitions: Int
    var isSelected = true
    var repetitions: String
}

private struct HistoricalSessionImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [HistoricalSessionImportDraft]
    @State private var isImporting = false
    @State private var errorMessage: String?
    @FocusState private var focusedSessionID: String?

    let onImport: ([HistoricalSessionImportDraft]) async throws -> Void

    init(
        drafts: [HistoricalSessionImportDraft],
        onImport: @escaping ([HistoricalSessionImportDraft]) async throws -> Void,
    ) {
        _drafts = State(initialValue: drafts)
        self.onImport = onImport
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Select the sessions you completed in your spreadsheet, then enter the reps from each primary top set.",
                    )
                    .font(.subheadline)
                } footer: {
                    Text(
                        "For selected sessions, every other unresolved set is recorded at its prescribed weight and reps.",
                    )
                }

                ForEach($drafts) { $draft in
                    Section {
                        Toggle("Completed", isOn: $draft.isSelected)
                            .accessibilityIdentifier("cycle.import.session.\(draft.id)")
                        if draft.isSelected {
                            LabeledContent("Primary lift", value: draft.primaryLiftName)
                            LabeledContent(
                                "Top-set weight",
                                value: String(format: "%.2f kg", draft.topSetWeightKg),
                            )
                            TextField("Top-set reps", text: $draft.repetitions)
                                .keyboardType(.numberPad)
                                .focused($focusedSessionID, equals: draft.id)
                                .accessibilityIdentifier("cycle.import.reps.\(draft.id)")
                        }
                    } header: {
                        Text(
                            "\(draft.intendedDate.date().formatted(date: .abbreviated, time: .omitted)) · \(draft.weekName)",
                        )
                    } footer: {
                        if draft.isSelected {
                            Text("Prescribed minimum: \(draft.minimumRepetitions) reps")
                        }
                    }
                }

                Section {
                    Button(importButtonTitle) {
                        Task { await importSelectedSessions() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canImport || isImporting)
                    .accessibilityIdentifier("cycle.import.confirm")
                }
            }
            .compassScreen()
            .navigationTitle("Add Past Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedSessionID = nil }
                        .accessibilityIdentifier("cycle.import.keyboard-done")
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Adding completed sessions…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .alert(
                "Could not add past results",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    },
                ),
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Review the selected sessions and try again.")
            }
        }
    }

    private var selectedDrafts: [HistoricalSessionImportDraft] {
        drafts.filter(\.isSelected)
    }

    private var canImport: Bool {
        !selectedDrafts.isEmpty
            && selectedDrafts.allSatisfy {
                guard let repetitions = Int($0.repetitions) else { return false }
                return repetitions >= 0
            }
    }

    private var importButtonTitle: String {
        let count = selectedDrafts.count
        return "Add \(count) Completed Session\(count == 1 ? "" : "s")"
    }

    private func importSelectedSessions() async {
        guard canImport else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            try await onImport(selectedDrafts)
            dismiss()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

private struct CycleView: View {
    let model: AppModel
    let onConfigureTrainingMaxes: () -> Void

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
    @State private var isLoading = true
    @State private var showingNewCycle = false
    @State private var showingHistoricalImport = false
    @State private var pendingNewCycleCommit: NewCycleCommit?
    @State private var startsAfterCreation = false
    @State private var showingSaveConfirmation = false
    @State private var showingResetConfirmation = false
    @State private var showingCycleConfirmation = false
    @State private var showingCycleActivationConfirmation = false
    @State private var showingCycleDiscardConfirmation = false
    @State private var pendingLifecycleRequest: CycleLifecycleRequest?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading cycle…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if template == nil {
                CycleSetupView(lifts: lifts, onConfigureTrainingMaxes: onConfigureTrainingMaxes)
            } else {
                AnyView(
                    List {
                        if let visibleCycle = activeCycle ?? draftCycle {
                            Section {
                                cycleOverviewCard(visibleCycle)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        if draftCycle == nil {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label(
                                        activeCycle == nil ? "Ready for a new cycle" : "Plan the next cycle",
                                        systemImage: activeCycle == nil
                                            ? "location.north.circle.fill"
                                            : "calendar.badge.plus",
                                    )
                                    .font(.headline)
                                    .foregroundStyle(CompassPalette.navy)

                                    Text(
                                        activeCycle == nil
                                            ? "Choose the Week 1 date, review the copied schedule, then start when you are ready."
                                            : "Prepare the next cycle now. It stays editable until the active cycle is complete.",
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                    Button(activeCycle == nil ? "Start a New Cycle" : "Plan Next Cycle") {
                                        showingNewCycle = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .accessibilityIdentifier("cycle.new")
                                }
                                .padding(.vertical, 6)
                            }
                        }

                        Section {
                            Text(
                                "This reusable normal-week layout is copied into future Training Cycles. Changes stay local until you explicitly save them.",
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
                                            session: $0, week: $1, cycleID: draftCycle.id,
                                        )
                                    },
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
                                    Button("Start Training Cycle") {
                                        Task { await reviewCycleActivation(anchorChoice: .retain) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("cycle.activate")
                                    if draftCycle.week1AnchorDate < TrainingDate(date: Date()) {
                                        DatePicker(
                                            "New Week 1 date",
                                            selection: $anchorDate,
                                            displayedComponents: [.date],
                                        )
                                        Button("Start with New Date") {
                                            Task {
                                                await reviewCycleActivation(
                                                    anchorChoice: .replace(
                                                        TrainingDate(date: anchorDate),
                                                    ),
                                                )
                                            }
                                        }
                                        .accessibilityIdentifier("cycle.activate-replace-anchor")
                                    }
                                }
                            } else {
                                Text("No draft is being edited.")
                                    .foregroundStyle(.secondary)
                            }
                            if let activeCycle {
                                ActiveCycleSection(
                                    cycle: activeCycle,
                                    liftName: liftName,
                                    historicalSessionCount: historicalImportDrafts.count,
                                    onImportHistory: { showingHistoricalImport = true },
                                    onEdit: {
                                        cycleSessionDraft = CycleSessionDraft(
                                            session: $0, week: $1, cycleID: activeCycle.id,
                                        )
                                    },
                                    onRequestLifecycle: { pendingLifecycleRequest = $0 },
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
                                            : audit.changeKind == .programEdit ? "Program Edit" : audit.action.rawValue,
                                    )
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
                                                "\(entry.lifecycleBadge) · \(entry.includesDeloadBadge ? "Deload" : "No Deload")",
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
                                            "Primary: \(liftName(session.primaryLiftID)) · Assistance: \(liftName(session.assistanceLiftID))",
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
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            EditButton()
                            Menu("Schedule Template", systemImage: "ellipsis.circle") {
                                Button("Reset to Default", systemImage: "arrow.counterclockwise") {
                                    Task { await reviewReset() }
                                }
                                .accessibilityIdentifier("schedule.reset")
                                Button("Save Changes", systemImage: "checkmark") {
                                    Task { await reviewSave() }
                                }
                                .disabled(workingSessions.isEmpty)
                                .accessibilityIdentifier("schedule.save")
                            }
                            .accessibilityIdentifier("schedule.actions")
                        }
                    },
                )
            }
        }
        .compassScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .compassTopBarTitle("Cycle")
        .compassNavigationTitle("Cycle")
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
                cycleSessionDraft = nil
                Task { await reviewCycleEdit(reviewedDraft) }
            }
        }
        .sheet(
            isPresented: $showingNewCycle,
            onDismiss: {
                guard let commit = pendingNewCycleCommit else { return }
                anchorDate = commit.anchorDate
                pendingNewCycleCommit = nil
                Task {
                    await reviewCycleCreation(startAfterCreation: commit.startsImmediately)
                }
            },
        ) {
            if let template {
                NewCycleSheet(
                    anchorDate: anchorDate,
                    template: template,
                    liftName: liftName,
                    canStartImmediately: activeCycle == nil,
                ) { date, shouldStart in
                    pendingNewCycleCommit = NewCycleCommit(
                        anchorDate: date,
                        startsImmediately: shouldStart,
                    )
                    showingNewCycle = false
                }
            }
        }
        .sheet(isPresented: $showingHistoricalImport) {
            HistoricalSessionImportSheet(drafts: historicalImportDrafts) { drafts in
                try await importHistoricalSessions(drafts)
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
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
        .alert("Confirm Draft Training Cycle", isPresented: $showingCycleConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingCycleChange = nil
                startsAfterCreation = false
            }
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
                "This permanently removes the editable draft. The Schedule Template and any Active Training Cycle remain unchanged.",
            )
        }
        .confirmationDialog(
            lifecycleRequestTitle,
            isPresented: Binding(
                get: { pendingLifecycleRequest != nil },
                set: {
                    if !$0 {
                        pendingLifecycleRequest = nil
                    }
                },
            ),
            titleVisibility: .visible,
        ) {
            Button(lifecycleRequestConfirmTitle, role: lifecycleRequestIsDestructive ? .destructive : nil) {
                let request = pendingLifecycleRequest
                pendingLifecycleRequest = nil
                Task { await perform(request) }
            }
            Button("Cancel", role: .cancel) { pendingLifecycleRequest = nil }
        } message: {
            Text(lifecycleRequestMessage)
        }
    }

    private func cycleOverviewCard(_ cycle: TrainingCycle) -> some View {
        CompassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("5/3/1 – Training Cycle")
                            .font(.system(.headline, design: .serif).weight(.bold))
                            .foregroundStyle(CompassPalette.navy)
                        Text("Anchor: \(cycle.week1AnchorDate.iso8601String)")
                            .font(.caption2)
                            .foregroundStyle(CompassPalette.inkMuted)
                    }
                    Spacer()
                    CompassStatusPill(
                        title: cycle.lifecycleState.displayName,
                        color: cycle.lifecycleState == .active
                            ? CompassPalette.green
                            : CompassPalette.blue,
                    )
                }

                HStack(spacing: 6) {
                    ForEach(Array(cycle.weeks.prefix(4))) { week in
                        Text(week.kind.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                week.position == 1 ? Color.white : CompassPalette.navy,
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                week.position == 1
                                    ? CompassPalette.blue
                                    : CompassPalette.paper,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous),
                            )
                    }
                }

                if let firstWeek = cycle.weeks.first {
                    VStack(spacing: 0) {
                        ForEach(firstWeek.sessions.prefix(5)) { session in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.intendedDate.iso8601String)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(CompassPalette.blue)
                                    Text(liftName(session.primaryLiftID))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CompassPalette.navy)
                                    Text(session.status.rawValue.capitalized)
                                        .font(.caption2)
                                        .foregroundStyle(CompassPalette.inkMuted)
                                }
                                Spacer()
                                Image(
                                    systemName: session.status == .completed
                                        ? "checkmark.circle.fill"
                                        : session.status == .scheduled
                                        ? "circle"
                                        : "minus.circle",
                                )
                                .foregroundStyle(
                                    session.status == .completed
                                        ? CompassPalette.green
                                        : session.status == .scheduled
                                        ? CompassPalette.inkMuted
                                        : CompassPalette.red,
                                )
                            }
                            .padding(.vertical, 8)
                            if session.id != firstWeek.sessions.prefix(5).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var defaultPreviewText: String {
        guard let pendingReset else { return "" }
        return pendingReset.after.sessions.map { session in
            "\(session.intendedWeekday.displayName): \(liftName(session.primaryLiftID)) / \(liftName(session.assistanceLiftID))"
        }.joined(separator: "\n")
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedLifts = try await model.scheduleTemplateBoundary.availableLifts()
            lifts = loadedLifts
            let loadedTemplate = try await model.scheduleTemplateBoundary.list()
            template = loadedTemplate
            workingSessions = loadedTemplate.sessions
            draftCycle = try await model.trainingCycleBoundary.draft()
            activeCycle = try await model.trainingCycleBoundary.active()
            if let draftCycle {
                anchorDate = draftCycle.week1AnchorDate.date()
            }
            if let cycle = activeCycle ?? draftCycle {
                cycleAudits = try await model.trainingCycleBoundary.auditHistory(for: cycle.id)
            } else {
                cycleAudits = []
            }
            cycleHistory = try await model.trainingCycleBoundary.history()
        } catch {
            template = nil
            draftCycle = nil
        }
    }

    private var historicalImportDrafts: [HistoricalSessionImportDraft] {
        guard let activeCycle else { return [] }
        let today = TrainingDate(date: Date())
        return activeCycle.weeks.flatMap { week in
            week.sessions.compactMap { session in
                guard session.intendedDate < today,
                      !session.status.isTerminal,
                      let topSet = session.prescriptions.first(where: {
                          $0.role == .primary && $0.isPlusSetEligible
                      })
                else { return nil }
                return HistoricalSessionImportDraft(
                    id: session.id,
                    intendedDate: session.intendedDate,
                    weekName: week.kind.displayName,
                    primaryLiftName: liftName(session.primaryLiftID),
                    topSetWeightKg: topSet.weightKg,
                    minimumRepetitions: topSet.repetitions,
                    repetitions: String(topSet.repetitions),
                )
            }
        }.sorted { $0.intendedDate < $1.intendedDate }
    }

    private func importHistoricalSessions(_ drafts: [HistoricalSessionImportDraft]) async throws {
        for draft in drafts.sorted(by: { $0.intendedDate < $1.intendedDate }) {
            guard let repetitions = Int(draft.repetitions), repetitions >= 0 else { continue }
            _ = try await model.sessionLoggingBoundary.importCompletedSession(
                sessionID: draft.id,
                topSetRepetitions: repetitions,
            )
        }
        await reload()
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
        if case .abandon = pendingLifecycleRequest {
            return true
        }
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
            case let .skipSession(sessionID):
                _ = try await model.trainingCycleBoundary.skipSession(
                    sessionID: sessionID, confirmation: .confirmed,
                )
            case let .skipWeek(weekID):
                _ = try await model.trainingCycleBoundary.skipRemainingSessions(
                    in: weekID, confirmation: .confirmed,
                )
            case let .finishWeek(weekID):
                _ = try await model.trainingCycleBoundary.finishWeek(
                    weekID: weekID, confirmation: .confirmed,
                )
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
                            assistanceLiftID: session.assistanceLiftID,
                        )
                    },
                ),
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
        let deload = if cycle.includesProvisionalDeload {
            "A provisional Deload Week is included."
        } else {
            "No Deload Week is due yet."
        }
        let warning = preview.warning.map { " \($0)" } ?? ""
        let startCopy =
            startsAfterCreation
                ? " Starting snapshots the current Training Maxes and prescriptions for this cycle."
                : " You can edit the draft before starting it."
        return "Week 1 begins \(cycle.week1AnchorDate.iso8601String). The cycle contains "
            + "\(cycle.weeks.count) fixed Training Weeks. \(deload)" + startCopy + warning
    }

    private var cycleConfirmationActionTitle: String {
        switch pendingCycleChange?.action {
        case .created: startsAfterCreation ? "Start Cycle" : "Save Draft"
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
        return "Week 1 remains anchored on \(preview.after.week1AnchorDate.iso8601String). "
            + "The activated cycle stores immutable Training Max snapshots and prescriptions. "
            + deload + warning
    }

    private func reviewCycleCreation(startAfterCreation: Bool = false) async {
        do {
            startsAfterCreation = startAfterCreation
            pendingCycleChange = try await model.trainingCycleBoundary.previewCreate(
                anchorDate: anchorDate,
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
        anchorChoice: TrainingCycleActivationAnchorChoice,
    ) async {
        do {
            pendingCycleActivation = try await model.trainingCycleBoundary.previewActivation(
                anchorChoice: anchorChoice,
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
            let cycle = [activeCycle, draftCycle].compactMap(\.self).first(where: {
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
        if dateChanged, rolesChanged {
            errorMessage =
                "Choose Calendar Change for a date move or Program Edit for lift roles. Save them separately."
            return
        }
        if dateChanged {
            do {
                pendingCycleChange = try await model.trainingCycleBoundary.previewCalendarChange(
                    sessionID: old.id,
                    intendedDate: TrainingDate(date: draft.intendedDate, calendar: .current),
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
            status: old.status,
        )
        var weeks = cycle.weeks
        var sessions = weeks[weekIndex].sessions
        sessions[sessionIndex] = replacement
        weeks[weekIndex] = TrainingWeek(
            id: weeks[weekIndex].id,
            position: weeks[weekIndex].position,
            kind: weeks[weekIndex].kind,
            startDate: weeks[weekIndex].startDate,
            sessions: sessions,
        )
        let request = TrainingCycleEditRequest(
            id: cycle.id,
            week1AnchorDate: cycle.week1AnchorDate,
            weeks: weeks.map { TrainingWeekRequest(cycleWeek: $0) },
        )
        do {
            pendingCycleChange = try await model.trainingCycleBoundary.previewProgramEdit(request)
            showingCycleConfirmation = true
        } catch { errorMessage = String(describing: error) }
    }

    private func confirmCycleChange(_ preview: TrainingCycleChangePreview) async {
        do {
            if preview.action == .created, startsAfterCreation {
                _ = try await model.trainingCycleBoundary.confirm(preview)
                let activation = try await model.trainingCycleBoundary.previewActivation(
                    anchorChoice: .retain,
                )
                _ = try await model.trainingCycleBoundary.confirmActivation(activation)
                pendingCycleChange = nil
                startsAfterCreation = false
                await reload()
                return
            }
            switch preview.action {
            case .calendarChanged:
                _ = try await model.trainingCycleBoundary.confirmCalendarChange(
                    preview, acknowledgeOutsideWeek: true,
                )
            case .programEdited:
                _ = try await model.trainingCycleBoundary.confirmProgramEdit(preview)
            default:
                _ = try await model.trainingCycleBoundary.confirm(preview)
            }
            pendingCycleChange = nil
            startsAfterCreation = false
            await reload()
        } catch {
            pendingCycleChange = nil
            startsAfterCreation = false
            errorMessage = String(describing: error)
        }
    }

    private func confirmCycleDiscard(_: TrainingCycleChangePreview) async {
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
            assistanceLiftID: assistanceLiftID,
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
            assistanceLiftID: liftID,
        )
    }

    private init(
        id: String,
        existingID: String?,
        intendedWeekday: ScheduleWeekday,
        primaryLiftID: String,
        assistanceLiftID: String,
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
        onReview: @escaping (ScheduleSessionDraft) -> Void,
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
            .compassScreen()
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
                                        + "Assistance: \(liftName(session.assistanceLiftID))",
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
    let historicalSessionCount: Int
    let onImportHistory: () -> Void
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
            if historicalSessionCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bring in completed sessions", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(CompassPalette.navy)
                    Text(
                        "\(historicalSessionCount) past session\(historicalSessionCount == 1 ? " is" : "s are") ready for top-set reps from your spreadsheet.",
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Button("Add Past Results") { onImportHistory() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("cycle.import-history")
                }
                .padding(.vertical, 6)
            }
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
                                    "\(session.status.rawValue.capitalized) · Primary: \(liftName(session.primaryLiftID)) · Assistance: \(liftName(session.assistanceLiftID))",
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
        onReview: @escaping (CycleSessionDraft) -> Void,
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
            .compassScreen()
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
                    assistanceLiftID: $0.assistanceLiftID,
                )
            },
        )
    }
}

private extension Array {
    func reordered(fromOffsets offsets: IndexSet, toOffset destination: Int) -> [Element] {
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
        var id: URL {
            url
        }
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
                ForEach(rows.filter { $0.identity.progressionLift != nil }) { item in
                    TMRow(item: item) {
                        draft = TMDraft(item: item)
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                                "\(proposal.currentTrainingMaxKg, specifier: "%.1f") → \(proposal.proposedTrainingMaxKg, specifier: "%.1f") kg · Cycle \(proposal.sourceCycleID)",
                            )
                            .font(.subheadline)
                            Text(
                                "Evidence: \(proposal.evidence.eligibleE1RM.count) eligible e1RM · \(proposal.evidence.excludedWork.count) excluded records",
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
                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .refreshable { await reload() }
        .compassScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .compassTopBarTitle("Training Maxes", subtitle: "5/3/1+ proposals, reviewed by you")
        .compassNavigationTitle("TMs")
        .accessibilityIdentifier("tms.destination")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add custom", systemImage: "plus") {
                        draft = TMDraft.newCustom()
                    }
                    .accessibilityIdentifier("tm.add-custom")
                    Button("Add variant", systemImage: "rectangle.stack.badge.plus") {
                        draft = TMDraft.newVariant()
                    }
                    .accessibilityIdentifier("tm.add-variant")
                    Divider()
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
                .compassScreen()
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
            allowsMultipleSelection: false,
        ) { result in
            if case let .success(urls) = result {
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
                    "Save \(pendingPreview.after.identity.displayName) with Training Max \(pendingPreview.after.trainingMaxKg, specifier: "%.2f") kg and Loading Increment \(pendingPreview.after.loadingIncrementKg, specifier: "%.2f") kg?",
                )
            }
        }
        .alert(
            "Could not save lift",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
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
        _ decision: TrainingMaxProposalDecision,
    ) async {
        do {
            _ = try await model.trainingMaxProposalBoundary.decide(
                proposalID: proposal.id, decision: decision,
            )
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
        .compassScreen()
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
            .compassScreen()
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
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    },
                ),
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
            .compassScreen()
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
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    },
                ),
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
    @State private var deleteHealthKitWriteBacks = false
    @State private var pendingHealthKitDeletion: HealthWorkoutWriteBackDeletionResult?

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
                Section("HealthKit summaries (optional)") {
                    Toggle(
                        "Delete Training Compass HealthKit summaries first",
                        isOn: $deleteHealthKitWriteBacks,
                    )
                    .accessibilityIdentifier("erase.delete-healthkit")
                    Text(TrainingErasureCopy.healthKitChoiceMessage)
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
            .compassScreen()
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
                    confirmationMessage,
                )
            }
            .alert(
                "HealthKit summaries remain",
                isPresented: Binding(
                    get: { pendingHealthKitDeletion != nil },
                    set: {
                        if !$0 {
                            pendingHealthKitDeletion = nil
                        }
                    },
                ),
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Retry") {
                    Task { await erase(deleteHealthKitWriteBacks: true) }
                }
                .accessibilityIdentifier("erase.retry-healthkit")
                Button("Erase Local Data Anyway", role: .destructive) {
                    Task { await erase(deleteHealthKitWriteBacks: false) }
                }
                .accessibilityIdentifier("erase.local-anyway")
            } message: {
                Text(healthKitDeletionFailureMessage)
            }
            .alert(
                "Could not erase app data",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    },
                ),
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? TrainingErasureError.cleanupFailed.privacySafeDescription)
            }
        }
    }

    private func erase() async {
        await erase(deleteHealthKitWriteBacks: deleteHealthKitWriteBacks)
    }

    private func erase(deleteHealthKitWriteBacks: Bool) async {
        isErasing = true
        defer { isErasing = false }
        do {
            let result = try await model.eraseAllData(
                deleteHealthKitWriteBacks: deleteHealthKitWriteBacks,
            )
            switch result {
            case .completed:
                dismiss()
            case let .healthKitDeletionIncomplete(deletion):
                pendingHealthKitDeletion = deletion
            }
        } catch let error as TrainingErasureError {
            errorMessage = error.privacySafeDescription
        } catch {
            errorMessage = TrainingErasureError.cleanupFailed.privacySafeDescription
        }
    }

    private var confirmationMessage: String {
        let healthChoice: String = if deleteHealthKitWriteBacks {
            TrainingErasureCopy.healthKitChoiceMessage
        } else {
            "HealthKit summaries remain outside this local-erasure action."
        }
        return TrainingErasureCopy.confirmationMessage + "\n\n"
            + healthChoice + "\n\n" + TrainingErasureCopy.externalCopiesMessage
    }

    private var healthKitDeletionFailureMessage: String {
        let failure = pendingHealthKitDeletion?.failure?.privacySafeDescription
        return [failure, TrainingErasureCopy.healthKitDeletionFailureMessage]
            .compactMap(\.self)
            .joined(separator: " ")
    }
}

private struct TrainingExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (TrainingExportShareOutcome) -> Void

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            completion(activityType != nil && completed ? .shared : .cancelled)
        }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

private struct TMRow: View {
    let item: LiftConfigurationListItem
    let onEdit: () -> Void

    var body: some View {
        CompassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    CompassRoundSymbol(systemImage: symbol)
                    Text(item.identity.displayName)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(CompassPalette.navy)
                    Spacer()
                    Button(item.configuration == nil ? "Configure" : "Edit", action: onEdit)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("tm.edit.\(item.id)")
                }
                if let configuration = item.configuration {
                    HStack(spacing: 0) {
                        CompassMetricValue(
                            label: "TM",
                            value: String(format: "%.1f kg", configuration.trainingMaxKg),
                        )
                        Divider().frame(height: 36)
                        CompassMetricValue(
                            label: "INCREMENT",
                            value: String(format: "%.2f kg", configuration.loadingIncrementKg),
                        )
                        .padding(.leading, 14)
                        Divider().frame(height: 36)
                        CompassMetricValue(
                            label: "STATUS",
                            value: "Ready",
                            detail: "Local",
                        )
                        .padding(.leading, 14)
                    }
                } else {
                    HStack {
                        CompassMetricValue(label: "TM", value: "Not set")
                        Spacer()
                        CompassStatusPill(title: "Needs setup", color: CompassPalette.inkMuted)
                    }
                }
            }
        }
    }

    private var symbol: String {
        switch item.identity.displayName.lowercased() {
        case let name where name.contains("squat"):
            "figure.strengthtraining.traditional"
        case let name where name.contains("bench"):
            "figure.strengthtraining.functional"
        case let name where name.contains("deadlift"):
            "dumbbell.fill"
        case let name where name.contains("press"):
            "figure.core.training"
        default:
            "scalemass.fill"
        }
    }
}

private struct TMDraft: Identifiable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case variant
        case custom

        var id: String {
            rawValue
        }
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
            isCorrection: isCorrection,
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
        isCorrection: Bool,
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
            isCorrection: false,
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
            isCorrection: false,
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
                        "Training Max is a calculation reference and does not need to align to the Loading Increment.",
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if draft.existingID != nil {
                    Toggle("This is a corrective edit", isOn: $draft.isCorrection)
                }
            }
            .compassScreen()
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
                ZStack(alignment: .bottomTrailing) {
                    CompassBrandMark()
                        .frame(width: 72, height: 72)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(CompassPalette.surface)
                        .frame(width: 34, height: 34)
                        .background(CompassPalette.navy, in: Circle())
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                        .offset(x: 4, y: 4)
                }
                .accessibilityHidden(true)
                Text("Training Compass")
                    .font(.title2.bold())
                Text("Private content concealed")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("privacy.shield")
    }
}
