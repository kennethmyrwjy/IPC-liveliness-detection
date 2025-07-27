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
                Text("Overall Verification Results")
                    .font(.largeTitle).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                // Display Overall Process Status
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overall Process Status")
                        .font(.title2).bold()
                    Divider()
                    switch viewModel.overallProcessStatus {
                    case .pending, .processing:
                        ProgressView("Compiling all results...")
                    case .complete(let isSuccessful):
                        ResultRow(label: "Status", value: isSuccessful ? "COMPLETED SUCCESSFULLY" : "FAILED", icon: isSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill", color: isSuccessful ? .green : .red)
                    case .error(let message):
                        ResultRow(label: "Status", value: "OVERALL ERROR", icon: "exclamationmark.triangle.fill", color: .orange)
                        Text(message).font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // 1. Liveness API Check Result (on auto-snapped selfie)
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Liveness API Check (Selfie)")
                        .font(.title2).bold()
                    Divider()
                    // MODIFIED: Use SelfieLivenessCheckAPIStatus
                    switch viewModel.livenessAPICallStatus {
                    case .pending:
                        Text("Not performed yet.").foregroundStyle(.secondary)
                    case .processing:
                        ProgressView("Analyzing selfie with Liveness API...")
                    case .success(let response):
                        ResultRow(label: "Status", value: "LIVENESS PASSED", icon: "checkmark.shield.fill", color: .green)
                        Text(String(format: "Confidence: %.1f%%", response.confidence * 100)).font(.footnote).foregroundStyle(.secondary)
                    case .failure(let message):
                        ResultRow(label: "Status", value: "LIVENESS FAILED", icon: "xmark.shield.fill", color: .red)
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    case .error(let message):
                        ResultRow(label: "Status", value: "API ERROR", icon: "exclamationmark.triangle.fill", color: .orange)
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)


                // 2. Similarity Verification Check Result (KTP + auto-snapped selfie)
                VStack(alignment: .leading, spacing: 10) {
                    Text("2. Similarity Verification (KTP vs Selfie)")
                        .font(.title2).bold()
                    Divider()
                    switch viewModel.verificationAPICallStatus {
                    case .pending:
                        Text("Not performed yet.").foregroundStyle(.secondary)
                    case .processing:
                        ProgressView("Verifying KTP and Selfie...")
                    case .success(let response):
                        ResultRow(label: "Status", value: "MATCH FOUND", icon: "checkmark.shield.fill", color: .green)
                        ResultRow(label: "Similarity Score", value: String(format: "%.2f%%", response.similarity_score * 100))
                    case .failure(let response):
                        ResultRow(label: "Status", value: "NO MATCH", icon: "xmark.shield.fill", color: .red)
                        ResultRow(label: "Similarity Score", value: String(format: "%.2f%%", response.similarity_score * 100))
                    case .error(let message):
                        ResultRow(label: "Status", value: "API ERROR", icon: "exclamationmark.triangle.fill", color: .orange)
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // 3. Color Flash Liveness Check Result (Interactive Liveness)
                VStack(alignment: .leading, spacing: 10) {
                    Text("3. Interactive Color Flash Liveness")
                        .font(.title2).bold()
                    Divider()
                    switch viewModel.colorFlashLivenessStatus {
                    case .pending:
                        Text("Not performed yet.").foregroundStyle(.secondary)
                    case .inProgress:
                        ProgressView("Analyzing color flash...")
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
