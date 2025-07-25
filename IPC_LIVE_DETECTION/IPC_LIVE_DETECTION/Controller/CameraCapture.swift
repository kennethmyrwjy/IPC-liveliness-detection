import AVFoundation
import CoreML
import Vision
import SwiftUI

public class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var session: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    private var mlModel: VNCoreMLModel!
    private var request: VNCoreMLRequest!
    private var visionHandler: VNImageRequestHandler!
    
    private var desiredResult: String = "plain" // Desired model output to trigger next step
    private let photoOutput = AVCapturePhotoOutput() // Reference to the photo output

    // Completion handler to notify when the desired output is detected
    var onDesiredOutputDetected: ((UIImage) -> Void)?

    override init() {
        super.init()
        
        setupCamera()
        setupModel()
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        // Set up the capture session
        session = AVCaptureSession()
        
        // Set front camera as input device
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera) else {
            print("Failed to get front camera.")
            return
        }
        
        // Add input to session
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Set up output to capture frames from the camera
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        // Add photo output to session
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        // Set up the preview layer to show camera feed on the screen
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = CGRect(x: 0, y: 0, width: 300, height: 300) // Adjust the preview size
    }
    
    // Start capturing live video
    func startCapture() {
        session.startRunning()
    }
    
    // Stop capturing live video
    func stopCapture() {
        session.stopRunning()
    }
    
    // MARK: - Core ML Setup
    private func setupModel() {
        // Load the Core ML model
        guard let model = try? VNCoreMLModel(for: model_obstruction().model) else {
            print("Failed to load the Core ML model.")
            return
        }
        
        // Create the Core ML request
        request = VNCoreMLRequest(model: model) { [weak self] request, error in
            if let error = error {
                print("Error during model inference: \(error.localizedDescription)")
                return
            }
            
            // Get the results from the request
            guard let results = request.results as? [VNClassificationObservation],
                  let bestResult = results.first else {
                print("No results from the model.")
                return
            }
            
            // If the desired result is detected, capture the image and trigger next process
            if bestResult.identifier == self?.desiredResult {
                self?.captureImage()
            }
        }
    }
    
    // Capture the image when desired output is detected
    private func captureImage() {
        // Use the already existing photoOutput (not creating a new one)
        let settings = AVCapturePhotoSettings()
        
        // Capture photo with settings
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - Video Processing
    public func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
        // Convert the sample buffer to a CIImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Perform Core ML inference on the image buffer
        visionHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try visionHandler.perform([request])
        } catch {
            print("Error performing vision request: \(error.localizedDescription)")
        }
    }
}

extension CameraCapture: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error processing photo: \(error.localizedDescription)")
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("Failed to capture image.")
            return
        }

        // Once the image is captured, notify the view controller
        onDesiredOutputDetected?(image)
    }
}

