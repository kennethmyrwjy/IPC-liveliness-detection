//
//  ContentView.swift
//  KTPVerification
//
//  Created by Christian Luis Efendy on 21/07/25.
//

import SwiftUI
import Vision         // For Face Detection and running the ML model
import CoreML         // For the ML model itself
import Accelerate     // For high-speed math (cosine similarity)

// MARK: - Verification Status Enum
enum VerificationStatus {
    case pending
    case processing
    case success(score: Float)
    case failure(score: Float)
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
    
    // Computed property to check if verification can start
    private var canVerify: Bool {
        ktpUIImage != nil && selfieUIImage != nil
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                
                // --- Image Selection Sections ---
                HStack(spacing: 15) {
                    ImageSelectionView(
                        image: $ktpUIImage,
                        title: "KTP Photo",
                        systemIconName: "person.text.rectangle.fill"
                    ) {
                        isShowingKTPPicker = true
                    }
                    
                    ImageSelectionView(
                        image: $selfieUIImage,
                        title: "Selfie Photo",
                        systemIconName: "person.crop.square.fill"
                    ) {
                        isShowingSelfiePicker = true
                    }
                }
                
                // --- Verification Button ---
                Button(action: performVerification) {
                    Label("Verify Identity", systemImage: "faceid")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(canVerify ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canVerify)
                
                Spacer()
                
                // --- Results View ---
                VerificationResultView(status: verificationStatus)
                
                Spacer()
            }
            .padding()
            .navigationTitle("AIFR KTP Verification")
            .sheet(isPresented: $isShowingKTPPicker) {
                ImagePicker(selectedImage: $ktpUIImage)
            }
            .sheet(isPresented: $isShowingSelfiePicker) {
                ImagePicker(selectedImage: $selfieUIImage)
            }
        }
    }
    
    // MARK: - Core Logic
    private func performVerification() {
        guard let ktpImage = ktpUIImage, let selfieImage = selfieUIImage else {
            verificationStatus = .error(message: "Images are missing.")
            return
        }
        
        verificationStatus = .processing
        
        Task {
            do {
                // 1. Preprocess images (applying filters like in the Python script)
                // NOTE: Use OpenCV for iOS or Core Image for a 1-to-1 implementation
                let processedKTP = preprocess(image: ktpImage)
                let processedSelfie = preprocess(image: selfieImage)

                // 2. Extract facial embeddings using your converted Core ML model
                // NOTE: This is a placeholder. You must implement `getEmbedding`
                // using Vision and your actual 'InsightFace.mlmodel'.
                guard let ktpEmbedding = await getEmbedding(from: processedKTP),
                      let selfieEmbedding = await getEmbedding(from: processedSelfie) else {
                    throw VerificationError.featureExtractionFailed
                }

                // 3. Calculate similarity
                let similarity = calculateCosineSimilarity(between: ktpEmbedding, and: selfieEmbedding)
                
                // 4. Check against threshold (e.g., 0.45 for 'normal')
                let threshold: Float = 0.45
                if similarity > threshold {
                    verificationStatus = .success(score: similarity)
                } else {
                    verificationStatus = .failure(score: similarity)
                }
                
            } catch let error as VerificationError {
                verificationStatus = .error(message: error.description)
            } catch {
                verificationStatus = .error(message: "An unexpected error occurred: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Placeholder & Helper Functions
    
    /// **PLACEHOLDER**: Implement your image preprocessing logic here.
    private func preprocess(image: UIImage) -> UIImage {
        print("⚙️ Preprocessing image...")
        // For a 1:1 match, use OpenCV for iOS to apply CLAHE, Bilateral Filter, etc.
        // For now, we just return the original image.
        return image
    }
    
    /// **PLACEHOLDER**: Runs the Core ML model to get the facial embedding.
    private func getEmbedding(from image: UIImage) async -> [Float]? {
        print("🧠 Extracting facial embedding...")
        // ------------------------------------------------------------------
        // THIS IS WHERE YOU INTEGRATE YOUR CONVERTED `InsightFace.mlmodel`
        // 1. Create a VNCoreMLModel from your model.
        // 2. Create a VNCoreMLRequest.
        // 3. Run it using a VNImageRequestHandler.
        // 4. Extract the resulting MLMultiArray and convert it to [Float].
        // ------------------------------------------------------------------
        
        // For demonstration, we return a random 512-dimensional vector.
        return (0..<512).map { _ in Float.random(in: -1.0...1.0) }
    }
    
    /// **IMPLEMENTED**: Calculates cosine similarity using the Accelerate framework.
    private func calculateCosineSimilarity(between vecA: [Float], and vecB: [Float]) -> Float {
        guard vecA.count == vecB.count, !vecA.isEmpty else { return 0.0 }
        
        let dotProduct = vDSP.dot(vecA, vecB)
        let normA = vDSP.rootMeanSquare(vecA) * Float(vecA.count).squareRoot()
        let normB = vDSP.rootMeanSquare(vecB) * Float(vecB.count).squareRoot()
        
        guard normA > 0, normB > 0 else { return 0.0 }
        
        // Cosine similarity is defined as (A·B) / (||A||*||B||)
        // InsightFace's score is 1 - cosine_distance. Here we calculate similarity directly.
        // The Python script's "similarity" is actually distance. We use the more standard definition.
        // A direct comparison would be: return 1.0 - (dotProduct / (normA * normB))
        // Let's stick to the standard similarity score.
        return dotProduct / (normA * normB)
    }
}

// MARK: - Error Enum
enum VerificationError: Error {
    case featureExtractionFailed
    
    var description: String {
        switch self {
        case .featureExtractionFailed:
            return "Could not detect or process a face in one of the images."
        }
    }
}


// MARK: - Reusable UI Components

/// A view for selecting and displaying an image.
struct ImageSelectionView: View {
    @Binding var image: UIImage?
    let title: String
    let systemIconName: String
    let onButtonTapped: () -> Void
    
    var body: some View {
        VStack {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        Image(systemName: systemIconName)
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

/// A view for displaying the final verification result.
struct VerificationResultView: View {
    let status: VerificationStatus
    
    var body: some View {
        VStack(spacing: 10) {
            switch status {
            case .pending:
                Text("Please select both images to begin.")
                    .foregroundStyle(.secondary)
            case .processing:
                ProgressView("Verifying...")
            case .success(let score):
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
                Text("VERIFICATION PASSED")
                    .font(.title2).bold()
                    .foregroundStyle(.green)
                Text(String(format: "Similarity Score: %.2f%%", score * 100))
                    .font(.subheadline)
            case .failure(let score):
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)
                Text("VERIFICATION FAILED")
                    .font(.title2).bold()
                    .foregroundStyle(.red)
                Text(String(format: "Similarity Score: %.2f%%", score * 100))
                    .font(.subheadline)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)
                Text("Error")
                    .font(.title2).bold()
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


// MARK: - Image Picker Wrapper
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

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}


// MARK: - Preview
#Preview {
    ContentView()
}
