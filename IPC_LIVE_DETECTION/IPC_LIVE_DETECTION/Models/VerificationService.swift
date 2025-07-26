//
//  VerificationService.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import Foundation
import UIKit

struct VerificationService: VerificationServiceProtocol {
    private let verifyAPIURL = URL(string: "https://c-luis-e-ipc-similarity-verifier.hf.space/api/verify")!
    // NEW: Define your spoof/pre-liveness API URL
    private let spoofAPIURL = URL(string: "YOUR_SPOOF_API_URL_HERE")! // <<<--- REPLACE THIS WITH YOUR ACTUAL SPOOF API URL

    func verify(ktpImage: UIImage, selfieImage: UIImage) async throws -> VerificationResponse {
        var request = URLRequest(url: verifyAPIURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        request.httpBody = createMultipartBody(boundary: boundary, ktpImage: ktpImage, selfieImage: selfieImage)
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(VerificationResponse.self, from: data)
        } else {
            let errorObj = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorObj?.error ?? "An unknown server error occurred. Status: \(httpResponse.statusCode)"])
        }
    }
    
    // NEW: Function for spoof/pre-liveness check
    func performPreLivenessCheck(ktpImage: UIImage) async throws -> SpoofDetectionResponse {
        var request = URLRequest(url: spoofAPIURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Assuming only KTP image is needed for initial spoof check
        request.httpBody = createMultipartBody(boundary: boundary, image: ktpImage, name: "image", filename: "ktp.jpg")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            // Decode to your new SpoofDetectionResponse
            return try decoder.decode(SpoofDetectionResponse.self, from: data)
        } else {
            let errorObj = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorObj?.error ?? "An unknown server error occurred during spoof check. Status: \(httpResponse.statusCode)"])
        }
    }

    // Helper function for single image upload (used by performPreLivenessCheck)
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
    
    // Existing helper function for two images (used by verify)
    private func createMultipartBody(boundary: String, ktpImage: UIImage, selfieImage: UIImage) -> Data {
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
