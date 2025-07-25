//
//  ResultView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

struct ResultView: View {
    @EnvironmentObject var viewModel: EKYCViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                Text("Verification Results")
                    .font(.largeTitle).fontWeight(.bold)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Liveness Check")
                        .font(.title2).bold()
                    Divider()
                    HStack {
                        Image(systemName: viewModel.livenessStatus == .success ? "checkmark.shield.fill" : "xmark.shield.fill")
                            .font(.largeTitle)
                            .foregroundColor(viewModel.livenessStatus == .success ? .green : .red)
                        Text(viewModel.livenessStatus == .success ? "PASSED" : "FAILED")
                            .font(.title3).bold()
                            .foregroundColor(viewModel.livenessStatus == .success ? .green : .red)
                    }
                    Text(viewModel.livenessReport)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                if viewModel.livenessStatus == .success {
                    VerificationResultView(status: viewModel.verificationStatus)
                }
                
                Button(action: {
                    viewModel.resetProcess()
                }) {
                    Label("Start Over", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }
}
