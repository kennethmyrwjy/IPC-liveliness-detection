
//
//  ContentView.swift
//  KTPVerification
//

import SwiftUI
import UIKit
import CoreML
import Vision

// MARK: - Data Models

struct VerificationResponse: Decodable {
    let verified: Bool
    let similarity_score: Double
    let deep_feature_similarity: Double
    let threshold: Double
}

struct APIErrorResponse: Decodable {
    let error: String
}

enum VerificationStatus {
    case pending
    case processing
    case success(response: VerificationResponse)
    case failure(response: VerificationResponse)
    case error(message: String)
}

extension UIImage {
    /// Converts the UIImage into a CVPixelBuffer of the given size (for Core ML input).
    func toCVPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        UIGraphicsBeginImageContextWithOptions(size, true, 2.0)
        self.draw(in: CGRect(origin: .zero, size: size))
        guard let scaledImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()
        guard let cgImage = scaledImage.cgImage else { return nil }

        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         attrs,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        let pxData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pxData,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: rgbColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

// MARK: - ViewModel

@MainActor
class VerificationViewModel: ObservableObject {
    @Published var ktpImage: UIImage?
    @Published var selfieImage: UIImage?
    @Published var status: VerificationStatus = .pending
    private var inferenceResult: String?

    private let service: VerificationServiceProtocol

    init(service: VerificationServiceProtocol = VerificationService()) {
        self.service = service
    }

    var canVerify: Bool {
        ktpImage != nil && selfieImage != nil
    }

    func performVerification() {
        
        performMLModelInference()
        
        guard let result = inferenceResult, result == "plain" else {
            status = .failure(response: VerificationResponse(verified: false, similarity_score: 0, deep_feature_similarity: 0, threshold: 0))
            return
        }
        
        guard let ktp = ktpImage, let selfie = selfieImage else { return }
        status = .processing
        Task {
            do {
                let response = try await service.verify(ktpImage: ktp, selfieImage: selfie)
                status = response.verified ? .success(response: response)
                                           : .failure(response: response)
            } catch {
                status = .error(message: error.localizedDescription)
            }
        }
    }
    
    // MARK: - Core ML Integration
    func performMLModelInference() {
        
        guard let selfie = selfieImage else { return }

        // Convert UIImage to CIImage
        guard let ciImage = CIImage(image: selfie) else { return }

        // Load the Core ML model
        guard let model = try? VNCoreMLModel(for: model_obstruction().model) else {
            print("Failed to load the Core ML model.")
            return
        }

        // Create a VNCoreMLRequest
        let request = VNCoreMLRequest(model: model) { request, error in
            if let error = error {
                print("Error during model inference: \(error.localizedDescription)")
                return
            }

            // Get the results from the request
            guard let results = request.results as? [VNClassificationObservation],
                  let bestResult = results.first else {
                print("No results from the model.")
                return
            }

            // Handle the result (best result will contain the classification)
            print("Prediction: \(bestResult.identifier) with confidence: \(bestResult.confidence)")
            self.inferenceResult = bestResult.identifier
        }

        // Create a VNImageRequestHandler to perform the request on the CIImage
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Error performing image request: \(error.localizedDescription)")
        }
    }
}

// MARK: - Service Layer

protocol VerificationServiceProtocol {
    func verify(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse
}

struct VerificationService: VerificationServiceProtocol {
    private let apiURL = URL(string: "https://c-luis-e-ipc-similarity-verifier.hf.space/api/verify")!

    func verify(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func appendImageField(name: String, image: UIImage, filename: String) {
            if let data = image.jpegData(compressionQuality: 0.8) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
        }

        appendImageField(name: "ktp_image", image: ktpImage, filename: "ktp.jpg")
        appendImageField(name: "selfie_image", image: selfieImage, filename: "selfie.jpg")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()

        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(VerificationResponse.self, from: data)
        } else {
            let errorObj = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorObj?.error ?? "An unknown server error occurred."])
        }
    }
}

// MARK: - View

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
        cameraCapture = CameraCapture()
        cameraCapture.onDesiredOutputDetected = { capturedImage in
            // Once the desired result is detected, set the captured image as the selfie
            self.viewModel.selfieImage = capturedImage
            // Proceed to the verification process
            self.viewModel.performVerification()
        }
        
        // Start the live camera feed
        cameraCapture.startCapture()
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

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Selfie Image Picker

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraDevice = .front  // Use front camera for selfies
        picker.allowsEditing = false  // Disable editing (cropping)
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}


#Preview {
    ContentView()
}
