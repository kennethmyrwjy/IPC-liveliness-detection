//
//  ContentView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = EKYCViewModel()

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            KTPCaptureView()
                .navigationDestination(for: String.self) { route in
                    switch route {
                    case "liveness":
                        LivenessCheckView()
                    case "result":
                        ResultView()
                    default:
                        Text("Unknown Route")
                    }
                }
        }
        .environmentObject(viewModel)
    }
}
