import SwiftUI
import UIKit

private enum CaptureStage: Equatable {
    case idle
    case capturing
    case uploading
    case done

    var label: String {
        switch self {
        case .idle: return ""
        case .capturing: return "Capturing…"
        case .uploading: return "Sending to host…"
        case .done: return "Sent!"
        }
    }
}

struct CameraView: View {
    @ObservedObject var sentStore: GalleryStore
    @ObservedObject var receivedStore: GalleryStore

    @StateObject private var camera = CameraManager()
    @StateObject private var discovery = DiscoveryService()
    @AppStorage("matchingAlgorithm") private var algorithmRawValue: String = MatchingAlgorithm.orb.rawValue

    @State private var stage: CaptureStage = .idle
    @State private var activeError: AppError?
    @State private var lastResultItem: GalleryItem?
    @State private var showResultToast = false
    @State private var lastLatencyMs: Int?

    var body: some View {
        ZStack {
            cameraBackground

            VStack {
                topBar
                Spacer()
                if let lastResultItem, showResultToast {
                    resultThumbnail(lastResultItem)
                }
                captureButton
            }
            .padding(.bottom, 30)
        }
        .task {
            await camera.configureIfNeeded()
            if let setupError = camera.setupError {
                activeError = AppError(from: setupError)
            }
            discovery.startDiscovery()
        }
        .onDisappear {
            camera.stop()
            discovery.stopDiscovery()
        }
        .alert(item: $activeError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var cameraBackground: some View {
        if camera.isAuthorized {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.6))
                Text("Camera access is required")
                    .foregroundColor(.white)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var topBar: some View {
        HStack {
            ConnectionBadge(discovery: discovery, algorithmRawValue: $algorithmRawValue)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func resultThumbnail(_ item: GalleryItem) -> some View {
        if let image = receivedStore.image(for: item) {
            VStack(spacing: 4) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 90)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 1))
                if let lastLatencyMs {
                    Text("\(lastLatencyMs) ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale))
        }
    }

    private var captureButton: some View {
        VStack(spacing: 10) {
            if stage != .idle {
                Text(stage.label)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            Button {
                Task { await captureAndSend() }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 64, height: 64)
                    if stage == .capturing || stage == .uploading {
                        ProgressView().tint(.black)
                    }
                }
            }
            .disabled(stage == .capturing || stage == .uploading || !camera.isAuthorized)
        }
    }

    private func captureAndSend() async {
        guard discovery.connectionState == .connected,
              let host = discovery.hostAddress, let port = discovery.hostPort else {
            activeError = AppError(title: "Not Connected", message: "No host is connected yet. Wait for discovery to finish or connect manually from the connection details.")
            return
        }

        showResultToast = false
        stage = .capturing
        let tStart = Date()
        do {
            let photo = try await camera.capturePhoto()
            sentStore.add(photo)

            stage = .uploading
            let algorithm = MatchingAlgorithm(rawValue: algorithmRawValue) ?? .orb
            let tUpload = Date()
            let result = try await UploadService.upload(image: photo, host: host, port: port, algorithm: algorithm)
            let roundtripMs = Int(Date().timeIntervalSince(tUpload) * 1000)
            let item = receivedStore.add(result)

            let totalMs = Int(Date().timeIntervalSince(tStart) * 1000)
            print("[timing] end-to-end: capture+upload roundtrip=\(roundtripMs)ms total=\(totalMs)ms")
            lastLatencyMs = totalMs

            stage = .done
            lastResultItem = item
            withAnimation { showResultToast = true }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { showResultToast = false }
        } catch let error as CameraError {
            activeError = AppError(from: error)
        } catch let error as UploadError {
            activeError = AppError(from: error)
        } catch {
            activeError = AppError(title: "Something Went Wrong", message: error.localizedDescription)
        }
        stage = .idle
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(from error: CameraError) {
        self.title = "Camera Problem"
        self.message = error.errorDescription ?? "Unknown camera error."
    }

    init(from error: UploadError) {
        switch error {
        case .matchingFailed:
            self.title = "No Match Found"
        case .noHost:
            self.title = "Not Connected"
        default:
            self.title = "Upload Failed"
        }
        self.message = error.errorDescription ?? "Unknown upload error."
    }
}
