//
//  VerificationView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Kenneth Mayer on 25/07/25.
//

import SwiftUI

// MARK: - ContentView (View)

struct ContentView: View {
    @StateObject private var viewModel = VerificationViewModel()
    @State private var cameraCapture: CameraCapture!
    @State private var isShowingKTPPicker = false
    @State private var isShowingSelfiePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
//                HStack(spacing: 15) {
//                    ImageSelectionView(image: $viewModel.ktpImage, title: "KTP Photo") {
//                        isShowingKTPPicker = true
//                    }
//                    ImageSelectionView(image: $viewModel.selfieImage, title: "Selfie Photo") {
//                        isShowingSelfiePicker = true
//                    }
//                }
                if let captureSession = cameraCapture?.session {
                    CameraPreview(session: captureSession)
                        .frame(width: 300, height: 300)
                } else {
                    Text("Failed to start camera")
                        .foregroundColor(.red)
                }

                Button("Start Selfie Capture") {
                    startSelfieCapture()
                }

                Button(action: viewModel.performVerification) {
                    Label("Verify Identity", systemImage: "faceid")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(viewModel.canVerify ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!viewModel.canVerify)

                Spacer()

                VerificationResultView(status: viewModel.status)

                Spacer()
            }
            .padding()
            .navigationTitle("API KTP Verification")
            .sheet(isPresented: $isShowingKTPPicker) {
                CameraImagePicker(selectedImage: $viewModel.ktpImage)
            }
            .sheet(isPresented: $isShowingSelfiePicker) {
                CameraImagePicker(selectedImage: $viewModel.selfieImage)
            }
        }
    }
    
    private func startSelfieCapture() {
        if cameraCapture == nil {
            cameraCapture = CameraCapture()
            cameraCapture?.onDesiredOutputDetected = { capturedImage in
                // Once the desired result is detected, set the captured image as the selfie
                self.viewModel.selfieImage = capturedImage
                // Proceed to the verification process
                self.viewModel.performVerification()
            }
        }

        // Start the live camera feed
        cameraCapture?.startCapture()
    }
    
    private func stopSelfieCapture() {
        cameraCapture?.stopCapture()
    }
}

// MARK: - Reusable UI Components

struct ImageSelectionView: View {
    @Binding var image: UIImage?
    let title: String
    let onButtonTapped: () -> Void

    var body: some View {
        VStack {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 2))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        Image(systemName: "photo.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.gray)
                    )
                    .frame(width: 150, height: 180)
            }
            Button(action: onButtonTapped) {
                Text(title)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
    }
}

struct VerificationResultView: View {
    let status: VerificationStatus

    var body: some View {
        VStack(spacing: 10) {
            switch status {
            case .pending:
                Text("Please select both images to begin.").foregroundStyle(.secondary)
            case .processing:
                ProgressView("Verifying with server...")
            case .success:
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
                Text("VERIFICATION PASSED")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.green)
            case .failure:
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)
                Text("VERIFICATION FAILED")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.red)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)
                Text("Error")
                    .font(.title2)
                    .bold()
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

