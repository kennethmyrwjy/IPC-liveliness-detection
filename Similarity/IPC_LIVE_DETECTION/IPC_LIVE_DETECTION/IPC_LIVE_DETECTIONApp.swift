import SwiftUI

@main
struct IPC_LIVE_DETECTIONApp: App {
    @StateObject private var viewModel = VerificationViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView() // Main entry point to the UI
                .environmentObject(viewModel) // Make the view model available across the app
        }
    }
}
