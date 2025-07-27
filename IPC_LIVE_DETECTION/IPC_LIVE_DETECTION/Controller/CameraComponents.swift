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

struct LivenessCameraView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: EKYCViewModel
    @Binding var shouldCaptureBaselineSelfie: Bool // To capture the initial baseline selfie for APIs
    @Binding var shouldCaptureActiveFrameForAnalysis: Bool // To request an active frame for color analysis

    var onFlashColorChange: (Color) -> Void // For updating flash color in SwiftUI View


    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.cameraPosition = .front
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        context.coordinator.parent = self
        context.coordinator.viewModelColorFlashLivenessStatus = viewModel.colorFlashLivenessStatus
        context.coordinator.shouldCaptureBaselineSelfieBinding = $shouldCaptureBaselineSelfie
        context.coordinator.shouldCaptureActiveFrameForAnalysisBinding = $shouldCaptureActiveFrameForAnalysis
        context.coordinator.obstructionModel = viewModel.obstructionModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, viewModel: viewModel, onFlashColorChange: onFlashColorChange, shouldCaptureBaselineSelfieBinding: $shouldCaptureBaselineSelfie, shouldCaptureActiveFrameForAnalysisBinding: $shouldCaptureActiveFrameForAnalysis, obstructionModel: viewModel.obstructionModel)
    }

    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: LivenessCameraView
        var viewModel: EKYCViewModel
        var onFlashColorChange: (Color) -> Void

        // Bindings for Coordinator to trigger requests in CameraView
        var shouldCaptureBaselineSelfieBinding: Binding<Bool>
        var shouldCaptureActiveFrameForAnalysisBinding: Binding<Bool>


        var obstructionModel: VNCoreMLModel

        // Local state for liveness check, managed by Coordinator
        private var faceBoundingBox: CGRect?
        private var snappedBaselineSelfie: UIImage? // Store the baseline selfie for color analysis
        private var lastRealtimeAnalysisTime: TimeInterval = 0
        private let realtimeAnalysisThrottleInterval: TimeInterval = 0.25
        
        // Color flash specific states
        private var colorSequence: [Color] = []
        private var sessionResults: [(expected: String, detected: String)] = []
        private var currentStep = 0


        // This property allows the Coordinator to react to ViewModel state changes for color flash
        var viewModelColorFlashLivenessStatus: ColorFlashLivenessProcessStatus = .pending {
            didSet {
                if viewModelColorFlashLivenessStatus.isProcessing && !oldValue.isProcessing {
                    self.startColorFlashSequence()
                }
            }
        }

        init(parent: LivenessCameraView, viewModel: EKYCViewModel, onFlashColorChange: @escaping (Color) -> Void, shouldCaptureBaselineSelfieBinding: Binding<Bool>, shouldCaptureActiveFrameForAnalysisBinding: Binding<Bool>, obstructionModel: VNCoreMLModel) {
            self.parent = parent
            self.viewModel = viewModel
            self.onFlashColorChange = onFlashColorChange
            self.shouldCaptureBaselineSelfieBinding = shouldCaptureBaselineSelfieBinding
            self.shouldCaptureActiveFrameForAnalysisBinding = shouldCaptureActiveFrameForAnalysisBinding
            self.obstructionModel = obstructionModel
            super.init()
        }
        
        func didCaptureFrame(_ frame: CVPixelBuffer) {
            DispatchQueue.main.async { // Ensure all UI-related updates and ViewModel access are on MainActor
                // Run real-time face detection/obstruction analysis continuously if overall process is pending
                if self.viewModel.overallProcessStatus.isPending {
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.runRealtimeFaceAndObstructionAnalysis(frame: frame)
                    }
                }
                
                // Capture baseline selfie if trigger is set and face is detected
                if self.shouldCaptureBaselineSelfieBinding.wrappedValue && self.viewModel.isFaceDetected && self.snappedBaselineSelfie == nil {
                    self.shouldCaptureBaselineSelfieBinding.wrappedValue = false // Consume the trigger
                    self.snapBaselineSelfie(frame: frame)
                }

                // If color flash sequence is in progress, capture active frames during flashes
                if self.viewModel.colorFlashLivenessStatus.isProcessing {
                    if self.shouldCaptureActiveFrameForAnalysisBinding.wrappedValue {
                        self.shouldCaptureActiveFrameForAnalysisBinding.wrappedValue = false // Consume the trigger
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.captureActiveFrameAndAnalyze(frame: frame)
                        }
                    }
                }
            }
        }
        
        // Real-time analysis for face detection and obstruction (renamed for clarity)
        private func runRealtimeFaceAndObstructionAnalysis(frame: CVPixelBuffer) {
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastRealtimeAnalysisTime > realtimeAnalysisThrottleInterval else { return }
            lastRealtimeAnalysisTime = currentTime
            
            let faceRequest = VNDetectFaceRectanglesRequest { (request, error) in
                let faceDetected = (request.results as? [VNFaceObservation])?.first != nil
                DispatchQueue.main.async { // Update ViewModel on MainActor
                    self.viewModel.isFaceDetected = faceDetected
                }
            }
            
            let obstructionRequest = VNCoreMLRequest(model: self.obstructionModel) { (request, error) in
                let obstructionResult = (request.results as? [VNClassificationObservation])?.first?.identifier ?? "Error"
                DispatchQueue.main.async { // Update ViewModel on MainActor
                    self.viewModel.obstructionResult = obstructionResult
                }
            }
            
            try? VNImageRequestHandler(cvPixelBuffer: frame, options: [:]).perform([faceRequest, obstructionRequest])
        }

        // NEW: Function to snap the baseline selfie (for APIs and color analysis)
        private func snapBaselineSelfie(frame: CVPixelBuffer) {
            print("Coordinator: Capturing baseline selfie.")
            guard let frameCopy = frame.deepCopied() else {
                DispatchQueue.main.async {
                    self.viewModel.overallProcessStatus = .error(message: "Failed to capture baseline selfie for color flash/APIs.")
                }
                return
            }
            let ciImage = CIImage(cvPixelBuffer: frameCopy)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right) // Ensure correct orientation for front camera
                self.snappedBaselineSelfie = uiImage // Store for color analysis baseline
                
                // Get face bounding box for this selfie immediately
                self.detectFace(in: frameCopy) { [weak self] (faceBounds: CGRect?) in
                    guard let self = self else { return }
                    DispatchQueue.main.async { // Ensure main thread for ViewModel calls
                        if let bounds = faceBounds {
                            self.faceBoundingBox = bounds
                            print("Coordinator: Baseline selfie snapped, face bounds detected.")
                            // Pass the snapped selfie to ViewModel, but don't initiate APIs from here.
                            // The APIs are initiated in ViewModel.colorFlashSequenceCompleted.
                        } else {
                            print("Coordinator: No face detected in snapped baseline selfie.")
                            self.viewModel.overallProcessStatus = .error(message: "No face detected in snapped selfie. Please try again.")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.viewModel.overallProcessStatus = .error(message: "Failed to process baseline selfie image.")
                }
            }
        }

        // MARK: - Color Flash Liveness Step Management
        
        private func startColorFlashSequence() {
            print("Coordinator: Starting color flash sequence.")
            sessionResults.removeAll()
            currentStep = 0
            generateColorSequence()
            
            // Immediately trigger the first frame capture for color analysis
            DispatchQueue.main.async { // Set Binding on MainActor
                self.executeNextFlashStep()
            }
        }
        
        private func generateColorSequence() {
            let possibleColors: [Color] = [Color(UIColor.cyan), Color(UIColor.magenta), .yellow]
            self.colorSequence = (0..<6).map { _ in possibleColors.randomElement()! }
        }
        
        private func captureActiveFrameAndAnalyze(frame: CVPixelBuffer) {
            guard let baselineSelfie = self.snappedBaselineSelfie, // Use the stored baseline selfie
                  let faceBox = self.faceBoundingBox else { // Use the bounding box from initial snap's analysis
                DispatchQueue.main.async { self.abortLivenessCheck(reason: "Missing selfie baseline or face data for active frame.") }
                return
            }
            
            guard let baselinePixelBuffer = self.pixelBuffer(from: baselineSelfie),
                  let activeFrameCopy = frame.deepCopied() else {
                DispatchQueue.main.async { self.abortLivenessCheck(reason: "Could not create pixel buffer from baseline selfie or deep copy active frame.") }
                return
            }

            let result = self.analyzeMeanColorIncrease(baseline: baselinePixelBuffer, active: activeFrameCopy, faceBounds: faceBox)
            
            DispatchQueue.main.async { // Update UI and process results on MainActor
                self.onFlashColorChange(.black) // Immediately turn screen black after analysis
                self.handleAnalysisCompletion(result: result)
            }
        }
        
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

        private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
            let ciImage = CIImage(image: image)
            guard let cgImage = CIContext().createCGImage(ciImage!, from: ciImage!.extent) else { return nil }

            let width = cgImage.width
            let height = cgImage.height

            var pixelBuffer: CVPixelBuffer?
            let attributes = [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
            ] as CFDictionary

            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)
            guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
                return nil
            }

            CVPixelBufferLockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let pixelData = CVPixelBufferGetBaseAddress(unwrappedPixelBuffer)

            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(unwrappedPixelBuffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

            return unwrappedPixelBuffer
        }
        
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
            
            DispatchQueue.main.async { // Update UI on MainActor
                self.onFlashColorChange(self.colorSequence[self.currentStep])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { // Set Binding on MainActor
                    self.shouldCaptureActiveFrameForAnalysisBinding.wrappedValue = true // Corrected name
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
            
            let expectedColor = self.colorToString(self.colorSequence[self.currentStep])
            self.sessionResults.append((expected: expectedColor, detected: detectedColor))
            
            self.currentStep += 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.executeNextFlashStep()
            }
        }
        
        private func abortLivenessCheck(reason: String) {
            DispatchQueue.main.async { // Call ViewModel method on MainActor
                self.viewModel.colorFlashSequenceCompleted(wasSuccessful: false, report: reason, snappedSelfie: self.snappedBaselineSelfie) // Pass selfie
                // Reset local state if necessary
                self.currentStep = 0
                self.sessionResults.removeAll()
                self.colorSequence.removeAll()
                self.onFlashColorChange(.black) // Ensure flash is off
                self.shouldCaptureBaselineSelfieBinding.wrappedValue = false // Reset baseline capture
                // MODIFIED: Removed the line causing the error
                self.shouldCaptureActiveFrameForAnalysisBinding.wrappedValue = false // Reset active capture
                self.snappedBaselineSelfie = nil // Clear stored selfie
            }
        }
        
        private func endLivenessCheck() {
            DispatchQueue.main.async { // Call ViewModel method on MainActor
                self.onFlashColorChange(.black) // Ensure flash is off
                
                var report = "Color Flash Liveness Analysis Complete:\n\n"
                var successCount = 0
                for (index, result) in self.sessionResults.enumerated() {
                    let status = result.expected.lowercased() == result.detected.lowercased() ? "✅" : "❌"
                    if status == "✅" { successCount += 1 }
                    report += "Flash \(index + 1): Expected \(result.expected), Detected \(result.detected) \(status)\n"
                }
                
                let wasSuccessful = successCount >= 4 // Example success condition
                let finalStatus = wasSuccessful ? "Liveness Confirmed" : "Liveness Failed"
                report += "\nFinal Result: \(finalStatus)"
                
                self.viewModel.colorFlashSequenceCompleted(
                    wasSuccessful: wasSuccessful,
                    report: report,
                    snappedSelfie: self.snappedBaselineSelfie // Pass selfie
                )
                // Reset local state if necessary
                self.currentStep = 0
                self.sessionResults.removeAll()
                self.colorSequence.removeAll()
                self.shouldCaptureBaselineSelfieBinding.wrappedValue = false
                // MODIFIED: Removed the line causing the error
                self.shouldCaptureActiveFrameForAnalysisBinding.wrappedValue = false
                self.snappedBaselineSelfie = nil // Clear stored selfie
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
