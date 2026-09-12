import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            // FB1: iPhone — detail-column NavigationStack breaks pushes on compact.
            // FB2: iPad, landscape — switch-while-pushed detaches the incoming root.
            // Swap the view to match the report being reproduced.
            FB1ReproView()
            // FB2ReproView()
        }
    }
}
