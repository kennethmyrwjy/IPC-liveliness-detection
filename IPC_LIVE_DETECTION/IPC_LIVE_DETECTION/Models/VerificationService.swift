//
//  VerificationService.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import Foundation
import UIKit

struct VerificationService: VerificationServiceProtocol {
    // IMPORTANT: Replace with your actual Hugging Face URL for the base
    let baseURL = "https://c-luis-e-ipc-similarity-verifier.hf.space"

    // Computed properties for the full API endpoint URLs
    private var verifyAPIURL: URL { URL(string: "\(baseURL)/api/verify")! }
    private var livenessAPIURL: URL { URL(string: "\(baseURL)/api/liveness")! } // Used for /api/liveness endpoint

    // NEW: Function for /api/liveness API call
    func performLivenessAPI(selfieImage: UIImage) async throws -> LivenessAPIResponse {
        var request = URLRequest(url: livenessAPIURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Use the generic single image body creator
        request.httpBody = createMultipartBody(boundary: boundary, image: selfieImage, name: "image", filename: "selfie.jpg")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]) }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(LivenessAPIResponse.self, from: data)
        } else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorResponse?.error ?? "An unknown server error occurred during Liveness API check."])
        }
    }

    // Renamed for clarity to performVerificationAPI (for KTP+Selfie)
    func performVerificationAPI(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse {
        var request = URLRequest(url: verifyAPIURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = createMultipartBodyForTwoImages(boundary: boundary, ktpImage: ktpImage, selfieImage: selfieImage)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]) }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(VerificationResponse.self, from: data)
        } else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorResponse?.error ?? "An unknown server error occurred during Similarity API verification."])
        }
    }
    
    // Generic helper function for single image upload
    private func createMultipartBody(boundary: String, image: UIImage, name: String, filename: String) -> Data {
        var body = Data()
        if let data = image.jpegData(compressionQuality: 0.8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // Helper function for two images
    private func createMultipartBodyForTwoImages(boundary: String, ktpImage: UIImage, selfieImage: UIImage) -> Data {
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
        
        return body
    }
}

