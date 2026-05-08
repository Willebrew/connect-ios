//
//  QRScannerView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  QR code scanner for device pairing
//

import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkMonitor.self) private var networkMonitor
    let apiClient: APIClient
    let onDevicePaired: (Device) -> Void

    @State private var isScanning = true
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var scannedDevice: Device?
    @State private var cameraPermissionDenied = false
    @State private var showingOfflineAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                QRCodeScannerRepresentable(
                    isScanning: $isScanning,
                    onQRCodeScanned: { code in
                        handleQRCode(code)
                    },
                    onPermissionDenied: {
                        cameraPermissionDenied = true
                    }
                )
                .ignoresSafeArea()

                // Top gradient fade
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.7), .black.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false)

                    Spacer()
                }

                // Scanning frame overlay
                VStack {
                    // Title at top
                    HStack {
                        Button {
                            HapticManager.buttonPress()
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.body)
                                .foregroundStyle(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("Scan QR Code")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Spacer()

                        // Placeholder for symmetry
                        Text("Cancel")
                            .font(.body)
                            .foregroundStyle(.clear)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    Spacer()

                    // Scanning area
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 250, height: 250)

                    if #available(iOS 26.0, *) {
                        Text("Position QR code within frame")
                            .font(.headline)
                            .padding()                        
                            .glassEffect()
                    } else {
                        // Fallback on earlier versions
                        Text("Position QR code within frame")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.top, 20)
                    }
                    Spacer()

                    if cameraPermissionDenied {
                        VStack(spacing: 16) {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill.badge.exclamationmark")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.yellow)

                                Text("Camera Access Required")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text("Please enable camera access in Settings to scan QR codes")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding()
                            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))

                            Button {
                                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsUrl)
                                }
                            } label: {
                                Text("Open Settings")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.themeGreen, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding()
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text(error)
                                    .foregroundStyle(.white)
                            }
                            .padding()
                            .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))

                            Button {
                                HapticManager.buttonPress()
                                errorMessage = nil
                                isScanning = true
                            } label: {
                                Text("Try Again")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.themeGreen, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding()
                    }
                }

                // Pairing overlay
                if isPairing {
                    ZStack {
                        Color.black.opacity(0.8)
                            .ignoresSafeArea()

                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)

                            Text("Pairing device...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                }

                // Success overlay
                if let device = scannedDevice {
                    ZStack {
                        Color.black.opacity(0.9)
                            .ignoresSafeArea()

                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.green)

                            Text("Device Paired!")
                                .font(.title2.bold())
                                .foregroundStyle(.white)

                            VStack(spacing: 8) {
                                Text(device.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text(device.dongleId)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            Button {
                                HapticManager.actionSuccess()
                                onDevicePaired(device)
                                dismiss()
                            } label: {
                                if #available(iOS 26.0, *) {
                                    Text("Done")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: 200)
                                        .padding()
                                        .glassEffect()
                                } else {
                                    // Fallback on earlier versions
                                    Text("Done")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: 200)
                                        .padding()
                                        .background(Color.themeGreen, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.top)
                        }
                        .padding()
                    }
                }
            }
            .navigationBarHidden(true)
            .alert("No Internet Connection", isPresented: $showingOfflineAlert) {
                Button("OK", role: .cancel) {
                    HapticManager.buttonPress()
                    dismiss()
                }
            } message: {
                Text("You need an active internet connection to pair new devices. Please check your network settings and try again.")
            }
            .onAppear {
                // Ensure scanning is enabled when view appears
                // This fixes timing issues with camera initialization
                isScanning = true
            }
            .onDisappear {
                // Clean up scanning state when view disappears
                isScanning = false
            }
        }
    }

    private func handleQRCode(_ code: String) {
        // Stop scanning
        isScanning = false

        // Check if in demo mode
        if AuthService.shared.isDemoMode {
            errorMessage = "Cannot pair devices in demo mode. Please sign in with your own account."
            HapticManager.actionError()
            return
        }

        // Check if device has internet connection
        if !networkMonitor.isConnected {
            HapticManager.actionError()
            showingOfflineAlert = true
            return
        }

        // Validate and extract token
        guard let token = extractToken(from: code) else {
            errorMessage = "Invalid QR code format"
            return
        }

        // Pair device
        Task {
            isPairing = true
            errorMessage = nil

            do {
                let device = try await apiClient.pairDevice(token: token)
                isPairing = false
                HapticManager.actionSuccess()
                scannedDevice = device
            } catch let error as APIError {
                isPairing = false
                HapticManager.actionError()
                errorMessage = error.errorDescription ?? "Failed to pair device"
            } catch {
                isPairing = false
                HapticManager.actionError()
                errorMessage = "Failed to pair device: \(error.localizedDescription)"
            }
        }
    }

    private func extractToken(from qrCode: String) -> String? {
        // QR code format: "openpilot://pair?code=JWT_TOKEN"
        // or just the JWT token directly

        if qrCode.hasPrefix("openpilot://pair?code=") {
            return String(qrCode.dropFirst("openpilot://pair?code=".count))
        } else if qrCode.hasPrefix("pair--") {
            // Format: pair--JWT_TOKEN
            return String(qrCode.dropFirst("pair--".count))
        } else if isValidJWT(qrCode) {
            // Direct JWT token
            return qrCode
        }
        return nil
    }

    private func isValidJWT(_ token: String) -> Bool {
        // JWT format: header.payload.signature
        let components = token.split(separator: ".")
        return components.count == 3
    }
}

// UIViewRepresentable for AVCaptureSession
struct QRCodeScannerRepresentable: UIViewRepresentable {
    @Binding var isScanning: Bool
    let onQRCodeScanned: (String) -> Void
    let onPermissionDenied: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        // Check camera permission first
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraAuthStatus {
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        context.coordinator.setupCaptureSession(in: view)
                    }
                } else {
                    DispatchQueue.main.async {
                        onPermissionDenied()
                    }
                }
            }
            return view
        case .restricted, .denied:
            // Permission denied
            DispatchQueue.main.async {
                onPermissionDenied()
            }
            return view
        case .authorized:
            // Permission granted - setup session
            context.coordinator.setupCaptureSession(in: view)
            return view
        @unknown default:
            return view
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            previewLayer.frame = uiView.bounds
        }

        // Ensure capture session exists - set up if needed
        if context.coordinator.captureSession == nil {
            let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraAuthStatus == .authorized {
                context.coordinator.setupCaptureSession(in: uiView)
            }
        }

        // Control scanning state
        if isScanning {
            // Reset the hasScanned flag when scanning is re-enabled
            // This ensures multiple scans work correctly
            context.coordinator.hasScanned = false

            if let session = context.coordinator.captureSession, !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        } else {
            if let session = context.coordinator.captureSession, session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.stopRunning()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onQRCodeScanned: onQRCodeScanned)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onQRCodeScanned: (String) -> Void
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var hasScanned = false

        init(onQRCodeScanned: @escaping (String) -> Void) {
            self.onQRCodeScanned = onQRCodeScanned
        }

        func setupCaptureSession(in view: UIView) {
            let captureSession = AVCaptureSession()
            self.captureSession = captureSession

            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                return
            }

            let videoInput: AVCaptureDeviceInput
            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                return
            }

            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                return
            }

            let metadataOutput = AVCaptureMetadataOutput()

            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)

                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                return
            }

            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)

            self.previewLayer = previewLayer

            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned else { return }

            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }

                hasScanned = true
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

                onQRCodeScanned(stringValue)
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.captureSession?.stopRunning()
        coordinator.captureSession = nil
        coordinator.previewLayer = nil
    }
}

#Preview {
    QRScannerView(
        apiClient: ProductionAPIClient(),
        onDevicePaired: { device in
            Logger.ui.info("Paired device: \(device.displayName)")
        }
    )
    .environment(NetworkMonitor.shared)
}
