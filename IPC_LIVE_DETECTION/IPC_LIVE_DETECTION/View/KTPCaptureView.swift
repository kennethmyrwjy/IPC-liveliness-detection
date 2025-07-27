//
//  KTPCaptureView.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI

struct KTPCaptureView: View {
    @EnvironmentObject var viewModel: EKYCViewModel
    @State private var triggerCapture = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Step 1: Capture Your KTP")
                .font(.largeTitle).fontWeight(.bold)
                .multilineTextAlignment(.center)

            if viewModel.ktpImage == nil {
                cameraView
            } else {
                previewView
            }

            Button(action: {
                viewModel.navigateToLiveness() // Navigate directly to the liveness (selfie) capture
            }) {
                Label("Next Step: Capture Face", systemImage: "arrow.right.circle.fill")
                    .font(.headline).padding()
                    .frame(maxWidth: .infinity)
                    .background(viewModel.ktpImage != nil ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.ktpImage == nil) // Disabled if KTP not captured
        }
        .padding()
        .navigationTitle("KTP Verification")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cameraView: some View {
        VStack {
            ZStack {
                KTPCameraView(
                    shouldCapture: $triggerCapture,
                    onCaptured: { image in
                        viewModel.ktpImage = image
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.8), lineWidth: 3)
                )

                Text("Position KTP within the frame")
                    .font(.caption).padding(6)
                    .background(.black.opacity(0.5))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
            }
            .frame(height: 250)
            
            Spacer(minLength: 20)

            Button(action: {
                triggerCapture = true
            }) {
                Label("Capture KTP", systemImage: "camera.fill")
                    .font(.headline).padding()
            }
            .buttonStyle(.borderedProminent).tint(.blue)
            .frame(minHeight: 80)
        }
    }

    @ViewBuilder
    private var previewView: some View {
        if let ktpImage = viewModel.ktpImage {
            VStack {
                Image(uiImage: ktpImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                
                Spacer(minLength: 20)

                Button(action: {
                    viewModel.ktpImage = nil
                }) {
                    Label("Recapture", systemImage: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.headline).padding()
                }
                .buttonStyle(.bordered).tint(.blue)
                .frame(minHeight: 80)
            }
        }
    }
}
