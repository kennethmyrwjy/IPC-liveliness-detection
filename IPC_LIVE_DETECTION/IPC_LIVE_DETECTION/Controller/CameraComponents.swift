//
//  CameraComponents.swift
//  IPC_LIVE_DETECTION
//
//  Created by Jordan on 25/07/25.
//

import SwiftUI
import AVFoundation
import Vision
import QuartzCore

protocol CameraViewControllerDelegate: AnyObject {
    func didCaptureFrame(_ frame: CVPixelBuffer)
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    weak var delegate: CameraViewControllerDelegate?
    var cameraPosition: AVCaptureDevice.Position = .front

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        captureSession = AVCaptureSession()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Failed to get camera device for position: \(self.cameraPosition)")
            return
        }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue", qos: .userInitiated))
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.didCaptureFrame(pixelBuffer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}

// MARK: - KTP Camera View
struct KTPCameraView: UIViewControllerRepresentable {
    @Binding var shouldCapture: Bool
    var onCaptured: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.cameraPosition = .back
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: KTPCameraView
        
        init(parent: KTPCameraView) {
            self.parent = parent
        }
        
        func didCaptureFrame(_ frame: CVPixelBuffer) {
            DispatchQueue.main.async {
                if self.parent.shouldCapture {
                    self.parent.shouldCapture = false
                    
                    let ciImage = CIImage(cvPixelBuffer: frame)
                    let context = CIContext()
                    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
                        print("KTPCapture: Image successfully converted and about to be passed to viewModel.")
                        self.parent.onCaptured(uiImage)
                    } else {
                        print("KTPCapture: Failed to create CGImage from CVPixelBuffer.")
                    }
                }
            }
        }
    }
}

// MARK: - Liveness Camera View (Corrected)
struct LivenessCameraView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: EKYCViewModel
    @Binding var shouldCaptureBaselineSelfie: Bool
    @Binding var shouldCaptureActiveFrameForAnalysis: Bool

    var onFlashColorChange: (Color) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.cameraPosition = .front
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.viewModel = viewModel
        context.coordinator.shouldCaptureBaselineSelfieBinding = $shouldCaptureBaselineSelfie
        context.coordinator.shouldCaptureActiveFrameForAnalysisBinding = $shouldCaptureActiveFrameForAnalysis
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, viewModel: viewModel)
    }

    // MARK: - Coordinator (Corrected Logic)
    // ==================================
    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: LivenessCameraView
        var viewModel: EKYCViewModel

        var shouldCaptureBaselineSelfieBinding: Binding<Bool>
        var shouldCaptureActiveFrameForAnalysisBinding: Binding<Bool>

        private var snappedBaselinePixelBuffer: CVPixelBuffer?
        private var faceBoundingBox: CGRect?
        private var colorSequence: [Color] = []
        private var sessionResults: [(expected: String, detected: String)] = []
        private var currentStep = 0
        private var lastRealtimeAnalysisTime: TimeInterval = 0
        private let realtimeAnalysisThrottleInterval: TimeInterval = 0.25
        
        private var livenessStatusFromVM: ColorFlashLivenessProcessStatus = .pending

        init(parent: LivenessCameraView, viewModel: EKYCViewModel) {
            self.parent = parent
            self.viewModel = viewModel
            self.shouldCaptureBaselineSelfieBinding = parent.$shouldCaptureBaselineSelfie
            self.shouldCaptureActiveFrameForAnalysisBinding = parent.$shouldCaptureActiveFrameForAnalysis
            super.init()
        }

        @MainActor func didCaptureFrame(_ frame: CVPixelBuffer) {
            livenessStatusFromVM = viewModel.colorFlashLivenessStatus
            
            if !livenessStatusFromVM.isFinished {
                runRealtimeFaceAnalysis(frame: frame)
            }
            
            if shouldCaptureBaselineSelfieBinding.wrappedValue {
                shouldCaptureBaselineSelfieBinding.wrappedValue = false
                snapBaselineSelfie(frame: frame)
                return
            }
            
            if shouldCaptureActiveFrameForAnalysisBinding.wrappedValue {
                shouldCaptureActiveFrameForAnalysisBinding.wrappedValue = false
                captureAndAnalyzeActiveFrame(frame: frame)
                return
            }
        }

        private func runRealtimeFaceAnalysis(frame: CVPixelBuffer) {
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastRealtimeAnalysisTime > realtimeAnalysisThrottleInterval else { return }
            lastRealtimeAnalysisTime = currentTime
            
            let faceRequest = VNDetectFaceRectanglesRequest { (request, error) in
                let faceDetected = (request.results as? [VNFaceObservation])?.first != nil
                DispatchQueue.main.async {
                    self.viewModel.isFaceDetected = faceDetected
                }
            }
            try? VNImageRequestHandler(cvPixelBuffer: frame, options: [:]).perform([faceRequest])
        }
        
        private func snapBaselineSelfie(frame: CVPixelBuffer) {
            print("Coordinator: Capturing baseline selfie...")
            guard let frameCopy = frame.deepCopied() else {
                abortLivenessCheck(reason: "Failed to copy baseline frame.")
                return
            }
            
            detectFace(in: frameCopy) { [weak self] faceBounds in
                guard let self = self else { return }
                
                guard let bounds = faceBounds else {
                    self.abortLivenessCheck(reason: "No face detected in the initial selfie. Please try again.")
                    return
                }
                
                self.faceBoundingBox = bounds
                self.snappedBaselinePixelBuffer = frameCopy

                print("Coordinator: Baseline pixel buffer and face bounds captured. Starting flash sequence.")
                self.startColorFlashSequence()
            }
        }
        
        private func startColorFlashSequence() {
            sessionResults.removeAll()
            currentStep = 0
            generateColorSequence()
            
            DispatchQueue.main.async {
                self.executeNextFlashStep()
            }
        }
        
        private func captureAndAnalyzeActiveFrame(frame: CVPixelBuffer) {
            guard let baselinePixelBuffer = self.snappedBaselinePixelBuffer,
                  let faceBox = self.faceBoundingBox else {
                abortLivenessCheck(reason: "Missing baseline data for analysis.")
                return
            }
            
            guard let activeFrameCopy = frame.deepCopied() else {
                abortLivenessCheck(reason: "Could not copy active frame for analysis.")
                return
            }
            
            // CORRECTED: Call the CMY analysis function
            let result = self.analyzeCMYIncrease(baseline: baselinePixelBuffer, active: activeFrameCopy, faceBounds: faceBox)
            
            DispatchQueue.main.async {
                self.parent.onFlashColorChange(.black)
                // CORRECTED: Handle the CMY analysis result
                self.handleAnalysisCompletion(result: result)
            }
        }
        
        private func executeNextFlashStep() {
            guard currentStep < colorSequence.count else {
                endLivenessCheck()
                return
            }
            
            DispatchQueue.main.async {
                self.parent.onFlashColorChange(self.colorSequence[self.currentStep])
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.shouldCaptureActiveFrameForAnalysisBinding.wrappedValue = true
                }
            }
        }

        // MARK: - Corrected Analysis Logic (from your old code)
        
        /// **REPLACED FUNCTION**: This function now correctly handles the CMY analysis result.
        private func handleAnalysisCompletion(result: (cyan: Float, magenta: Float, yellow: Float)) {
            var detectedColor = "Inconclusive"
            
            let (cyanIncrease, magentaIncrease, yellowIncrease) = result

            // Determine which color channel had the largest increase
            if cyanIncrease > magentaIncrease && cyanIncrease > yellowIncrease {
                detectedColor = "Cyan"
            } else if magentaIncrease > cyanIncrease && magentaIncrease > yellowIncrease {
                detectedColor = "Magenta"
            } else if yellowIncrease > cyanIncrease && yellowIncrease > magentaIncrease {
                detectedColor = "Yellow"
            }
            
            let expectedColor = self.colorToString(self.colorSequence[self.currentStep])
            self.sessionResults.append((expected: expectedColor, detected: detectedColor))
            
            print("Flash \(currentStep + 1): Expected \(expectedColor), Detected \(detectedColor) | Increases -> C: \(String(format: "%.4f", cyanIncrease)), M: \(String(format: "%.4f", magentaIncrease)), Y: \(String(format: "%.4f", yellowIncrease))")

            self.currentStep += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeNextFlashStep()
            }
        }
        
        /// **REPLACED FUNCTION**: This now calculates the increase in CMY channels, not RGB.
        private func analyzeCMYIncrease(baseline: CVPixelBuffer, active: CVPixelBuffer, faceBounds: CGRect) -> (cyan: Float, magenta: Float, yellow: Float) {
            CVPixelBufferLockBaseAddress(baseline, .readOnly)
            CVPixelBufferLockBaseAddress(active, .readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(baseline, .readOnly)
                CVPixelBufferUnlockBaseAddress(active, .readOnly)
            }
            
            guard let baselineAddr = CVPixelBufferGetBaseAddress(baseline),
                  let activeAddr = CVPixelBufferGetBaseAddress(active) else {
                return (0, 0, 0)
            }
            
            let bytesPerRow = CVPixelBufferGetBytesPerRow(baseline)
            let baselinePtr = baselineAddr.assumingMemoryBound(to: UInt8.self)
            let activePtr = activeAddr.assumingMemoryBound(to: UInt8.self)
            
            let ellipseCenterX = Float(faceBounds.midX)
            let ellipseCenterY = Float(faceBounds.midY)
            let radiusX = Float(faceBounds.width / 2)
            let radiusY = Float(faceBounds.height / 2)

            var baseCSum: Float = 0, baseMSum: Float = 0, baseYSum: Float = 0
            var activeCSum: Float = 0, activeMSum: Float = 0, activeYSum: Float = 0
            var pixelCount: Float = 0

            for y in Int(faceBounds.minY)..<Int(faceBounds.maxY) {
                for x in Int(faceBounds.minX)..<Int(faceBounds.maxX) {
                    let dx = Float(x) - ellipseCenterX
                    let dy = Float(y) - ellipseCenterY
                    if (dx*dx)/(radiusX*radiusX) + (dy*dy)/(radiusY*radiusY) <= 1 {
                        let offset = y * bytesPerRow + x * 4
                        
                        // --- Calculate CMY for Baseline Frame (BGRA format) ---
                        let baseR = Float(baselinePtr[offset + 2]) / 255.0
                        let baseG = Float(baselinePtr[offset + 1]) / 255.0
                        let baseB = Float(baselinePtr[offset + 0]) / 255.0
                        baseCSum += (1.0 - baseR)  // Cyan = 1 - Red
                        baseMSum += (1.0 - baseG)  // Magenta = 1 - Green
                        baseYSum += (1.0 - baseB)  // Yellow = 1 - Blue

                        // --- Calculate CMY for Active Frame (BGRA format) ---
                        let activeR = Float(activePtr[offset + 2]) / 255.0
                        let activeG = Float(activePtr[offset + 1]) / 255.0
                        let activeB = Float(activePtr[offset + 0]) / 255.0
                        activeCSum += (1.0 - activeR)
                        activeMSum += (1.0 - activeG)
                        activeYSum += (1.0 - activeB)
                        
                        pixelCount += 1
                    }
                }
            }
            
            guard pixelCount > 0 else { return (0, 0, 0) }

            // --- Calculate Mean for each channel ---
            let baseCMean = baseCSum / pixelCount
            let baseMMean = baseMSum / pixelCount
            let baseYMean = baseYSum / pixelCount

            let activeCMean = activeCSum / pixelCount
            let activeMMean = activeMSum / pixelCount
            let activeYMean = activeYSum / pixelCount

            // --- Calculate and return the increase in mean intensity ---
            let increaseC = activeCMean - baseCMean
            let increaseM = activeMMean - baseMMean
            let increaseY = activeYMean - baseYMean

            return (increaseC, increaseM, increaseY)
        }

        // MARK: - Helper and State Management Functions (Unchanged)
        
        private func generateColorSequence() {
            let possibleColors: [Color] = [Color(UIColor.cyan), Color(UIColor.magenta), .yellow]
            self.colorSequence = (0..<6).map { _ in possibleColors.randomElement()! }
        }
        
        private func endLivenessCheck() {
            DispatchQueue.main.async {
                self.parent.onFlashColorChange(.black)
                var report = "Color Flash Liveness Analysis Complete:\n\n"
                var successCount = 0
                for (index, result) in self.sessionResults.enumerated() {
                    let status = result.expected.lowercased() == result.detected.lowercased() ? "✅" : "❌"
                    if status == "✅" { successCount += 1 }
                    report += "Flash \(index + 1): Expected \(result.expected), Detected \(result.detected) \(status)\n"
                }
                
                let wasSuccessful = successCount >= 4
                let finalStatus = wasSuccessful ? "Liveness Confirmed" : "Liveness Failed"
                report += "\nFinal Result: \(finalStatus)"
                
                var finalSelfie: UIImage?
                if let buffer = self.snappedBaselinePixelBuffer {
                    let ciImage = CIImage(cvPixelBuffer: buffer)
                    let context = CIContext()
                    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                        finalSelfie = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
                    }
                }

                self.viewModel.colorFlashSequenceCompleted(wasSuccessful: wasSuccessful, report: report, snappedSelfie: finalSelfie)
                self.resetLocalState()
            }
        }

        private func abortLivenessCheck(reason: String) {
            DispatchQueue.main.async {
                self.parent.onFlashColorChange(.black)
                self.viewModel.colorFlashSequenceCompleted(wasSuccessful: false, report: reason, snappedSelfie: nil)
                self.resetLocalState()
            }
        }
        
        private func resetLocalState() {
            currentStep = 0
            sessionResults.removeAll()
            colorSequence.removeAll()
            snappedBaselinePixelBuffer = nil
            faceBoundingBox = nil
            shouldCaptureBaselineSelfieBinding.wrappedValue = false
            shouldCaptureActiveFrameForAnalysisBinding.wrappedValue = false
        }
        
        private func detectFace(in pixelBuffer: CVPixelBuffer, completion: @escaping (CGRect?) -> Void) {
            let request = VNDetectFaceRectanglesRequest { (request, error) in
                guard let firstResult = (request.results as? [VNFaceObservation])?.first else {
                    completion(nil); return
                }
                let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
                let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
                let bounds = VNImageRectForNormalizedRect(firstResult.boundingBox, imageWidth, imageHeight)
                completion(bounds)
            }
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
        }
        
        private func colorToString(_ color: Color) -> String {
            switch color {
            case Color(UIColor.cyan): return "Cyan"
            case Color(UIColor.magenta): return "Magenta"
            case .yellow: return "Yellow"
            default: return "Unknown"
            }
        }
    }
}

// MARK: - CVPixelBuffer Extension
extension CVPixelBuffer {
    func deepCopied() -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let format = CVPixelBufferGetPixelFormatType(self)
        var pixelBufferCopy: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes, &pixelBufferCopy) == kCVReturnSuccess, let copy = pixelBufferCopy else { return nil }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }

        guard let source = CVPixelBufferGetBaseAddress(self), let dest = CVPixelBufferGetBaseAddress(copy) else {
            return nil
        }
        memcpy(dest, source, CVPixelBufferGetDataSize(self))
        return copy
    }
}
