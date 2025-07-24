import SwiftUI
import AVFoundation
import UIKit
import VideoToolbox
import Vision

// MARK: - Main SwiftUI View for eKYC
struct ContentView: View {
    // State to manage the liveness check process
    @State private var isCheckingLiveness = false

    // The color for the full-screen flash overlay.
    @State private var flashColor: Color = .black

    // The randomly generated sequence of colors to flash
    @State private var colorSequence: [Color] = []

    // A collection to store the detailed results of each step for a final report
    @State private var sessionResults: [(expected: String, detected: String, increases: (c: Float, m: Float, y: Float))] = []

    // The current step in the color sequence
    @State private var currentStep = 0

    // To store and restore the user's original screen brightness
    @State private var originalBrightness: CGFloat = UIScreen.main.brightness

    // Flags to signal the CameraView to perform analysis on the next frames
    @State private var shouldCaptureAndDetectFace = false
    @State private var shouldCaptureActive = false

    // State to hold the text result of the analysis
    @State private var analysisResultText: String = "Analysis results will appear here"

    var body: some View {
        ZStack {
            // Layer 1: Full-Screen Flash Overlay
            flashColor
                .ignoresSafeArea()
                .animation(.easeIn(duration: 0.1), value: flashColor)

            // Layer 2: Camera View and UI
            VStack(spacing: 0) {
                Text("Position Your Face in the Circle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 50)

                CameraView(
                    shouldCaptureAndDetectFace: $shouldCaptureAndDetectFace,
                    shouldCaptureActive: $shouldCaptureActive,
                    currentStep: $currentStep,
                    onAnalysisComplete: { result in
                        // This closure is the central point of control for the sequence.
                        
                        // 1. Turn off the flash as soon as analysis is received.
                        self.flashColor = .black
                        
                        // 2. Process the analysis results
                        let (cyanIncrease, magentaIncrease, yellowIncrease) = result
                        
                        // Handle the case where face detection failed.
                        if cyanIncrease == -1 && magentaIncrease == -1 && yellowIncrease == -1 {
                            self.analysisResultText = "Liveness check failed: No face was detected. Please try again."
                            self.abortLivenessCheck()
                            return
                        }
                        
                        var detectedColor = "Inconclusive"
                        if cyanIncrease > magentaIncrease && cyanIncrease > yellowIncrease {
                            detectedColor = "Cyan"
                        } else if magentaIncrease > cyanIncrease && magentaIncrease > yellowIncrease {
                            detectedColor = "Magenta"
                        } else if yellowIncrease > cyanIncrease && yellowIncrease > magentaIncrease {
                            detectedColor = "Yellow"
                        }
                        
                        // 3. Get the expected color and store the full result for this step.
                        let expectedColor = colorToString(colorSequence[currentStep])
                        let stepResult = (expected: expectedColor, detected: detectedColor, increases: (c: cyanIncrease, m: magentaIncrease, y: yellowIncrease))
                        self.sessionResults.append(stepResult)
                        
                        // Log the results for debugging
                        print("Flash \(currentStep + 1) Result: Expected \(expectedColor), Detected \(detectedColor) | Avg Increases: C:\(String(format: "%.4f", cyanIncrease)), M:\(String(format: "%.4f", magentaIncrease)), Y:\(String(format: "%.4f", yellowIncrease))")

                        // 4. Increment the step counter
                        self.currentStep += 1
                        
                        // 5. Trigger the next step after a brief pause.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.executeNextFlashStep()
                        }
                    },
                    onFaceDetected: {
                        // This is the implementation for our new closure.
                        // It's called from the Coordinator when a face is found.
                        self.executeNextFlashStep()
                    }
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: 300, height: 300)
                .clipShape(Circle())
                .overlay(Circle().stroke(isCheckingLiveness ? Color.yellow : Color.white, lineWidth: 4))
                .padding(.vertical, 20)
                
                // Display the analysis result as text
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                    Text(analysisResultText)
                        .foregroundColor(.white)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .padding()
                }
                .frame(minHeight: 140)
                .padding(.horizontal)
                
                Spacer()
                
                Button(action: startLivenessCheck) {
                    Text(isCheckingLiveness ? "Checking..." : "Start Liveness Check")
                        .font(.title2).fontWeight(.bold).foregroundColor(.white).padding()
                        .frame(maxWidth: .infinity)
                        .background(isCheckingLiveness ? Color.gray : Color.blue)
                        .cornerRadius(15).shadow(radius: 5)
                }
                .disabled(isCheckingLiveness)
                .padding()
            }
        }
        .onAppear {
            flashColor = .black
        }
    }
    
    // MARK: - Liveness Check Logic
    
    private func startLivenessCheck() {
        isCheckingLiveness = true
        analysisResultText = "Detecting face... Please hold still."
        sessionResults.removeAll()
        currentStep = 0
        originalBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
        generateColorSequence()
        
        // This is the first step: capture a frame and find the face in it.
        // The rest of the sequence is driven by the completion handlers.
        shouldCaptureAndDetectFace = true
    }
    
    private func generateColorSequence() {
        let possibleColors: [Color] = [Color(uiColor: .cyan), Color(uiColor: .magenta), .yellow]
        
        // Create a new sequence of 6 colors by randomly picking from the pool each time.
        self.colorSequence = (0..<6).map { _ in
            // .randomElement()! safely returns a random color because the `possibleColors` array is not empty.
            possibleColors.randomElement()!
        }
    }
    
    private func executeNextFlashStep() {
        // If all steps are done, call the end function.
        guard currentStep < colorSequence.count else {
            endLivenessCheck()
            return
        }
        
        // This function now only triggers the flash and the active frame capture.
        analysisResultText = "Flashing \(colorToString(colorSequence[currentStep]))..."
        
        // Flash the color
        self.flashColor = self.colorSequence[currentStep]
        
        // After a very short delay to let the screen update, signal to capture the active frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // Increased duration for better visibility
            self.shouldCaptureActive = true
        }
    }
    
    // Function to gracefully abort the process (e.g., if no face is found).
    private func abortLivenessCheck() {
        UIScreen.main.brightness = self.originalBrightness
        self.isCheckingLiveness = false
        self.colorSequence = []
        self.currentStep = 0
        self.flashColor = .black
    }
    
    private func endLivenessCheck() {
        UIScreen.main.brightness = self.originalBrightness
        
        // Generate and display the final report
        var report = "Analysis Complete:\n\n"
        var successCount = 0
        for (index, result) in sessionResults.enumerated() {
            let status = result.expected == result.detected ? "✅" : "❌"
            if result.expected == result.detected { successCount += 1 }
            let valuesString = String(format: "C:%.3f, M:%.3f, Y:%.3f", result.increases.c, result.increases.m, result.increases.y)
            report += "Flash \(index + 1): \(result.expected) -> \(result.detected) \(status)\n"
            report += "  └ Avg. Increase: \(valuesString)\n"
        }
        
        // ADJUSTED: The success condition now requires at least 4 matches for a 6-flash sequence.
        let finalStatus = successCount >= 4 ? "Liveness Confirmed" : "Liveness Failed"
        report += "\nFinal Result: \(finalStatus)"
        
        self.analysisResultText = report
        
        // Reset state variables
        self.isCheckingLiveness = false
        self.colorSequence = []
        self.currentStep = 0
        self.flashColor = .black
    }
    
    private func colorToString(_ color: Color) -> String {
        switch color {
        case Color(uiColor: .cyan): return "Cyan"
        case Color(uiColor: .magenta): return "Magenta"
        case .yellow: return "Yellow"
        default: return "Unknown"
        }
    }
}


// MARK: - Camera View Controller (AVFoundation & Vision Bridge)
struct CameraView: UIViewControllerRepresentable {
    @Binding var shouldCaptureAndDetectFace: Bool
    @Binding var shouldCaptureActive: Bool
    @Binding var currentStep: Int // Receive the binding for the current step
    // The completion handler for color analysis results
    var onAnalysisComplete: ((cyanIncrease: Float, magentaIncrease: Float, yellowIncrease: Float)) -> Void
    // A closure to call when the initial face detection is successful
    var onFaceDetected: () -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        // Pass the new onFaceDetected closure to the Coordinator
        Coordinator(self, onAnalysisComplete: onAnalysisComplete, onFaceDetected: onFaceDetected)
    }

    // MARK: - Coordinator (The Core Logic)
    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: CameraView
        var onAnalysisComplete: ((cyanIncrease: Float, magentaIncrease: Float, yellowIncrease: Float)) -> Void
        // Store the onFaceDetected closure
        var onFaceDetected: () -> Void

        private var baselineFrame: CVPixelBuffer?
        private var faceBoundingBox: CGRect? // To store the detected face rectangle

        // The initializer now accepts the new closure
        init(_ parent: CameraView, onAnalysisComplete: @escaping ((cyanIncrease: Float, magentaIncrease: Float, yellowIncrease: Float)) -> Void, onFaceDetected: @escaping () -> Void) {
            self.parent = parent
            self.onAnalysisComplete = onAnalysisComplete
            self.onFaceDetected = onFaceDetected // Store it
        }

        func didCaptureFrame(_ frame: CVPixelBuffer) {
            // --- Step 1: Capture Baseline and Detect Face ---
            if parent.shouldCaptureAndDetectFace {
                parent.shouldCaptureAndDetectFace = false // Reset the flag

                guard let frameCopy = frame.deepCopied() else { return }
                self.baselineFrame = frameCopy
                
                // SAVE THE BASELINE IMAGE (this part is correct)
                self.save(pixelBuffer: frameCopy, name: "baseline")

                // Perform face detection
                detectFace(in: frameCopy) { [weak self] faceBounds in
                    guard let self = self else { return }

                    if let faceBounds = faceBounds {
                        self.faceBoundingBox = faceBounds
                        print("Face detected at: \(faceBounds)")
                        DispatchQueue.main.async {
                            self.onFaceDetected()
                        }
                    } else {
                        print("No face detected.")
                        DispatchQueue.main.async {
                            self.onAnalysisComplete((-1, -1, -1))
                        }
                    }
                }
                return
            }

            // --- Step 2: Capture Active Frame and Analyze (CORRECTED LOGIC) ---
            if parent.shouldCaptureActive {
                parent.shouldCaptureActive = false // Reset the flag

                // Ensure we have a baseline frame and a detected face before proceeding
                guard let baseline = self.baselineFrame,
                      let faceBox = self.faceBoundingBox,
                      // Create a safe, deep copy of the active frame to use for both saving and analysis
                      let activeFrameCopy = frame.deepCopied() else {
                    print("Analysis aborted: Missing baseline, face box, or failed to copy active frame.")
                    return
                }

                // Perform both saving and analysis on the same copied frame in the background
                DispatchQueue.global(qos: .userInitiated).async {
                    // 1. SAVE THE ACTIVE (FLASHED) IMAGE
                    // This now saves the correct, copied frame.
                    self.save(pixelBuffer: activeFrameCopy, name: "active_\(self.parent.currentStep)")

                    // 2. ANALYZE THE SAME FRAME
                    let result = self.analyzeMeanColorIncrease(baseline: baseline, active: activeFrameCopy, faceBounds: faceBox)

                    // 3. Switch back to the main thread to update the UI
                    DispatchQueue.main.async {
                        self.onAnalysisComplete(result)
                    }
                }
            }
        }
        
        /// Converts a CVPixelBuffer to a UIImage and saves it to the photo album.
        private func save(pixelBuffer: CVPixelBuffer, name: String) {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                print("Error: Could not create CGImage from CVPixelBuffer.")
                return
            }
            let uiImage = UIImage(cgImage: cgImage)

            UIImageWriteToSavedPhotosAlbum(uiImage, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
            print("Attempting to save image: \(name)")
        }

        /// Callback function for UIImageWriteToSavedPhotosAlbum.
        @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
            if let error = error {
                print("Error saving photo: \(error.localizedDescription)")
            } else {
                print("Photo saved successfully to album.")
            }
        }


        // Face Detection using Vision
        private func detectFace(in pixelBuffer: CVPixelBuffer, completion: @escaping (CGRect?) -> Void) {
            let request = VNDetectFaceRectanglesRequest { (request, error) in
                guard error == nil, let results = request.results as? [VNFaceObservation], let firstResult = results.first else {
                    completion(nil)
                    return
                }

                // Convert normalized Vision coordinates to pixel coordinates
                let bounds = VNImageRectForNormalizedRect(firstResult.boundingBox,
                                                          CVPixelBufferGetWidth(pixelBuffer),
                                                          CVPixelBufferGetHeight(pixelBuffer))
                completion(bounds)
            }

            do {
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
            } catch {
                print("Failed to perform Vision request: \(error)")
                completion(nil)
            }
        }

        // This function implements the logic from the Python script.
        private func analyzeMeanColorIncrease(baseline: CVPixelBuffer, active: CVPixelBuffer, faceBounds: CGRect) -> (cyanIncrease: Float, magentaIncrease: Float, yellowIncrease: Float) {
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

            // Ellipse parameters from the face bounding box
            let ellipseCenterX = Float(faceBounds.midX)
            let ellipseCenterY = Float(faceBounds.midY)
            let radiusX = Float(faceBounds.width / 2)
            let radiusY = Float(faceBounds.height / 2)

            var baseCSum: Float = 0, baseMSum: Float = 0, baseYSum: Float = 0
            var activeCSum: Float = 0, activeMSum: Float = 0, activeYSum: Float = 0
            var pixelCount: Float = 0

            // Iterate only over the pixels within the face's bounding box
            for y in Int(faceBounds.minY)..<Int(faceBounds.maxY) {
                for x in Int(faceBounds.minX)..<Int(faceBounds.maxX) {

                    // Check if the pixel is inside the ellipse
                    let dx = Float(x) - ellipseCenterX
                    let dy = Float(y) - ellipseCenterY
                    if (dx*dx)/(radiusX*radiusX) + (dy*dy)/(radiusY*radiusY) <= 1 {

                        let offset = y * bytesPerRow + x * 4

                        // --- Calculate CMY for Baseline Frame ---
                        let baseR = Float(baselinePtr[offset + 2]) / 255.0
                        let baseG = Float(baselinePtr[offset + 1]) / 255.0
                        let baseB = Float(baselinePtr[offset]) / 255.0
                        baseCSum += (1.0 - baseR)
                        baseMSum += (1.0 - baseG)
                        baseYSum += (1.0 - baseB)

                        // --- Calculate CMY for Active Frame ---
                        let activeR = Float(activePtr[offset + 2]) / 255.0
                        let activeG = Float(activePtr[offset + 1]) / 255.0
                        let activeB = Float(activePtr[offset]) / 255.0
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
    }
}

// MARK: - Delegate and CameraViewController
protocol CameraViewControllerDelegate: AnyObject {
    func didCaptureFrame(_ frame: CVPixelBuffer)
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    weak var delegate: CameraViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        captureSession = AVCaptureSession()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() }
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

// MARK: - CVPixelBuffer Extension
extension CVPixelBuffer {
    /// Creates a deep copy of the CVPixelBuffer. This is crucial because the buffer from the
    /// capture output is reused by the system, so we need our own copy to analyze later.
    func deepCopied() -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let format = CVPixelBufferGetPixelFormatType(self)
        var pixelBufferCopy: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes, &pixelBufferCopy)

        guard status == kCVReturnSuccess, let copy = pixelBufferCopy else { return nil }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }

        guard let source = CVPixelBufferGetBaseAddress(self), let dest = CVPixelBufferGetBaseAddress(copy) else {
            return nil
        }

        let dataSize = CVPixelBufferGetDataSize(self)
        memcpy(dest, source, dataSize)

        return copy
    }
}
