import AVFoundation
import UIKit

/// Manages AVCaptureSession for full-screen camera preview and photo capture.
/// Uses a dedicated queue for session start/stop to avoid blocking the main thread.
final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onImagePicked: ((CapturedImageInfo) -> Void)?
    var onPreviewReady: (() -> Void)?
    var preWarmedSession: AVCaptureSession?
    var preWarmedPhotoOutput: AVCapturePhotoOutput?

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var lastShutterTrigger = 0
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if let session = preWarmedSession {
            captureSession = session
            photoOutput = preWarmedPhotoOutput
            sessionQueue.async { [weak self] in
                self?.attachPreviewLayer()
            }
        } else {
            sessionQueue.async { [weak self] in
                self?.setupCamera()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    func handleShutterTrigger(_ trigger: Int) {
        guard trigger > lastShutterTrigger else { return }
        lastShutterTrigger = trigger
        capturePhoto()
    }

    private func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .high  // 1080p for faster startup than .photo (12MP)

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            DispatchQueue.main.async { [weak self] in self?.onPreviewReady?() }
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        captureSession = session
        photoOutput = output

        DispatchQueue.main.async { [weak self] in
            guard let self, let session = self.captureSession else { return }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.view.bounds
            self.view.layer.addSublayer(layer)
            self.previewLayer = layer
            self.onPreviewReady?()
        }
    }

    /// Attaches preview layer to pre-warmed session. Runs on sessionQueue.
    private func attachPreviewLayer() {
        guard let session = captureSession else { return }
        if photoOutput == nil {
            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                photoOutput = output
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.view.bounds
            self.view.layer.addSublayer(layer)
            self.previewLayer = layer
            self.onPreviewReady?()
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        let previewSize = previewLayer?.bounds.size
        let info = CapturedImageInfo(image: image, previewSize: previewSize)
        DispatchQueue.main.async { [weak self] in
            self?.onImagePicked?(info)
        }
    }
}
