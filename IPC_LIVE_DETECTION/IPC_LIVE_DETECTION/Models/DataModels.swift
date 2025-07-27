//
//  DataModels.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

protocol VerificationServiceProtocol {
    func verify(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse
    // Add new method for spoof/pre-liveness verification
    func performPreLivenessCheck(ktpImage: UIImage) async throws -> SpoofDetectionResponse // Example
}

struct VerificationResponse: Decodable {
    let verified: Bool
    let similarity_score: Double
    let deep_feature_similarity: Double
    let threshold: Double
}

// MODIFIED: To match the /api/liveness endpoint response from app.py
struct SpoofDetectionResponse: Decodable, Equatable { // Keep Equatable for comparisons
    let liveness_passed: Bool // Changed from isSpoof to liveness_passed
    let confidence: Double?   // Matches 'confidence' key from app.py
}

struct APIErrorResponse: Decodable {
    let error: String
}

enum APIVerificationStatus {
    case pending
    case processing
    case success(response: VerificationResponse)
    case failure(response: VerificationResponse)
    case error(message: String)
}

enum LivenessStatus {
    case pending
    case inProgress
    case success
    case failure
}

// MODIFIED: Make PreLivenessVerificationStatus Equatable to allow comparison operators
enum PreLivenessVerificationStatus: Equatable {
    case pending
    case processing
    case success
    case failure(message: String)
    case error(message: String)
}

struct VerificationResultView: View {
    let status: APIVerificationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API Verification")
                .font(.title2).bold()
            Divider()

            switch status {
            case .pending:
                Text("Awaiting liveness check completion...").foregroundStyle(.secondary)
            case .processing:
                ProgressView("Verifying with server...")
            case .success(let response):
                ResultRow(label: "Status", value: "VERIFIED", icon: "checkmark.shield.fill", color: .green)
                ResultRow(label: "Similarity Score", value: String(format: "%.2f%%", response.similarity_score * 100))
            case .failure(let response):
                ResultRow(label: "Status", value: "NOT VERIFIED", icon: "xmark.shield.fill", color: .red)
                ResultRow(label: "Similarity Score", value: String(format: "%.2f%%", response.similarity_score * 100))
            case .error(let message):
                ResultRow(label: "Status", value: "ERROR", icon: "exclamationmark.triangle.fill", color: .orange)
                Text(message).font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ResultRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let icon = icon {
                Image(systemName: icon).foregroundColor(color)
            }
            Text(value).bold().foregroundColor(color)
        }
    }
}
