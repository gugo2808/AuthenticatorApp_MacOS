import AVFoundation
import Vision
import SwiftUI

// MARK: - Coordinator (sample buffer delegate + Vision)

final class QRScannerCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onDetect: (String) -> Void
    var onPermissionDenied: () -> Void

    private var isProcessing = false
    private var lastPayload: String?
    private var lastDetectedAt: Date?
    // Cooldown stops the same QR being re-imported while the user holds camera steady.
    // Different QRs are accepted immediately.
    private let sameQRCooldown: TimeInterval = 2.5
    private let visionQueue = DispatchQueue(label: "com.authenticatorapp.vision", qos: .userInitiated)

    init(onDetect: @escaping (String) -> Void, onPermissionDenied: @escaping () -> Void) {
        self.onDetect = onDetect
        self.onPermissionDenied = onPermissionDenied
    }

    // Called by ImportView after successfully importing a batch QR so this QR
    // won't be re-imported if the user holds the camera on it.
    func markDetected(_ payload: String) {
        lastPayload = payload
        lastDetectedAt = Date()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isProcessing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true

        visionQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try? handler.perform([request])

            guard let obs = request.results?.first as? VNBarcodeObservation,
                  let payload = obs.payloadStringValue,
                  payload.hasPrefix("otpauth://") || payload.hasPrefix("otpauth-migration://") else {
                return
            }

            // Suppress same-QR re-detection within the cooldown window
            if payload == self.lastPayload,
               let t = self.lastDetectedAt, Date().timeIntervalSince(t) < self.sameQRCooldown {
                return
            }

            // Record before dispatching so cooldown activates immediately
            self.lastPayload = payload
            self.lastDetectedAt = Date()
            DispatchQueue.main.async { self.onDetect(payload) }
        }
    }
}

// MARK: - NSView that hosts AVCaptureVideoPreviewLayer

final class QRScannerNSView: NSView {
    let captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

// MARK: - NSViewRepresentable

struct QRScannerView: NSViewRepresentable {
    var onDetect: (String) -> Void
    var onPermissionDenied: () -> Void

    func makeCoordinator() -> QRScannerCoordinator {
        QRScannerCoordinator(onDetect: onDetect, onPermissionDenied: onPermissionDenied)
    }

    func makeNSView(context: Context) -> QRScannerNSView {
        let view = QRScannerNSView()
        checkPermissionAndSetup(view: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: QRScannerNSView, context: Context) {
        context.coordinator.onDetect = onDetect
        context.coordinator.onPermissionDenied = onPermissionDenied
    }

    static func dismantleNSView(_ nsView: QRScannerNSView, coordinator: QRScannerCoordinator) {
        let session = nsView.captureSession
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    // MARK: - Private setup

    private func checkPermissionAndSetup(view: QRScannerNSView, coordinator: QRScannerCoordinator) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession(view: view, coordinator: coordinator)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupSession(view: view, coordinator: coordinator)
                } else {
                    DispatchQueue.main.async { coordinator.onPermissionDenied() }
                }
            }
        default:
            DispatchQueue.main.async { coordinator.onPermissionDenied() }
        }
    }

    private func setupSession(view: QRScannerNSView, coordinator: QRScannerCoordinator) {
        let session = view.captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session.beginConfiguration()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                DispatchQueue.main.async { coordinator.onPermissionDenied() }
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            let sampleQueue = DispatchQueue(label: "com.authenticatorapp.sampleBuffer", qos: .userInitiated)
            output.setSampleBufferDelegate(coordinator, queue: sampleQueue)
            if session.canAddOutput(output) { session.addOutput(output) }

            session.commitConfiguration()
            session.startRunning()

            DispatchQueue.main.async {
                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                preview.frame = view.bounds
                view.wantsLayer = true
                view.layer = preview
                view.previewLayer = preview
            }
        }
    }
}
