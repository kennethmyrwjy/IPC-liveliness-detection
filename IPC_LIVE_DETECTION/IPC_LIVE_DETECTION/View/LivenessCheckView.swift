// Di file LivenessCheckView.swift

import SwiftUI
import AVFoundation
import Vision
import QuartzCore

struct LivenessCheckView: View {
    @EnvironmentObject var viewModel: EKYCViewModel
    
    // State untuk mengontrol kamera
    @State private var shouldCaptureBaselineSelfie: Bool = false
    @State private var shouldCaptureActiveFrameForAnalysis: Bool = false

    // State untuk mengontrol UI
    @State private var flashColor: Color = .black
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness // Simpan kecerahan awal

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
                )
                .frame(width: 300, height: 300)
                .clipShape(Circle())
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

                // Tombol Aksi
                Button(action: {
                    // LOGIKA KECERAHAN DITAMBAHKAN DI SINI
                    self.originalBrightness = UIScreen.main.brightness // 1. Simpan kecerahan saat ini
                    UIScreen.main.brightness = 1.0 // 2. Atur kecerahan ke maksimal

                    // 3. Mulai proses seperti biasa
                    self.shouldCaptureBaselineSelfie = true
                    self.viewModel.colorFlashLivenessStatus = .inProgress
                }) {
                    Text(buttonTextForLiveness())
                        .font(.title2).fontWeight(.bold).foregroundColor(.white).padding()
                        .frame(maxWidth: .infinity)
                        .background(buttonBackgroundColorForLiveness())
                        .cornerRadius(15).shadow(radius: 5)
                }
                .disabled(!viewModel.isReadyForLivenessCheck || viewModel.colorFlashLivenessStatus.isProcessing || viewModel.overallProcessStatus.isFinished)

                Spacer()
            }
            .padding()
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .navigationBarBackButtonHidden(viewModel.overallProcessStatus.isProcessing || viewModel.colorFlashLivenessStatus.isProcessing)
        .onDisappear {
            // KEMBALIKAN KECERAHAN SAAT KELUAR DARI SCREEN INI
            UIScreen.main.brightness = self.originalBrightness
        }
    }
    
    // Helper untuk teks tombol
    private func buttonTextForLiveness() -> String {
        if viewModel.colorFlashLivenessStatus.isProcessing {
            return "Performing Color Flash..."
        } else if viewModel.colorFlashLivenessStatus.isFinished {
            return "Color Flash Completed"
        } else {
            return "Start Liveness Check"
        }
    }

    // Helper untuk warna background tombol
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
