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

    // --- MODIFIED ---
    // The check is now ready as long as a face is in the frame.
    // The UI will handle showing a warning for obstructions.
    var isReadyForLivenessCheck: Bool {
        isFaceDetected
    }

    var livenessInstruction: String {
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

    // ... rest of the file is unchanged ...
    func startLivenessCheck() {
        self.livenessStatus = .inProgress
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
        navigationPath.removeLast(navigationPath.count)
    }
    
    func navigateToLiveness() {
        navigationPath.append("liveness")
    }

    private func navigateToResult() {
        navigationPath.append("result")
    }
}
