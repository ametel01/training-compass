import SwiftUI

@main
struct TrainingCompassApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView(
                model: model,
                concealsSensitiveContent: scenePhase != .active || model.isErasing,
            )
        }
    }
}
