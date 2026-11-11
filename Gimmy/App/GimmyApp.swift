import SwiftUI

@main
struct GimmyApp: App {
    @State private var model = AppModel()

    init() {
        RestAlerts.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}
