//
//  LoadingResultView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

struct LoadingResultView: View {
    @EnvironmentObject var viewModel: EKYCViewModel
    @State private var showFinalResult = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if viewModel.overallProcessStatus.isProcessing {
                ProgressView("Analyzing results...")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
            } else { // It's finished (complete or error)
                Image(systemName: viewModel.overallProcessStatus.isComplete && (viewModel.overallProcessStatus == .complete(isSuccessful: true)) ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(viewModel.overallProcessStatus.isComplete && (viewModel.overallProcessStatus == .complete(isSuccessful: true)) ? .green : .red)
                Text("Analysis Complete!")
                    .font(.title2)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .navigationBarBackButtonHidden(true) // Prevent going back
        .onChange(of: viewModel.overallProcessStatus) { _, newStatus in // New iOS 17+ onChange syntax
            // Trigger navigation when overallProcessStatus becomes complete or error
            if newStatus.isComplete || newStatus.isError {
                DispatchQueue.main.async { // Defer state change to next run loop
                    self.showFinalResult = true
                }
            }
        }
        .navigationDestination(isPresented: $showFinalResult) {
            ResultView()
        }
    }
}
