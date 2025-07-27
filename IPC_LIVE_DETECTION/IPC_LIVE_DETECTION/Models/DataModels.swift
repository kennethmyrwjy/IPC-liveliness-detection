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
    let confidence: Double
}

struct APIErrorResponse: Decodable, Equatable {
    let error: String
}

// MARK: - Protocols for Services
protocol VerificationServiceProtocol {
    var baseURL: String { get } // Base URL for API calls

    func performLivenessAPI(selfieImage: UIImage) async throws -> LivenessAPIResponse // For /api/liveness endpoint
    func performVerificationAPI(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse // For /api/verify endpoint
}

// MARK: - Enums to Manage UI State in ViewModel

// Status for the /api/liveness call on selfie
enum SelfieLivenessAPICallStatus: Equatable {
    case pending
    case processing
    case success(response: LivenessAPIResponse) // Associated response is LivenessAPIResponse
    case failure(message: String) // Message for API-determined failure
    case error(message: String)   // Message for network/decoding error

    // Helper computed properties for easy checks
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
    var isFailure: Bool { if case .failure = self { return true } else { return false } }
    var isError: Bool { if case .error = self { return true } else { return false } }
    var isFinished: Bool { return isSuccess || isFailure || isError }
    var isProcessing: Bool { if case .processing = self { return true } else { return false } }
    var isPending: Bool { if case .pending = self { return true } else { return false } } // ADDED THIS
}

// Status for the /api/verify call (KTP+Selfie)
enum VerificationAPICallStatus: Equatable {
    case pending
    case processing
    case success(response: VerificationResponse) // Associated response is VerificationResponse
    case failure(response: VerificationResponse) // Failure includes original response for details
    case error(message: String)

    // Helper computed properties for easy checks
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
    var isFailure: Bool { if case .failure = self { return true } else { return false } }
    var isError: Bool { if case .error = self { return true } else { return false } }
    var isFinished: Bool { return isSuccess || isFailure || isError }
    var isProcessing: Bool { if case .processing = self { return true } else { return false } }
    var isPending: Bool { if case .pending = self { return true } else { return false } } // ADDED THIS
}

// Status for the interactive Color Flash liveness process
enum ColorFlashLivenessProcessStatus: Equatable {
    case pending
    case inProgress
    case success(report: String) // Store detailed report
    case failure(report: String) // Store detailed report

    // Helper computed properties for easy checks
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
    var isFailure: Bool { if case .failure = self { return true } else { return false } }
    var isFinished: Bool { return isSuccess || isFailure } // A process is finished if it succeeded or failed
    var isProcessing: Bool { if case .inProgress = self { return true } else { return false } } // Color flash uses 'inProgress' for processing
    var isPending: Bool { if case .pending = self { return true } else { return false } } // ADDED THIS
}

// Overall process status (combines all three concurrent branches)
enum OverallProcessStatus: Equatable {
    case pending
    case processing
    case complete(isSuccessful: Bool)
    case error(message: String)

    // Helper computed properties
    var isPending: Bool { if case .pending = self { return true } else { return false } }
    var isProcessing: Bool { if case .processing = self { return true } else { return false } }
    var isComplete: Bool { if case .complete = self { return true } else { return false } }
    var isError: Bool { if case .error = self { return true } else { return false } }
    var isFinished: Bool { return isComplete || isError }
}


// MARK: - Reusable SwiftUI Views for Results
struct VerificationResultView: View {
    let status: VerificationAPICallStatus // Uses VerificationAPICallStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Similarity Verification")
                .font(.title2).bold()
            Divider()

            switch status {
            case .pending:
                Text("Waiting for input...").foregroundStyle(.secondary)
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
