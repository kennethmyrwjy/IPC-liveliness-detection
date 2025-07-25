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
                        // --- FIX IS HERE ---
                        // Create the UIImage with the correct orientation
                        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
                        self.parent.onCaptured(uiImage)
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

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        controller.cameraPosition = .front
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: LivenessCameraView
        private var faceBoundingBox: CGRect?
        private var baselineFrame: CVPixelBuffer?
        private var lastAnalysisTime: TimeInterval = 0
        private let analysisThrottleInterval: TimeInterval = 0.25

        init(parent: LivenessCameraView) {
            self.parent = parent
            super.init()
        }
        
        func didCaptureFrame(_ frame: CVPixelBuffer) {
            DispatchQueue.main.async {
                switch self.parent.viewModel.livenessStatus {
                case .pending:
                    self.runPendingAnalysis(frame: frame)
                case .inProgress:
                    self.runLivenessStep(frame: frame)
                default:
                    break
                }
            }
        }
        
        private func runPendingAnalysis(frame: CVPixelBuffer) {
            let currentTime = CACurrentMediaTime()
            guard currentTime - lastAnalysisTime > analysisThrottleInterval else { return }
            lastAnalysisTime = currentTime
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.performRealTimeAnalysis(on: frame)
            }
        }
        
        private func performRealTimeAnalysis(on frame: CVPixelBuffer) {
            let faceRequest = VNDetectFaceRectanglesRequest { (request, error) in
                let faceDetected = (request.results as? [VNFaceObservation])?.first != nil
                DispatchQueue.main.async {
                    self.parent.viewModel.isFaceDetected = faceDetected
                }
            }
            
            let obstructionRequest = VNCoreMLRequest(model: self.parent.viewModel.obstructionModel) { (request, error) in
                let obstructionResult = (request.results as? [VNClassificationObservation])?.first?.identifier ?? "Error"
                DispatchQueue.main.async {
                    self.parent.viewModel.obstructionResult = obstructionResult
                }
            }
            
            try? VNImageRequestHandler(cvPixelBuffer: frame, options: [:]).perform([faceRequest, obstructionRequest])
        }

        @MainActor private func runLivenessStep(frame: CVPixelBuffer) {
            if parent.shouldCaptureBaseline {
                parent.shouldCaptureBaseline = false
                
                guard let frameCopy = frame.deepCopied() else { return }
                self.baselineFrame = frameCopy
                
                let ciImage = CIImage(cvPixelBuffer: frameCopy)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    self.parent.viewModel.selfieImage = UIImage(cgImage: cgImage)
                }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    self.detectFace(in: frameCopy) { [weak self] faceBounds in
                        guard let self = self else { return }
                        if let bounds = faceBounds {
                            self.faceBoundingBox = bounds
                            DispatchQueue.main.async { self.parent.onBaselineCaptured() }
                        } else {
                            DispatchQueue.main.async { self.parent.onAnalysisComplete((-1, -1, -1)) }
                        }
                    }
                }
            } else if parent.shouldCaptureActive {
                parent.shouldCaptureActive = false
                
                guard let baseline = self.baselineFrame,
                      let faceBox = self.faceBoundingBox,
                      let activeFrameCopy = frame.deepCopied() else {
                    return
                }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = self.analyzeMeanColorIncrease(baseline: baseline, active: activeFrameCopy, faceBounds: faceBox)
                    DispatchQueue.main.async {
                        self.parent.onAnalysisComplete(result)
                    }
                }
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
