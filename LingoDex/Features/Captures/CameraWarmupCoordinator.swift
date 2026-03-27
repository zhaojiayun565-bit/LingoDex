import AVFoundation
import Foundation

/// Pre-configures an AVCaptureSession so the camera opens faster when the user taps capture.
/// Call warmUpIfNeeded when the user is on the Captures tab. consumePreWarmedSession hands off
/// the configured session to the camera view (session can only have one consumer).
final class CameraWarmupCoordinator {
    private let queue = DispatchQueue(label: "camera.warmup")
    private var preWarmedSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var isWarming = false

    /// Starts configuration in background when on Captures tab. Idempotent.
    func warmUpIfNeeded() {
        queue.async { [weak self] in
            guard let self, preWarmedSession == nil, !isWarming else { return }
            isWarming = true
            defer { isWarming = false }

            let session = AVCaptureSession()
            session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }

            session.beginConfiguration()
            session.addInput(input)
            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                photoOutput = output
            }
            session.commitConfiguration()

            preWarmedSession = session
        }
    }

    /// Returns pre-configured session if available. Call from main before showing camera. Session is removed after consumption.
    func consumePreWarmedSession() -> (session: AVCaptureSession, photoOutput: AVCapturePhotoOutput?)? {
        var result: (AVCaptureSession, AVCapturePhotoOutput?)?
        queue.sync {
            if let session = preWarmedSession {
                result = (session, photoOutput)
                preWarmedSession = nil
                photoOutput = nil
            }
        }
        return result
    }
}
