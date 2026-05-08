//
//  SnapshotView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Device camera snapshot viewer
//

import SwiftUI
import Photos

struct SnapshotView: View {
    let dongleId: String
    @State private var athenaService: AthenaService
    @State private var roadSnapshot: UIImage?     // Back/road camera
    @State private var driverSnapshot: UIImage?   // Front/driver camera
    @State private var isLoading = false
    @State private var error: String?
    @State private var saveSuccess = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    init(dongleId: String, apiClient: APIClient) {
        self.dongleId = dongleId
        self._athenaService = State(initialValue: AthenaService(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if let error = error {
                            errorView(error)
                        }

                        // Take snapshot button (takes both cameras at once)
                        Button {
                            HapticManager.buttonPress()
                            Task {
                                await takeSnapshot()
                            }
                        } label: {
                            if #available(iOS 26.0, *) {
                                Label(isLoading ? "Taking Snapshot..." : "Take Snapshot", systemImage: "camera")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .foregroundStyle(.white)
                                    .glassEffect()
                                    .opacity(deviceIsOnline ? 1.0 : 0.5)
                            } else {
                                Label(isLoading ? "Taking Snapshot..." : "Take Snapshot", systemImage: "camera")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        deviceIsOnline
                                            ? Color.themeGreen.gradient
                                            : Color.gray.gradient,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .foregroundStyle(.white)
                                    .opacity(deviceIsOnline ? 1.0 : 0.6)
                            }
                        }
                        .disabled(isLoading || !deviceIsOnline)

                        if !deviceIsOnline {
                            offlineMessage
                        }

                        // Road camera (back) snapshot
                        if isLoading || roadSnapshot != nil {
                            snapshotCard(
                                title: "Road Camera",
                                image: roadSnapshot,
                                isLoading: isLoading
                            )
                        }

                        // Driver camera (front) snapshot
                        if isLoading || driverSnapshot != nil {
                            snapshotCard(
                                title: "Driver Camera",
                                image: driverSnapshot,
                                isLoading: isLoading
                            )
                        }

                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("Snapshots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        HapticManager.buttonPress()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func snapshotCard(
        title: String,
        image: UIImage?,
        isLoading: Bool
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .aspectRatio(16/9, contentMode: .fit)

                    ProgressView()
                        .scaleEffect(1.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contextMenu {
                        Button {
                            HapticManager.buttonPress()
                            Task {
                                await saveImageToPhotos(image)
                            }
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(title))
                    }
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)

                            Text("No snapshot")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private var deviceIsOnline: Bool {
        appState.devices.first(where: { $0.dongleId == dongleId })?.isOnline ?? false
    }

    private var offlineSnapshotMessage: String {
        "Device is offline. Snapshots unavailable."
    }

    private var offlineMessage: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(offlineSnapshotMessage)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func saveImageToPhotos(_ image: UIImage) async {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }

        guard status == .authorized || status == .limited else {
            error = "Photos access denied. Enable in Settings."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: image.jpegData(compressionQuality: 0.9)!, options: nil)
            }
            HapticManager.actionSuccess()
            saveSuccess = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveSuccess = false
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func takeSnapshot() async {
        guard deviceIsOnline else {
            error = offlineSnapshotMessage
            return
        }

        isLoading = true
        error = nil
        roadSnapshot = nil
        driverSnapshot = nil

        do {
            let result = try await athenaService.takeSnapshot(dongleId: dongleId)

            // Decode road camera (back)
            if let jpegBack = result.jpegBack,
               let data = Data(base64Encoded: jpegBack),
               let image = UIImage(data: data) {
                roadSnapshot = image
            }

            // Decode driver camera (front)
            if let jpegFront = result.jpegFront,
               let data = Data(base64Encoded: jpegFront),
               let image = UIImage(data: data) {
                driverSnapshot = image
            }

            if roadSnapshot != nil || driverSnapshot != nil {
                HapticManager.actionSuccess()
            } else {
                error = "Failed to decode snapshot images"
            }
        } catch let err {
            if err.isDeviceOfflineError {
                self.error = offlineSnapshotMessage
            } else {
                self.error = "Failed to take snapshot: \(err.localizedDescription)"
            }
        }
        isLoading = false
    }
}
