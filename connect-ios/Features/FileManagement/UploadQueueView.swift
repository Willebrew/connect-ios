//
//  UploadQueueView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  Upload queue management interface
//

import SwiftUI

struct UploadQueueView: View {
    let dongleId: String
    @State private var fileService: FileManagementService
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    init(dongleId: String, apiClient: APIClient) {
        self.dongleId = dongleId
        let athenaService = AthenaService(apiClient: apiClient)
        self._fileService = State(initialValue: FileManagementService(apiClient: apiClient, athenaService: athenaService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if let errorMessage = fileService.lastError {
                    offlineState(message: errorMessage)
                } else if fileService.uploadQueue.isEmpty && !fileService.isLoadingQueue {
                    emptyState
                } else {
                    List {
                        ForEach(fileService.uploadQueue) { item in
                            UploadQueueRow(item: item) {
                                Task {
                                    await fileService.cancelUpload(dongleId: dongleId, uploadId: item.id)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                if fileService.isLoadingQueue {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Upload Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticManager.buttonPress()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        HapticManager.refresh()
                        Task {
                            await fileService.fetchUploadQueue(dongleId: dongleId, isDeviceOnline: deviceIsOnline)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(fileService.isLoadingQueue)
                }

                if !fileService.uploadQueue.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Cancel All", role: .destructive) {
                            HapticManager.delete()
                            Task {
                                await fileService.cancelAllUploads(dongleId: dongleId)
                            }
                        }
                    }
                }
            }
            .task {
                await fileService.fetchUploadQueue(dongleId: dongleId, isDeviceOnline: deviceIsOnline)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Uploads")
                    .font(.title2.bold())

                Text("Upload queue is empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension UploadQueueView {
    private var deviceIsOnline: Bool {
        appState.devices.first(where: { $0.dongleId == dongleId })?.isOnline ?? false
    }

    private func offlineState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Upload queue unavailable")
                .font(.title3.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                HapticManager.buttonPress()
                Task {
                    await fileService.fetchUploadQueue(dongleId: dongleId, isDeviceOnline: deviceIsOnline)
                }
            } label: {
                if #available(iOS 26.0, *) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .glassEffect()
                } else {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.themeGreen.gradient, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
            .disabled(fileService.isLoadingQueue)
        }
        .padding(32)
    }
}

struct UploadQueueRow: View {
    let item: UploadQueueItem
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileType)
                        .font(.headline)

                    Text(item.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if item.current {
                    Text("\(Int(item.progress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.themeGreen)
                } else if item.paused {
                    Text("Paused")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.15), in: Capsule())
                } else {
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if item.current {
                ProgressView(value: item.progress)
                    .tint(Color.themeGreen)
            }

            HStack {
                Text("Added \(item.created.shortTimeAgo)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    HapticManager.buttonPress()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.caption.bold())
                }
            }
        }
        .padding(.vertical, 8)
    }
}
