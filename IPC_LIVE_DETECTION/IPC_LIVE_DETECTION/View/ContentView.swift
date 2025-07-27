//
//  ContentView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

struct ContentView: View {
    // ViewModel is provided via environmentObject from IPC_LIVE_DETECTIONApp.swift
    @EnvironmentObject var viewModel: EKYCViewModel

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            KTPCaptureView()
                .navigationDestination(for: String.self) { route in
                    switch route {
                    case "liveness":
                        LivenessCheckView()
                    case "loadingResult": // NEW: Route to the loading screen
                        LoadingResultView()
                    case "result": // Overall combined result view
                        ResultView()
                    default:
                        Text("Unknown Route")
                    }
                }
        }
    }
}
