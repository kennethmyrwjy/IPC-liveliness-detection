//
//  VerificationResponse.swift
//  IPC_LIVE_DETECTION
//
//  Created by Kenneth Mayer on 25/07/25.
//

import Foundation
import UIKit

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
