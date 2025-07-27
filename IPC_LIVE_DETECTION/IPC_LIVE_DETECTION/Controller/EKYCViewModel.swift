//
//  EKYCViewModel.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI
import AVFoundation
import CoreML
import Vision

@MainActor
class EKYCViewModel: ObservableObject {
    @Published var navigationPath = NavigationPath()
    @Published var ktpImage: UIImage?
    @Published var selfieImage: UIImage? // This will be the baseline selfie for liveness & final verification

    @Published var isFaceDetected: Bool = false // From LivenessCameraView
    @Published var obstructionResult: String = "Initializing..." // From LivenessCameraView

    // Stages of the EKYC process
    @Published var initialSecurityCheckStatus: InitialSecurityCheckStatus = .pending // For KTP image
    @Published var colorFlashLivenessStatus: ColorFlashLivenessStatus = .pending // For the interactive liveness
    @Published var finalVerificationStatus: FinalVerificationStatus = .pending // For KTP vs Selfie

    // Computed property to control LivenessCheckView's button
    var isReadyForColorFlashLiveness: Bool {
        // Use if case for comparing InitialSecurityCheckStatus
        if case .success = initialSecurityCheckStatus {
            return isFaceDetected // Only if initial check succeeded and face is detected
        }
        return false // Not ready if initial check hasn't succeeded
    }

    // Dynamic instruction text for LivenessCheckView
    var livenessInstruction: String {
        // MODIFIED: Use a switch statement for cleaner handling of multiple enum cases
        switch initialSecurityCheckStatus {
        case .processing:
            return "Performing initial security check on KTP..."
        case .failure, .error: // Handles both .failure and .error cases
            return "Initial security check failed. Please reset and try again."
        default: // Covers .pending and .success states
            break // Fall through to subsequent checks if not processing, failure, or error
        }

        if !isFaceDetected {
            return "No face detected. Please position your face in the circle."
        }
        if obstructionResult != "plain" {
            return "Warning: Obstruction detected. Verification may fail. (\(obstructionResult))"
        }
        return "Face detected. Ready to start color flash."
    }

    private let verificationService: VerificationServiceProtocol
    let obstructionModel: VNCoreMLModel

    init(service: VerificationServiceProtocol = VerificationService()) {
        self.verificationService = service
        do {
            self.obstructionModel = try VNCoreMLModel(for: model_obstruction().model)
        } catch {
            fatalError("Failed to load the model_obstruction Core ML model: \(error)")
        }
    }

    // MARK: - Process Flow Control

    // Step 1: Initiates the initial security check on the KTP image
    func performInitialSecurityCheck() {
        guard let ktp = ktpImage else {
            initialSecurityCheckStatus = .error(message: "KTP image is missing to start security check.")
            return
        }

        initialSecurityCheckStatus = .processing
        Task {
            do {
                let response = try await verificationService.uploadImage(
                    to: URL(string: verificationService.baseURL + "/api/liveness")!, // Direct call to liveness API for KTP
                    image: ktp,
                    fieldName: "image", // Matches API expectation
                    responseType: LivenessAPIResponse.self
                )
                
                if response.liveness_passed {
                    initialSecurityCheckStatus = .success(response: response)
                    // If KTP check passes, prepare for color flash liveness (handled by LivenessCheckView's onAppear)
                } else {
                    initialSecurityCheckStatus = .failure(message: "KTP image failed initial liveness/spoof check. Score: \(response.confidence ?? 0.0)")
                    // Navigate to result to show initial failure
                    navigateToResult()
                }
            } catch {
                initialSecurityCheckStatus = .error(message: error.localizedDescription)
                navigateToResult()
            }
        }
    }

    // Step 2: Initiates the color flash sequence (called by LivenessCheckView when ready)
    func startColorFlashLiveness() {
        self.colorFlashLivenessStatus = .inProgress
        // LivenessCheckView observes this and begins the sequence.
    }

    // Step 2.1: Callback from LivenessCameraView when color flash liveness is complete
    func colorFlashLivenessCompleted(wasSuccessful: Bool, report: String, baselineImage: UIImage?) {
        self.colorFlashLivenessStatus = wasSuccessful ? .success(report: report) : .failure(report: report)
        self.selfieImage = baselineImage // Store the selfie captured during liveness check

        if wasSuccessful, let _ = selfieImage, let _ = ktpImage {
            performFinalVerification() // Proceed to final verification
        } else {
            // If liveness failed or images are missing, go to result view
            navigateToResult()
        }
    }

    // Step 3: Performs the final KTP-Selfie similarity verification
    func performFinalVerification() {
        guard let ktp = ktpImage, let selfie = selfieImage else {
            finalVerificationStatus = .error(message: "Missing KTP or selfie image for final verification.")
            navigateToResult()
            return
        }

        finalVerificationStatus = .processing
        // Optionally navigate to result early to show "processing"
        navigateToResult()

        Task {
            do {
                let response = try await verificationService.uploadTwoImages(ktpImage: ktp, selfieImage: selfie) // Using the new service method
                finalVerificationStatus = response.verified ? .success(response: response) : .failure(response: response)
            } catch {
                finalVerificationStatus = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Navigation & Reset
    func resetProcess() {
        ktpImage = nil
        selfieImage = nil
        isFaceDetected = false
        obstructionResult = "Initializing..."
        initialSecurityCheckStatus = .pending
        colorFlashLivenessStatus = .pending
        finalVerificationStatus = .pending
        navigationPath.removeLast(navigationPath.count) // Go back to root
    }
    
    func navigateToLiveness() {
        navigationPath.append("liveness")
    }

    private func navigateToResult() {
        navigationPath.append("result")
    }
}
