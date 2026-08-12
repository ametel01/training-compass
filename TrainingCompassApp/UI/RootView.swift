import SwiftUI

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
          UnavailableDestinationView(
            title: "TMs",
            systemImage: "scalemass",
            detail: "Training Maxes become available in Local Training Core."
          )
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
        Text("This engineering foundation is not approved for owner training or Health data.")
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
