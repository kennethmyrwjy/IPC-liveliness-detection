import SwiftUI

// MARK: - Decodable Structs to Match API JSON
struct VerificationResponse: Decodable {
    let verified: Bool
    let similarity_score: Double
    let deep_feature_similarity: Double
    let threshold: Double
}

struct LivenessResponse: Decodable {
    let liveness_passed: Bool
    let confidence: Double
}

struct APIErrorResponse: Decodable {
    let error: String
}

// MARK: - Enum to Manage UI State
enum VerificationStatus {
    case pending
    case processing
    case success(response: VerificationResponse)
    case failure(response: VerificationResponse)
    case livenessSuccess(response: LivenessResponse)
    case livenessFailure(response: LivenessResponse)
    case error(message: String)
}

// MARK: - Main Content View
struct ContentView: View {
    // MARK: - State Variables
    @State private var ktpUIImage: UIImage?
    @State private var selfieUIImage: UIImage?
    @State private var isShowingKTPPicker = false
    @State private var isShowingSelfiePicker = false
    @State private var verificationStatus: VerificationStatus = .pending

    // ⚠️ IMPORTANT: Replace with your actual Hugging Face URL
    let baseURL = "https://c-luis-e-ipc-similarity-verifier.hf.space"

    // Computed properties for the full API endpoint URLs
    private var verifyURL: URL { URL(string: "\(baseURL)/api/verify")! }
    private var livenessURL: URL { URL(string: "\(baseURL)/api/liveness")! }

    // Computed properties to enable/disable buttons
    private var canVerify: Bool { ktpUIImage != nil && selfieUIImage != nil }
    private var canCheckLiveness: Bool { selfieUIImage != nil }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Complete Verification")
                        .font(.largeTitle).bold()
                        .padding(.top)

                    // Image Selection UI
                    HStack(spacing: 15) {
                        ImageSelectionView(image: $ktpUIImage, title: "KTP Photo") { isShowingKTPPicker = true }
                        ImageSelectionView(image: $selfieUIImage, title: "Selfie Photo") { isShowingSelfiePicker = true }
                    }

                    // Action Buttons UI
                    VStack(spacing: 10) {
                        Button(action: performLivenessCheck) {
                            Label("1. Check Liveness", systemImage: "face.smiling")
                                .font(.headline).padding().frame(maxWidth: .infinity)
                                .background(canCheckLiveness ? Color.orange : Color.gray)
                        }
                        .disabled(!canCheckLiveness)

                        Button(action: performVerification) {
                            Label("2. Verify Similarity", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                .font(.headline).padding().frame(maxWidth: .infinity)
                                .background(canVerify ? Color.blue : Color.gray)
                        }
                        .disabled(!canVerify)
                    }
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Results Display UI
                    VerificationResultView(status: verificationStatus)
                }
                .padding()
            }
            .navigationTitle("Face Verification")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingKTPPicker) { ImagePicker(selectedImage: $ktpUIImage) }
            .sheet(isPresented: $isShowingSelfiePicker) { ImagePicker(selectedImage: $selfieUIImage) }
        }
    }

    // MARK: - API Logic
    func performLivenessCheck() {
        guard let selfieImg = selfieUIImage else { return }
        verificationStatus = .processing
        Task {
            do {
                let response = try await uploadImage(to: livenessURL, image: selfieImg, fieldName: "image", responseType: LivenessResponse.self)
                if response.liveness_passed {
                    verificationStatus = .livenessSuccess(response: response)
                } else {
                    verificationStatus = .livenessFailure(response: response)
                }
            } catch {
                verificationStatus = .error(message: error.localizedDescription)
            }
        }
    }

    func performVerification() {
        guard let ktpImg = ktpUIImage, let selfieImg = selfieUIImage else { return }
        verificationStatus = .processing
        Task {
            do {
                let response = try await uploadTwoImages(ktpImage: ktpImg, selfieImage: selfieImg)
                if response.verified {
                    verificationStatus = .success(response: response)
                } else {
                    verificationStatus = .failure(response: response)
                }
            } catch {
                verificationStatus = .error(message: error.localizedDescription)
            }
        }
    }

    // Generic function for uploading a single image
    func uploadImage<T: Decodable>(to url: URL, image: UIImage, fieldName: String, responseType: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        if let data = image.jpegData(compressionQuality: 0.8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(T.self, from: data)
        } else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorResponse?.error ?? "An unknown server error occurred."])
        }
    }

    // Specific function for uploading two images
    func uploadTwoImages(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse {
        var request = URLRequest(url: verifyURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        if let ktpData = ktpImage.jpegData(compressionQuality: 0.8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"ktp_image\"; filename=\"ktp.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(ktpData)
            body.append("\r\n".data(using: .utf8)!)
        }
        if let selfieData = selfieImage.jpegData(compressionQuality: 0.8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"selfie_image\"; filename=\"selfie.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(selfieData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(VerificationResponse.self, from: data)
        } else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorResponse?.error ?? "An unknown server error occurred."])
        }
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
                Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 150, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 2))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1))
                    .overlay(Image(systemName: "photo.fill").font(.largeTitle).foregroundStyle(.gray)).frame(width: 150, height: 180)
            }
            Button(action: onButtonTapped) { Text(title) }.buttonStyle(.bordered).tint(.blue)
        }
    }
}

struct VerificationResultView: View {
    let status: VerificationStatus
    var body: some View {
        VStack(spacing: 10) {
            switch status {
            case .pending:
                Text("Please select images to begin.").foregroundStyle(.secondary)
            case .processing:
                ProgressView("Processing...")
            case .livenessSuccess(let response):
                Image(systemName: "face.smiling.fill").font(.system(size: 50)).foregroundStyle(.green)
                Text("LIVENESS PASSED").font(.title2).bold().foregroundStyle(.green)
                Text(String(format: "Confidence: %.1f%%", response.confidence * 100)).font(.subheadline)
            case .livenessFailure:
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 50)).foregroundStyle(.red)
                Text("LIVENESS FAILED").font(.title2).bold().foregroundStyle(.red)
                Text("This may be a spoofed image.").font(.subheadline)
            case .success(let response):
                Image(systemName: "checkmark.shield.fill").font(.system(size: 50)).foregroundStyle(.green)
                Text("VERIFICATION PASSED").font(.title2).bold().foregroundStyle(.green)
                Text(String(format: "Similarity Score: %.2f%%", response.similarity_score * 100)).font(.subheadline)
            case .failure(let response):
                Image(systemName: "xmark.shield.fill").font(.system(size: 50)).foregroundStyle(.red)
                Text("VERIFICATION FAILED").font(.title2).bold().foregroundStyle(.red)
                Text(String(format: "Similarity Score: %.2f%%", response.similarity_score * 100)).font(.subheadline)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 50)).foregroundStyle(.orange)
                Text("Error").font(.title2).bold()
                Text(message).font(.subheadline).multilineTextAlignment(.center)
            }
        }.padding().frame(maxWidth: .infinity, minHeight: 150).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage { parent.selectedImage = image }; parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
