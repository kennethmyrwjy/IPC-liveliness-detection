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
    @Published var selfieImage: UIImage?

    @Published var isFaceDetected: Bool = false
    @Published var obstructionResult: String = "Initializing..."
    @Published var livenessStatus: LivenessStatus = .pending
    @Published var livenessReport: String = ""

    @Published var verificationStatus: APIVerificationStatus = .pending
    // NEW: Status for the pre-liveness API call (e.g., spoof detection)
    @Published var preLivenessVerificationStatus: PreLivenessVerificationStatus = .pending

    // --- MODIFIED ---
    // The check is now ready as long as a face is in the frame AND pre-liveness check is not processing.
    var isReadyForLivenessCheck: Bool {
        // Corrected comparison for enum with associated values
        if case .processing = preLivenessVerificationStatus {
            return false // If processing, not ready for liveness check
        }
        return isFaceDetected
    }

    var livenessInstruction: String {
        // Corrected comparison for enum with associated values
        if case .processing = preLivenessVerificationStatus {
            return "Performing initial security check..."
        }
        if !isFaceDetected {
            return "No face detected. Please position your face in the circle."
        }
        if obstructionResult != "plain" {
            // This instruction now acts as a secondary warning.
            return "Obstruction Detected: \(obstructionResult)"
        }
        return "Face detected. Ready to start."
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

    // --- MODIFIED ---
    // This function now initiates the *pre-liveness* API check.
    // The actual liveness color flash sequence starts only if this pre-check passes.
    func performPreLivenessVerification() {
        guard let ktp = ktpImage else {
            preLivenessVerificationStatus = .error(message: "Missing KTP image for initial verification.")
            // Consider navigating to result or showing an immediate alert here
            return
        }

        preLivenessVerificationStatus = .processing
        // Optionally, navigate to result or show loading UI

        Task {
            do {
                let response = try await verificationService.performPreLivenessCheck(ktpImage: ktp)
                if !response.isSpoof { // Assuming the API indicates `isSpoof` is false for success
                    preLivenessVerificationStatus = .success
                    // Only start the liveness sequence if the pre-check passes
                    DispatchQueue.main.async { // Ensure UI updates on main thread
                        self.startColorFlashSequence()
                    }
                } else {
                    preLivenessVerificationStatus = .failure(message: "Spoof detected. Please try again.")
                    navigateToResult() // Navigate to result to show failure
                }
            } catch {
                preLivenessVerificationStatus = .error(message: error.localizedDescription)
                navigateToResult() // Navigate to result to show error
            }
        }
    }

    // NEW: Function to explicitly start the color flash sequence
    func startColorFlashSequence() {
        self.livenessStatus = .inProgress
        // LivenessCheckView will observe this status and begin the sequence.
        // `sessionResults` and `currentStep` will be reset within LivenessCheckView
        // when `prepareAndStartLivenessCheck` (now `startColorFlashSequence`) is called there.
    }


    func livenessCheckCompleted(wasSuccessful: Bool, report: String, baselineImage: UIImage?) {
        self.livenessStatus = wasSuccessful ? .success : .failure
        self.livenessReport = report
        self.selfieImage = baselineImage

        if wasSuccessful, let _ = selfieImage, let _ = ktpImage {
            performFinalVerification()
        } else {
            navigateToResult()
        }
    }

    func performFinalVerification() {
        guard let ktp = ktpImage, let selfie = selfieImage else {
            verificationStatus = .error(message: "Missing KTP or selfie image for verification.")
            navigateToResult()
            return
        }

        verificationStatus = .processing
        navigateToResult()

        Task {
            do {
                let response = try await verificationService.verify(ktpImage: ktp, selfieImage: selfie)
                verificationStatus = response.verified ? .success(response: response) : .failure(response: response)
            } catch {
                verificationStatus = .error(message: error.localizedDescription)
            }
        }
    }

    func resetProcess() {
        ktpImage = nil
        selfieImage = nil
        isFaceDetected = false
        obstructionResult = "Initializing..."
        livenessStatus = .pending
        livenessReport = ""
        verificationStatus = .pending
        preLivenessVerificationStatus = .pending // NEW: Reset pre-liveness status
        navigationPath.removeLast(navigationPath.count)
    }
    
    func navigateToLiveness() {
        navigationPath.append("liveness")
    }

    private func navigateToResult() {
        navigationPath.append("result")
    }
}
