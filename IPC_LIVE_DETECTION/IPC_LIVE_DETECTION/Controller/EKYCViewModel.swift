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
    @Published var selfieImage: UIImage? // This will be the baseline selfie from color flash

    @Published var isFaceDetected: Bool = false
    @Published var obstructionResult: String = "Initializing..."

    // API Result containers (hold the actual response objects)
    @Published var livenessAPIResult: LivenessAPIResponse?
    @Published var verificationAPIResult: VerificationResponse?

    // Statuses for each concurrent branch (reflect processing/success/failure/error)
    @Published var colorFlashLivenessStatus: ColorFlashLivenessProcessStatus = .pending // Status for the interactive color flash
    @Published var livenessAPICallStatus: SelfieLivenessAPICallStatus = .pending // Status for the /api/liveness call on selfie
    @Published var verificationAPICallStatus: VerificationAPICallStatus = .pending // Status for the /api/verify call (KTP+Selfie)

    // Overall process status (combines all three concurrent branches' completion)
    @Published var overallProcessStatus: OverallProcessStatus = .pending


    // Computed property for LivenessCheckView button enablement
    var isReadyForLivenessCheck: Bool {
        // Button enabled if face is detected and no liveness flow is currently in progress
        return isFaceDetected && colorFlashLivenessStatus.isPending &&
               livenessAPICallStatus.isPending && verificationAPICallStatus.isPending
    }

    var livenessInstruction: String {
        if overallProcessStatus.isProcessing {
            return "Processing results..."
        }
        if !isFaceDetected {
            return "No face detected. Please position your face in the circle."
        }
        if obstructionResult != "plain" {
            return "Warning: Obstruction detected: \(obstructionResult)"
        }
        if colorFlashLivenessStatus.isPending {
            return "Face detected. Ready to start color flash."
        }
        if colorFlashLivenessStatus.isProcessing {
            return "Performing color flash..."
        }
        if colorFlashLivenessStatus.isFinished { // If color flash is done
            return "Color flash complete. Waiting for analysis..."
        }
        return "Initializing..." // Default
    }

    private let verificationService: VerificationServiceProtocol
    let obstructionModel: VNCoreMLModel

    init(service: VerificationServiceProtocol = VerificationService()) {
        self.verificationService = service
        do {
            let modelConfiguration = MLModelConfiguration()
            self.obstructionModel = try VNCoreMLModel(for: model_obstruction(configuration: modelConfiguration).model)
        } catch {
            fatalError("Failed to load the model_obstruction Core ML model: \(error)")
        }
    }

    // MARK: - Core Workflow Functions

    // Triggered by LivenessCheckView button. Captures selfie and starts color flash.
    // API calls are triggered AFTER color flash is complete.
    func startLivenessProcess(snappedSelfie: UIImage) {
        self.selfieImage = snappedSelfie // Store the baseline selfie
        self.colorFlashLivenessStatus = .inProgress // Start the color flash process
        // Color flash will now run. API calls will start in colorFlashSequenceCompleted.
    }

    // Called by LivenessCameraView.Coordinator when color flash sequence is done
    func colorFlashSequenceCompleted(wasSuccessful: Bool, report: String, snappedSelfie: UIImage?) {
        DispatchQueue.main.async { // Ensure update on MainActor
            self.colorFlashLivenessStatus = wasSuccessful ? .success(report: report) : .failure(report: report)
            // Ensure selfieImage is correctly set here if it wasn't already (e.g., if it was passed via snappedSelfie)
            if self.selfieImage == nil {
                self.selfieImage = snappedSelfie
            }

            // Navigate to the loading screen immediately after color flash finishes
            self.navigateToLoadingResult()

            // Trigger concurrent API calls ONLY IF selfie and KTP are available (regardless of color flash success)
            if let selfie = snappedSelfie, let ktp = self.ktpImage {
                self.overallProcessStatus = .processing // Indicate API processing has begun
                Task {
                    await self.performConcurrentAPIChecks(ktp: ktp, selfie: selfie)
                    // The overallProcessStatus will be set to complete/error inside performConcurrentAPIChecks or its sub-calls.
                }
            } else {
                // If selfie or KTP is missing (which shouldn't happen if flow is correct), deem APIs as errored
                self.livenessAPICallStatus = .error(message: "Selfie or KTP missing for API calls.")
                self.verificationAPICallStatus = .error(message: "Selfie or KTP missing for API calls.")
                self.overallProcessStatus = .complete(isSuccessful: false) // Mark overall failed due to missing input
            }
        }
    }

    // Performs both API checks concurrently (called after color flash is done)
    private func performConcurrentAPIChecks(ktp: UIImage, selfie: UIImage) async {
        await withTaskGroup(of: Void.self) { group in
            // Branch 1: Liveness API call (selfie only)
            group.addTask { await self.performLivenessAPICall(selfie: selfie) }

            // Branch 2: Verification API call (KTP + selfie)
            group.addTask { await self.performVerificationAPICall(ktp: ktp, selfie: selfie) }
            
            await group.waitForAll() // Wait for both API calls to finish

            // After APIs are done, determine overall process status
            self.determineOverallProcessCompletion()
        }
    }

    // Individual concurrent API call for /api/liveness
    private func performLivenessAPICall(selfie: UIImage) async {
        livenessAPICallStatus = .processing
        do {
            let response = try await verificationService.performLivenessAPI(selfieImage: selfie)
            livenessAPIResult = response // Store the actual response object
            livenessAPICallStatus = response.liveness_passed ? .success(response: response) : .failure(message: "Selfie Liveness failed with confidence: \(response.confidence)")
        } catch {
            livenessAPICallStatus = .error(message: error.localizedDescription)
        }
    }

    // Individual concurrent API call for /api/verify
    private func performVerificationAPICall(ktp: UIImage, selfie: UIImage) async {
        verificationAPICallStatus = .processing
        do {
            let response = try await verificationService.performVerificationAPI(ktpImage: ktp, selfieImage: selfie)
            verificationAPIResult = response // Store the actual response object
            verificationAPICallStatus = response.verified ? .success(response: response) : .failure(response: response)
        } catch {
            verificationAPICallStatus = .error(message: error.localizedDescription)
        }
    }

    // Determines overall process completion (called after APIs are done)
    private func determineOverallProcessCompletion() {
        DispatchQueue.main.async { // Ensure update on MainActor
            // All three branches (color flash + 2 APIs) are finished by this point.
            // Determine overall success based on combined results.
            
            let allSucceeded = self.colorFlashLivenessStatus.isSuccess &&
                               self.livenessAPICallStatus.isSuccess &&
                               self.verificationAPICallStatus.isSuccess

            let anyBranchErrored = self.livenessAPICallStatus.isError || self.verificationAPICallStatus.isError
            let anyBranchFailed = self.colorFlashLivenessStatus.isFailure || self.livenessAPICallStatus.isFailure || self.verificationAPICallStatus.isFailure

            if anyBranchErrored {
                self.overallProcessStatus = .complete(isSuccessful: false)
            } else if anyBranchFailed {
                self.overallProcessStatus = .complete(isSuccessful: false)
            } else {
                self.overallProcessStatus = .complete(isSuccessful: allSucceeded)
            }
            // MODIFIED: Removed navigateToResult() call here.
            // LoadingResultView will observe overallProcessStatus and trigger navigation.
        }
    }

    // MARK: - Navigation & Reset

    func resetProcess() {
        ktpImage = nil
        self.selfieImage = nil
        isFaceDetected = false
        obstructionResult = "Initializing..."
        livenessAPIResult = nil
        verificationAPIResult = nil
        colorFlashLivenessStatus = .pending
        livenessAPICallStatus = .pending
        verificationAPICallStatus = .pending
        overallProcessStatus = .pending
        navigationPath.removeLast(navigationPath.count) // Go back to root (KTPCaptureView)
    }
    
    func navigateToLiveness() {
        navigationPath.append("liveness")
    }

    private func navigateToLoadingResult() {
        navigationPath.append("loadingResult")
    }

    private func navigateToResult() {
        navigationPath.append("result")
    }
}
