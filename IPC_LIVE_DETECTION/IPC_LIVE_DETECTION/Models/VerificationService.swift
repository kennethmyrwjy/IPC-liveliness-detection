//
//  VerificationService.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import Foundation
import UIKit

// Conforms to the updated protocol
struct VerificationService: VerificationServiceProtocol {
    // ⚠️ IMPORTANT: Replace with your actual Hugging Face URL for the base
    let baseURL = "https://c-luis-e-ipc-similarity-verifier.hf.space"

    // Computed properties for the full API endpoint URLs
    private var verifyURL: URL { URL(string: "\(baseURL)/api/verify")! } // From ContentView
    private var livenessURL: URL { URL(string: "\(baseURL)/api/liveness")! } // From ContentView

    // Generic function for uploading a single image (from ContentView.swift)
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
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]) }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(T.self, from: data)
        } else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorResponse?.error ?? "An unknown server error occurred."])
        }
    }

    // Specific function for uploading two images (from ContentView.swift)
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
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."]) }

        let decoder = JSONDecoder()
        if (200...299).contains(httpResponse.statusCode) {
            return try decoder.decode(VerificationResponse.self, from: data)
        } else {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: errorResponse?.error ?? "An unknown server error occurred."])
        }
    }
}
