//
//  VerificationController.swift
//  IPC_LIVE_DETECTION
//
//  Created by Kenneth Mayer on 25/07/25.
//

import Foundation
import SwiftUI
import CoreML
import Vision
import AVFoundation

// MARK: - ViewModel (Controller)

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
        
        if let ktp = ktpImage, let selfie = selfieImage {
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
        } else {
            status = .error(message: "Missing images for verification.")
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

struct CameraPreview: UIViewRepresentable {
    var session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        
        // Create the preview layer and add it to the view's layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the view when needed (e.g., when the frame changes)
        if let previewLayer = uiView.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
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
