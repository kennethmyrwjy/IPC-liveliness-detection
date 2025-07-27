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
            // Check the trigger on the main thread
            DispatchQueue.main.async {
                if self.parent.shouldCapture {
                    self.parent.shouldCapture = false // Reset trigger
                    
                    // Convert the CVPixelBuffer to a UIImage
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

struct LivenessCameraView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: EKYCViewModel
    @Binding var shouldCaptureBaseline: Bool
    @Binding var shouldCaptureActive: Bool
    var onAnalysisComplete: ((cyan: Float, magenta: Float, yellow: Float)) -> Void
    var onBaselineCaptured: () -> Void
    var onFlashColorChange: (Color) -> Void


    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.cameraPosition = .front
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.viewModelLivenessStatus = viewModel.colorFlashLivenessStatus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, viewModel: viewModel, onAnalysisComplete: onAnalysisComplete, onBaselineCaptured: onBaselineCaptured, onFlashColorChange: onFlashColorChange)
    }

    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: LivenessCameraView
        var viewModel: EKYCViewModel
        var onAnalysisComplete: ((cyan: Float, magenta: Float, yellow: Float)) -> Void
        var onBaselineCaptured: () -> Void
        var onFlashColorChange: (Color) -> Void

        private var faceBoundingBox: CGRect?
        private var baselineFrame: CVPixelBuffer?
        private var lastAnalysisTime: TimeInterval = 0
        private let analysisThrottleInterval: TimeInterval = 0.25
        private var colorSequence: [Color] = []
        private var sessionResults: [(expected: String, detected: String)] = []
        private var currentStep = 0

        var viewModelLivenessStatus: ColorFlashLivenessStatus = .pending {
            didSet {
                if viewModelLivenessStatus == .inProgress && oldValue != .inProgress {
                    startColorFlashSequence()
                }
            }
        }

        init(parent: LivenessCameraView, viewModel: EKYCViewModel, onAnalysisComplete: @escaping ((cyan: Float, magenta: Float, yellow: Float)) -> Void, onBaselineCaptured: @escaping () -> Void, onFlashColorChange: @escaping (Color) -> Void) {
            self.parent = parent
            self.viewModel = viewModel
            self.onAnalysisComplete = onAnalysisComplete
            self.onBaselineCaptured = onBaselineCaptured
            self.onFlashColorChange = onFlashColorChange
            super.init()
        }
        
        func didCaptureFrame(_ frame: CVPixelBuffer) {
            DispatchQueue.main.async { // Ensure viewModel access is on MainActor
                switch self.viewModel.colorFlashLivenessStatus {
                case .pending:
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.runPendingAnalysis(frame: frame)
                    }
                case .inProgress:
                    if self.parent.shouldCaptureBaseline {
                        self.parent.shouldCaptureBaseline = false
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.captureBaselineAndProceed(frame: frame)
                        }
                    } else if self.parent.shouldCaptureActive {
                        self.parent.shouldCaptureActive = false
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.captureActiveFrameAndAnalyze(frame: frame)
                        }
                    }
                case .success, .failure:
                    break
                }
            }
        }
        
        private func runPendingAnalysis(frame: CVPixelBuffer) {
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastAnalysisTime > analysisThrottleInterval else { return }
            lastAnalysisTime = currentTime
            
            self.performRealTimeAnalysis(on: frame)
        }
        
        private func performRealTimeAnalysis(on frame: CVPixelBuffer) {
            let faceRequest = VNDetectFaceRectanglesRequest { (request, error) in
                let faceDetected = (request.results as? [VNFaceObservation])?.first != nil
                DispatchQueue.main.async {
                    self.viewModel.isFaceDetected = faceDetected
                }
            }
            
            let obstructionRequest = VNCoreMLRequest(model: self.viewModel.obstructionModel) { (request, error) in
                let obstructionResult = (request.results as? [VNClassificationObservation])?.first?.identifier ?? "Error"
                DispatchQueue.main.async {
                    self.viewModel.obstructionResult = obstructionResult
                }
            }
            
            try? VNImageRequestHandler(cvPixelBuffer: frame, options: [:]).perform([faceRequest, obstructionRequest])
        }

        // MARK: - Liveness Step Management (MOVED TO COORDINATOR)
        
        private func startColorFlashSequence() {
            sessionResults.removeAll()
            currentStep = 0
            generateColorSequence()
            DispatchQueue.main.async {
                self.parent.shouldCaptureBaseline = true
            }
        }
        
        private func generateColorSequence() {
            let possibleColors: [Color] = [Color(UIColor.cyan), Color(UIColor.magenta), .yellow]
            self.colorSequence = (0..<6).map { _ in possibleColors.randomElement()! }
        }
        
        private func captureBaselineAndProceed(frame: CVPixelBuffer) {
            guard let frameCopy = frame.deepCopied() else {
                DispatchQueue.main.async { self.abortLivenessCheck(reason: "Failed to capture baseline image.") }
                return
            }
            self.baselineFrame = frameCopy
            
            let ciImage = CIImage(cvPixelBuffer: frameCopy)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                DispatchQueue.main.async {
                    self.viewModel.selfieImage = UIImage(cgImage: cgImage)
                }
            }
            
            // MODIFIED: Explicitly cast faceBounds to CGRect?
            self.detectFace(in: frameCopy) { [weak self] (faceBounds: CGRect?) in // <<< Fix 2
                guard let self = self else { return }
                if let bounds = faceBounds {
                    self.faceBoundingBox = bounds
                    DispatchQueue.main.async {
                        self.onBaselineCaptured()
                        self.executeNextFlashStep() // <<< Fix 1
                    }
                } else {
                    DispatchQueue.main.async { self.abortLivenessCheck(reason: "No face detected in baseline image.") }
                }
            }
        }

        private func captureActiveFrameAndAnalyze(frame: CVPixelBuffer) {
            guard let baseline = self.baselineFrame,
                  let faceBox = self.faceBoundingBox,
                  let activeFrameCopy = frame.deepCopied() else {
                DispatchQueue.main.async { self.abortLivenessCheck(reason: "Missing baseline or face data for active frame.") }
                return
            }
            
            // MODIFIED: Added self. prefix to analyzeMeanColorIncrease
            let result = self.analyzeMeanColorIncrease(baseline: baseline, active: activeFrameCopy, faceBounds: faceBox)
            
            DispatchQueue.main.async {
                self.onFlashColorChange(.black)
                self.handleAnalysisCompletion(result: result)
            }
        }
        
        // MODIFIED: Added self. prefix
        private func detectFace(in pixelBuffer: CVPixelBuffer, completion: @escaping (CGRect?) -> Void) {
            let request = VNDetectFaceRectanglesRequest { (request, error) in
                guard let firstResult = (request.results as? [VNFaceObservation])?.first else {
                    completion(nil); return
                }
                let bounds = VNImageRectForNormalizedRect(firstResult.boundingBox, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer))
                completion(bounds)
            }
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
        }
        
        // MODIFIED: Added self. prefix
        private func analyzeMeanColorIncrease(baseline: CVPixelBuffer, active: CVPixelBuffer, faceBounds: CGRect) -> (cyan: Float, magenta: Float, yellow: Float) {
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
                        
                        let baseR = Float(baselinePtr[offset + 2]) / 255.0; let baseG = Float(baselinePtr[offset + 1]) / 255.0; let baseB = Float(baselinePtr[offset + 0]) / 255.0
                        baseCSum += (1.0 - baseR); baseMSum += (1.0 - baseG); baseYSum += (1.0 - baseB)

                        let activeR = Float(activePtr[offset + 2]) / 255.0; let activeG = Float(activePtr[offset + 1]) / 255.0; let activeB = Float(activePtr[offset + 0]) / 255.0
                        activeCSum += (1.0 - activeR); activeMSum += (1.0 - activeG); activeYSum += (1.0 - activeB)
                        
                        pixelCount += 1
                    }
                }
            }
            
            guard pixelCount > 0 else { return (0, 0, 0) }

            let increaseC = (activeCSum / pixelCount) - (baseCSum / pixelCount)
            let increaseM = (activeMSum / pixelCount) - (baseMSum / pixelCount)
            let increaseY = (activeYSum / pixelCount) - (baseYSum / pixelCount)

            return (increaseC, increaseM, increaseY)
        }
        
        private func executeNextFlashStep() {
            guard currentStep < colorSequence.count else {
                endLivenessCheck()
                return
            }
            
            DispatchQueue.main.async {
                self.onFlashColorChange(self.colorSequence[self.currentStep])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.parent.shouldCaptureActive = true
                }
            }
        }
        
        private func handleAnalysisCompletion(result: (cyan: Float, magenta: Float, yellow: Float)) {
            guard result.cyan != -1 else {
                self.abortLivenessCheck(reason: "Liveness check failed: No face was detected during the process.")
                return
            }

            var detectedColor = "Inconclusive"
            if result.cyan > result.magenta && result.cyan > result.yellow { detectedColor = "Cyan" }
            else if result.magenta > result.cyan && result.magenta > result.yellow { detectedColor = "Magenta" }
            else if result.yellow > result.cyan && result.yellow > result.magenta { detectedColor = "Yellow" }
            
            let expectedColor = self.colorToString(self.colorSequence[self.currentStep]) // <<< Fix 4
            self.sessionResults.append((expected: expectedColor, detected: detectedColor))
            
            self.currentStep += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeNextFlashStep()
            }
        }
        
        private func abortLivenessCheck(reason: String) {
            DispatchQueue.main.async {
                self.viewModel.colorFlashLivenessCompleted(wasSuccessful: false, report: reason, baselineImage: nil)
                self.currentStep = 0
                self.sessionResults.removeAll()
                self.colorSequence.removeAll()
                self.onFlashColorChange(.black)
                self.parent.shouldCaptureBaseline = false
                self.parent.shouldCaptureActive = false
            }
        }
        
        private func endLivenessCheck() {
            DispatchQueue.main.async {
                self.onFlashColorChange(.black)
                
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
                
                self.viewModel.colorFlashLivenessCompleted(
                    wasSuccessful: wasSuccessful,
                    report: report,
                    baselineImage: self.viewModel.selfieImage
                )
                self.currentStep = 0
                self.sessionResults.removeAll()
                self.colorSequence.removeAll()
                self.parent.shouldCaptureBaseline = false
                self.parent.shouldCaptureActive = false
            }
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
