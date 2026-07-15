import AVFoundation
import UIKit

enum CameraError: Error, LocalizedError {
    case accessDenied
    case deviceUnavailable
    case captureFailed(Error)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Camera access was denied. Enable it in Settings to take photos."
        case .deviceUnavailable:
            return "No camera is available on this device."
        case .captureFailed(let error):
            return "Couldn't take the photo: \(error.localizedDescription)"
        }
    }
}

/// Thin wrapper around AVCaptureSession providing a live camera preview and
/// single-photo capture, similar to the "viewfinder" screen described for
/// ScreenshotMatcher's Android app.
///
/// All AVCaptureSession calls (`beginConfiguration`, `startRunning`, etc.)
/// happen on a dedicated serial queue, as required by AVFoundation — mixing
/// them with MainActor-isolated access caused corrupted capture sessions
/// (CoreMedia `FigCaptureSourceRemote` errors) on device.
final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published @MainActor var isAuthorized = false
    @Published @MainActor var setupError: CameraError?

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false
    @MainActor private var captureContinuation: CheckedContinuation<UIImage, Error>?

    func configureIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let authorized: Bool
        switch status {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }

        await MainActor.run { self.isAuthorized = authorized }
        guard authorized else {
            await MainActor.run { self.setupError = .accessDenied }
            return
        }

        let deviceAvailable = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async { [weak self] in
                let ok = self?.setUpSessionIfNeeded() ?? false
                continuation.resume(returning: ok)
            }
        }
        if !deviceAvailable {
            await MainActor.run { self.setupError = .deviceUnavailable }
        }
    }

    /// Must only be called on `sessionQueue`. Returns false if no camera
    /// device could be attached.
    private func setUpSessionIfNeeded() -> Bool {
        guard !isConfigured else {
            if !session.isRunning { session.startRunning() }
            return true
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        var deviceAttached = false
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            deviceAttached = true
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        isConfigured = deviceAttached
        if deviceAttached {
            session.startRunning()
        }
        return deviceAttached
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    @MainActor
    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error {
                captureContinuation?.resume(throwing: CameraError.captureFailed(error))
                captureContinuation = nil
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                captureContinuation?.resume(throwing: UploadError.badResponse)
                captureContinuation = nil
                return
            }
            captureContinuation?.resume(returning: image)
            captureContinuation = nil
        }
    }
}
