import SwiftUI

@main
struct IPC_LIVE_DETECTIONApp: App {
    // Create an instance of your ACTUAL ViewModel here.
    // EKYCViewModel is a class that conforms to ObservableObject.
    @StateObject private var viewModel = EKYCViewModel()

    var body: some Scene {
        WindowGroup {
            // Your ContentView is the main UI.
            ContentView()
                // Pass the single viewModel instance into the environment
                // so all child views (like KTPCaptureView, etc.) can access it.
                .environmentObject(viewModel)
        }
    }
}
