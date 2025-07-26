//
//  LivenessCheckView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

struct LivenessCheckView: View {
    @EnvironmentObject var viewModel: EKYCViewModel
    
    @State private var flashColor: Color = .black
    @State private var colorSequence: [Color] = []
    @State private var sessionResults: [(expected: String, detected: String)] = []
    @State private var currentStep = 0
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness
    
    @State private var shouldCaptureBaselineAndDetectFace = false
    @State private var shouldCaptureActive = false

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
                    shouldCaptureBaseline: $shouldCaptureBaselineAndDetectFace,
                    shouldCaptureActive: $shouldCaptureActive,
                    onAnalysisComplete: handleAnalysisCompletion,
                    onBaselineCaptured: handleBaselineCapture
                )
                .frame(width: 300, height: 300)
                .clipShape(Circle())
                .overlay(Circle().stroke(viewModel.livenessStatus == .inProgress ? Color.yellow : Color.white, lineWidth: 4))

                // Instruction Text - Updated based on preLivenessVerificationStatus
                VStack {
                    Text(viewModel.livenessInstruction)
                        .font(.headline)
                        .foregroundColor(viewModel.obstructionResult == "plain" ? .green : (viewModel.preLivenessVerificationStatus == .processing ? .white : .orange)) // Corrected
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: viewModel.livenessInstruction)
                }
                .frame(minHeight: 60)

                // --- NEW WARNING/ERROR VIEWS ---
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
                } else if case .failure(let message) = viewModel.preLivenessVerificationStatus {
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
                } else if case .error(let message) = viewModel.preLivenessVerificationStatus {
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
                    // Add a spacer to prevent the button from jumping up and down
                    Spacer().frame(height: 38)
                }
                
                Button(action: {
                    // Call the new pre-liveness verification function in ViewModel
                    viewModel.performPreLivenessVerification()
                }) {
                    Text(viewModel.preLivenessVerificationStatus == .processing ? "Checking..." : (viewModel.livenessStatus == .inProgress ? "Checking..." : "Start Liveness Check"))
                        .font(.title2).fontWeight(.bold).foregroundColor(.white).padding()
                        .frame(maxWidth: .infinity)
                        .background(viewModel.isReadyForLivenessCheck ? Color.blue : Color.gray)
                        .cornerRadius(15).shadow(radius: 5)
                }
                // The button is now disabled if not ready, or if initial check or liveness is in progress.
                .disabled(!viewModel.isReadyForLivenessCheck || viewModel.preLivenessVerificationStatus == .processing || viewModel.livenessStatus == .inProgress) // Reverted back to ==
                
                Spacer()
            }
            .padding()
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        // Hide back button during processing states
        .navigationBarBackButtonHidden(viewModel.livenessStatus == .inProgress || viewModel.preLivenessVerificationStatus == .processing) // Reverted back to ==
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            // If the viewModel indicates a successful pre-liveness check and pending liveness,
            // it means we navigated back and forth, so we should re-start the color sequence
            // if we were already past the pre-liveness check.
            if viewModel.preLivenessVerificationStatus == .success && viewModel.livenessStatus == .pending { // Reverted back to ==
                startColorFlashSequence()
            }
        }
        .onDisappear {
            UIScreen.main.brightness = originalBrightness
        }
    }
    
    // This function is now called by the ViewModel when it's time to start the actual color sequence
    private func startColorFlashSequence() {
        sessionResults.removeAll()
        currentStep = 0
        UIScreen.main.brightness = 1.0
        generateColorSequence()
        shouldCaptureBaselineAndDetectFace = true
    }
    
    private func generateColorSequence() {
        let possibleColors: [Color] = [Color(UIColor.cyan), Color(UIColor.magenta), .yellow]
        self.colorSequence = (0..<6).map { _ in possibleColors.randomElement()! }
    }
    
    private func handleBaselineCapture() {
        executeNextFlashStep()
    }

    private func handleAnalysisCompletion(result: (cyan: Float, magenta: Float, yellow: Float)) {
        self.flashColor = .black
        
        guard result.cyan != -1 else {
            abortLivenessCheck(reason: "Liveness check failed: No face was detected during the process.")
            return
        }

        var detectedColor = "Inconclusive"
        if result.cyan > result.magenta && result.cyan > result.yellow { detectedColor = "Cyan" }
        else if result.magenta > result.cyan && result.magenta > result.yellow { detectedColor = "Magenta" }
        else if result.yellow > result.cyan && result.yellow > result.magenta { detectedColor = "Yellow" }
        
        let expectedColor = colorToString(colorSequence[currentStep])
        self.sessionResults.append((expected: expectedColor, detected: detectedColor))
        
        self.currentStep += 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            executeNextFlashStep()
        }
    }

    private func executeNextFlashStep() {
        guard currentStep < colorSequence.count else {
            endLivenessCheck()
            return
        }
        
        self.flashColor = self.colorSequence[currentStep]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.shouldCaptureActive = true
        }
    }
    
    private func abortLivenessCheck(reason: String) {
        UIScreen.main.brightness = originalBrightness
        let report = "Liveness Failed:\n\(reason)"
        viewModel.livenessCheckCompleted(wasSuccessful: false, report: report, baselineImage: nil)
        viewModel.preLivenessVerificationStatus = .pending // Reset pre-liveness status to allow retry from the start
    }
    
    private func endLivenessCheck() {
        UIScreen.main.brightness = originalBrightness
        self.flashColor = .black
        
        var report = "Liveness Analysis Complete:\n\n"
        var successCount = 0
        for (index, result) in sessionResults.enumerated() {
            let status = result.expected.lowercased() == result.detected.lowercased() ? "✅" : "❌"
            if status == "✅" { successCount += 1 }
            report += "Flash \(index + 1): Expected \(result.expected), Detected \(result.detected) \(status)\n"
        }
        
        let wasSuccessful = successCount >= 4
        let finalStatus = wasSuccessful ? "Liveness Confirmed" : "Liveness Failed"
        report += "\nFinal Result: \(finalStatus)"
        
        viewModel.livenessCheckCompleted(
            wasSuccessful: wasSuccessful,
            report: report,
            baselineImage: viewModel.selfieImage
        )
    }

    private func colorToString(_ color: Color) -> String {
        switch color {
        case Color(UIColor.cyan): return "Cyan"
        case Color(UIColor.magenta): return "Magenta"
        case .yellow: return "Yellow"
        default: return "Unknown"
        }
    }
}
