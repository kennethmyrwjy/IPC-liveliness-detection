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

                // 1. Initial Security Check Result
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Initial Security Check (KTP Image)")
                        .font(.title2).bold()
                    Divider()
                    switch viewModel.initialSecurityCheckStatus {
                    case .pending:
                        Text("Not performed.").foregroundStyle(.secondary)
                    case .processing:
                        ProgressView("Processing KTP image...")
                    case .success(let response):
                        ResultRow(label: "Status", value: "PASSED", icon: "checkmark.shield.fill", color: .green)
                        Text(String(format: "Confidence: %.1f%%", response.confidence ?? 0.0 * 100)).font(.subheadline).foregroundStyle(.secondary)
                    case .failure(let message):
                        ResultRow(label: "Status", value: "FAILED", icon: "xmark.shield.fill", color: .red)
                        Text(message).font(.subheadline)
                    case .error(let message):
                        ResultRow(label: "Status", value: "ERROR", icon: "exclamationmark.triangle.fill", color: .orange)
                        Text(message).font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // 2. Color Flash Liveness Check Result
                VStack(alignment: .leading, spacing: 10) {
                    Text("2. Color Flash Liveness Check (Selfie)")
                        .font(.title2).bold()
                    Divider()
                    switch viewModel.colorFlashLivenessStatus {
                    case .pending:
                        Text("Not performed.").foregroundStyle(.secondary)
                    case .inProgress:
                        ProgressView("Analyzing liveness...")
                    case .success(let report):
                        ResultRow(label: "Status", value: "PASSED", icon: "checkmark.shield.fill", color: .green)
                        Text(report).font(.footnote).foregroundStyle(.secondary)
                    case .failure(let report):
                        ResultRow(label: "Status", value: "FAILED", icon: "xmark.shield.fill", color: .red)
                        Text(report).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // 3. Final API Verification Result (KTP vs Selfie)
                // Only show this if the color flash liveness passed
                if case .success(_) = viewModel.colorFlashLivenessStatus {
                    VerificationResultView(status: viewModel.finalVerificationStatus)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("3. Final API Verification (KTP vs Selfie)")
                            .font(.title2).bold()
                        Divider()
                        Text("Awaiting successful liveness check...").foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
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
