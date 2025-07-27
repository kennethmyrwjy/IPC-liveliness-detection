//
//  DataModels.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

// MARK: - API Response Structs
struct VerificationResponse: Decodable, Equatable {
    let verified: Bool
    let similarity_score: Double
    let deep_feature_similarity: Double
    let threshold: Double
}

struct LivenessAPIResponse: Decodable, Equatable {
    let liveness_passed: Bool
    let confidence: Double // Your app.py also sends confidence as float
}

struct APIErrorResponse: Decodable, Equatable {
    let error: String
}

// MARK: - Protocols for Services
protocol VerificationServiceProtocol {
    // MODIFIED: Add baseURL to the protocol
    var baseURL: String { get }

    func uploadImage<T: Decodable>(to url: URL, image: UIImage, fieldName: String, responseType: T.Type) async throws -> T
    func uploadTwoImages(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse
}

// MARK: - Enums to Manage UI State in ViewModel
enum FinalVerificationStatus: Equatable {
    case pending
    case processing
    case success(response: VerificationResponse)
    case failure(response: VerificationResponse)
    case error(message: String)
}

enum InitialSecurityCheckStatus: Equatable {
    case pending
    case processing
    case success(response: LivenessAPIResponse)
    case failure(message: String)
    case error(message: String)
}

enum ColorFlashLivenessStatus: Equatable {
    case pending
    case inProgress
    case success(report: String)
    case failure(report: String)
}


// MARK: - Reusable SwiftUI Views for Results
struct VerificationResultView: View {
    let status: FinalVerificationStatus

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
