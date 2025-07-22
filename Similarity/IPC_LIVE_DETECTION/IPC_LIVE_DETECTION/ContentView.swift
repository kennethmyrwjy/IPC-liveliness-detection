//
//  ContentView.swift
//  KTPVerification
//
//  Created by Christian Luis Efendy on 21/07/25.
//

import SwiftUI

// MARK: - Decodable Struct for API Response (Corrected)
struct VerificationResponse: Decodable {
    let verified: Bool
    let similarity_score: Double
    let deep_feature_similarity: Double // Added
    let threshold: Double               // Added
}

struct APIErrorResponse: Decodable {
    let error: String
}

// MARK: - Verification Status Enum
enum VerificationStatus {
    case pending
    case processing
    case success(response: VerificationResponse)
    case failure(response: VerificationResponse)
    case error(message: String)
}

// MARK: - Main Content View
struct ContentView: View {

    @State private var ktpUIImage: UIImage?
    @State private var selfieUIImage: UIImage?
    @State private var isShowingKTPPicker = false
    @State private var isShowingSelfiePicker = false
    @State private var verificationStatus: VerificationStatus = .pending

    // Use your final Hugging Face URL
    let apiURL = URL(string: "https://c-luis-e-ipc-similarity-verifier.hf.space/api/verify")!

    private var canVerify: Bool {
        ktpUIImage != nil && selfieUIImage != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 15) {
                    ImageSelectionView(image: $ktpUIImage, title: "KTP Photo") {
                        isShowingKTPPicker = true
                    }
                    ImageSelectionView(image: $selfieUIImage, title: "Selfie Photo") {
                        isShowingSelfiePicker = true
                    }
                }

                Button(action: performVerification) {
                    Label("Verify Identity", systemImage: "faceid")
                        .font(.headline).padding().frame(maxWidth: .infinity)
                        .background(canVerify ? Color.blue : Color.gray)
                        .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canVerify)
                
                Spacer()
                VerificationResultView(status: verificationStatus)
                Spacer()
            }
            .padding()
            .navigationTitle("API KTP Verification")
            .sheet(isPresented: $isShowingKTPPicker) { ImagePicker(selectedImage: $ktpUIImage) }
            .sheet(isPresented: $isShowingSelfiePicker) { ImagePicker(selectedImage: $selfieUIImage) }
        }
    }

    private func performVerification() {
        guard let ktpImg = ktpUIImage, let selfieImg = selfieUIImage else { return }
        verificationStatus = .processing
        Task {
            do {
                let response = try await verifyWithAPI(ktpImage: ktpImg, selfieImage: selfieImg)
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

    private func verifyWithAPI(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse {
        var request = URLRequest(url: apiURL)
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
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

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
                Image(uiImage: uiImage)
                    .resizable().scaledToFill().frame(width: 150, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 2))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1))
                    .overlay(Image(systemName: "photo.fill").font(.largeTitle).foregroundStyle(.gray))
                    .frame(width: 150, height: 180)
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
                Text("Please select both images to begin.").foregroundStyle(.secondary)
            case .processing:
                ProgressView("Verifying with server...")
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
        }.padding().frame(maxWidth: .infinity).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 20))
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

// MARK: - Preview
#Preview {
    ContentView()
}
