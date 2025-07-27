//
//  LivenessCheckView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI
import AVFoundation // Make sure this is imported if not already
import Vision     // Make sure this is imported if not already
import QuartzCore // Make sure this is imported if not already

struct LivenessCheckView: View {
    @EnvironmentObject var viewModel: EKYCViewModel
    
    @State private var flashColor: Color = .black
    // @State private var colorSequence: [Color] = [] // Moved to Coordinator
    // @State private var sessionResults: [(expected: String, detected: String)] = [] // Moved to Coordinator
    // @State private var currentStep = 0 // Moved to Coordinator
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness
    
    // These bindings are correctly used to trigger actions in the CameraView
    @State private var shouldCaptureBaseline: Bool = false
    @State private var shouldCaptureActive: Bool = false

    var body: some View {
        ZStack {
            flashColor
                .ignoresSafeArea()
                .animation(.easeIn(duration: 0.1), value: flashColor)

            VStack(spacing: 20) {
                Text("Step 2: Liveness Check")
                    .font(.largeTitle).fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Position Your Face in the Circle")
                    .font(.headline)
                    .foregroundColor(.white)

                LivenessCameraView(
                    viewModel: viewModel,
                    shouldCaptureBaseline: $shouldCaptureBaseline,
                    shouldCaptureActive: $shouldCaptureActive,
                    onAnalysisComplete: { result in /* Coordinator will call ViewModel directly now */ },
                    onBaselineCaptured: { /* Coordinator will call ViewModel directly now */ },
                    // MODIFIED: Added argument for onFlashColorChange
                    onFlashColorChange: { newColor in
                        self.flashColor = newColor
                    }
                )
                .frame(width: 300, height: 300)
                .clipShape(Circle())
                .overlay(Circle().stroke(viewModel.colorFlashLivenessStatus == .inProgress ? Color.yellow : Color.white, lineWidth: 4))

                // Instruction Text
                VStack {
                    Text(viewModel.livenessInstruction)
                        .font(.headline)
                        .foregroundColor(viewModel.obstructionResult == "plain" ? .green : (viewModel.initialSecurityCheckStatus == .processing ? .white : .orange))
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: viewModel.livenessInstruction)

                    // DEBUG TEXT ADDED HERE:
                    Text("KTP Check Status: \(String(describing: viewModel.initialSecurityCheckStatus))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 5)
                    Text("Face Detected: \(viewModel.isFaceDetected ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    // END DEBUG TEXT
                }
                .frame(minHeight: 60)

                // --- WARNING/ERROR VIEWS ---
                if viewModel.isFaceDetected && viewModel.obstructionResult != "plain" {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Warning: Obstruction detected. Verification may fail.")
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.3))
                    .cornerRadius(8)
                    .transition(.opacity.animation(.easeInOut))
                }
                // Display initial security check failure/error
                else if case .failure(let message) = viewModel.initialSecurityCheckStatus {
                     HStack {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(8)
                    .transition(.opacity.animation(.easeInOut))
                } else if case .error(let message) = viewModel.initialSecurityCheckStatus {
                     HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                        Text("Error: \(message)")
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.3))
                    .cornerRadius(8)
                    .transition(.opacity.animation(.easeInOut))
                }
                else {
                    Spacer().frame(height: 38)
                }
                
                Button(action: {
                    // Start the initial security check on KTP
                    viewModel.performInitialSecurityCheck()
                }) {
                    Text(buttonTextForLiveness())
                        .font(.title2).fontWeight(.bold).foregroundColor(.white).padding()
                        .frame(maxWidth: .infinity)
                        .background(buttonBackgroundColorForLiveness())
                        .cornerRadius(15).shadow(radius: 5)
                }
                // Disable button based on initial check status and liveness status
                .disabled(viewModel.initialSecurityCheckStatus == .processing ||
                          viewModel.colorFlashLivenessStatus == .inProgress ||
                          !viewModel.isFaceDetected || // Requires face detection
                          viewModel.initialSecurityCheckStatus == .success(response: LivenessAPIResponse(liveness_passed: true, confidence: 0.0)) // Disable if already successful (prevent re-trigger)
                         )
                
                Spacer()
            }
            .padding()
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        // Hide back button during any processing or in-progress state
        .navigationBarBackButtonHidden(viewModel.initialSecurityCheckStatus == .processing || viewModel.colorFlashLivenessStatus == .inProgress)
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            // If initial check was already successful, and color flash is pending, start it.
            if case .success(_) = viewModel.initialSecurityCheckStatus, viewModel.colorFlashLivenessStatus == .pending {
                // Now, call the Coordinator's start sequence directly from here.
                // The Coordinator is responsible for initiating its internal state.
                // We will rely on LivenessCameraView's `updateUIViewController`
                // to trigger the Coordinator when `viewModel.colorFlashLivenessStatus` becomes `.inProgress`.
                // So, `viewModel.startColorFlashLiveness()` is the correct trigger from LivenessCheckView.
                viewModel.startColorFlashLiveness()
            }
        }
        .onDisappear {
            UIScreen.main.brightness = originalBrightness
        }
    }
    
    // Helper to determine button text
    private func buttonTextForLiveness() -> String {
        if viewModel.initialSecurityCheckStatus == .processing {
            return "Checking KTP..."
        } else if viewModel.colorFlashLivenessStatus == .inProgress {
            return "Performing Liveness..."
        } else {
            return "Start Liveness Check"
        }
    }

    // Helper to determine button background color
    private func buttonBackgroundColorForLiveness() -> Color {
        if viewModel.initialSecurityCheckStatus == .processing || viewModel.colorFlashLivenessStatus == .inProgress {
            return .gray
        }
        // Button enabled if KTP check is pending AND face is detected
        else if viewModel.initialSecurityCheckStatus == .pending && viewModel.isFaceDetected {
            return .blue
        }
        else {
            return .gray // Disabled state
        }
    }

    // These methods were moved to Coordinator in CameraComponents.swift.
    // The LivenessCheckView's responsibility is now mainly UI and binding to ViewModel.
    // The logic to start/manage the color flash sequence now resides in the Coordinator.
    // The `viewModel.startColorFlashLiveness()` call is the trigger.

    // Removed the now redundant `private func startColorFlashSequence()` from here.
    // Removed the now redundant `private func handleBaselineCapture()` from here.
    // Removed the now redundant `private func handleAnalysisCompletion(result: ...)` from here.
    // Removed the now redundant `private func abortLivenessCheck(reason: ...)` from here.
    // Removed the now redundant `private func endLivenessCheck()` from here.
    // Removed the now redundant `private func colorToString(_ color: Color)` from here.
}
