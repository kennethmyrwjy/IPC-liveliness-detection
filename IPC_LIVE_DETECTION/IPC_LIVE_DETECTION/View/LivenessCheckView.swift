//
//  LivenessCheckView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI
import AVFoundation
import Vision
import QuartzCore

struct LivenessCheckView: View {
    @EnvironmentObject var viewModel: EKYCViewModel
    
    @State private var flashColor: Color = .black
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness
    
    // Bindings to trigger actions in LivenessCameraView.Coordinator
    @State private var shouldCaptureBaselineSelfie: Bool = false // To capture the initial baseline selfie for APIs
    @State private var shouldCaptureActiveFrameForAnalysis: Bool = false // To request an active frame for color analysis


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
                    shouldCaptureBaselineSelfie: $shouldCaptureBaselineSelfie,
                    shouldCaptureActiveFrameForAnalysis: $shouldCaptureActiveFrameForAnalysis,
                    onFlashColorChange: { newColor in
                        self.flashColor = newColor
                    }
                    // onSelfieSnapped is handled by ViewModel passing selfie to colorFlashSequenceCompleted
                )
                .frame(width: 300, height: 300)
                .clipShape(Circle())
                // Overlay shows color flash status now
                .overlay(Circle().stroke(viewModel.colorFlashLivenessStatus.isProcessing ? Color.yellow : Color.white, lineWidth: 4))

                // Instruction Text
                VStack {
                    Text(viewModel.livenessInstruction)
                        .font(.headline)
                        .foregroundColor(viewModel.obstructionResult == "plain" ? .green : .orange)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: viewModel.livenessInstruction)

                    Text("Face Detected: \(viewModel.isFaceDetected ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(minHeight: 60)

                // --- WARNING/ERROR VIEW ---
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
                else {
                    Spacer().frame(height: 38)
                }
                
                Button(action: {
                    // MODIFIED: Capture baseline selfie, and set ViewModel status for color flash
                    self.shouldCaptureBaselineSelfie = true // Trigger baseline selfie capture in Coordinator
                    self.viewModel.colorFlashLivenessStatus = .inProgress // Set ViewModel status for color flash
                }) {
                    Text(buttonTextForLiveness())
                        .font(.title2).fontWeight(.bold).foregroundColor(.white).padding()
                        .frame(maxWidth: .infinity)
                        .background(buttonBackgroundColorForLiveness())
                        .cornerRadius(15).shadow(radius: 5)
                }
                // Button enabled if face is detected and color flash is pending
                .disabled(!viewModel.isReadyForLivenessCheck || viewModel.colorFlashLivenessStatus.isProcessing || viewModel.overallProcessStatus.isFinished)

                Spacer()
            }
            .padding()
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .navigationBarBackButtonHidden(viewModel.overallProcessStatus.isProcessing || viewModel.colorFlashLivenessStatus.isProcessing)
        .onAppear {
            originalBrightness = UIScreen.main.brightness
            DispatchQueue.main.async { // Wrap state resets
                viewModel.isFaceDetected = false
                viewModel.obstructionResult = "Initializing..."
            }
        }
        .onDisappear {
            UIScreen.main.brightness = originalBrightness
        }
    }
    
    // Helper to determine button text
    private func buttonTextForLiveness() -> String {
        if viewModel.colorFlashLivenessStatus.isProcessing {
            return "Performing Color Flash..."
        } else if viewModel.colorFlashLivenessStatus.isFinished {
            return "Color Flash Completed"
        } else {
            return "Start Liveness Check"
        }
    }

    // Helper to determine button background color
    private func buttonBackgroundColorForLiveness() -> Color {
        if viewModel.colorFlashLivenessStatus.isProcessing {
            return .gray
        } else if viewModel.isReadyForLivenessCheck {
            return .blue
        } else {
            return .gray
        }
    }
}
