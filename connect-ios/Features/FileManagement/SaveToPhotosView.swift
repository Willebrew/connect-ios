//
//  SaveToPhotosView.swift
//  connect-ios
//
//  Created by Will Killebrew on 1/21/26.
//
//  Primary UI component for downloading drive videos and saving to Photos

import SwiftUI
import Photos

/// Main UI for saving drive videos to the Photos library
struct SaveToPhotosView: View {
    let route: Route
    let currentSegment: Int?
    let apiClient: APIClient

    // Selection state
    @State private var selectedRange: RangeOption = .fullDrive
    @State private var selectedCamera: CameraOption = .road
    @State private var selectedQuality: QualityOption = .standard

    // Processing state
    @State private var isProcessing = false
    @State private var processingProgress: Double = 0
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showSuccess = false
    @State private var canRetry = false

    // Camera availability state
    @State private var availableCameras: Set<CameraOption> = [.road]
    @State private var isCheckingAvailability = true
    @State private var hasCheckedAvailability = false

    // Export task tracking
    @State private var currentExportTask: Task<Void, Never>?

    // Services
    private let downloadQueueManager = DownloadQueueManager.shared
    private let photosSaveService = PhotosSaveService.shared
    private var videoExportService: VideoExportService { VideoExportService.shared }

    // Local copy of download stats for UI updates
    @State private var downloadStats = DownloadStats()
    @State private var statsUpdateTimer: Timer?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        // Single persistent container — lifecycle handlers here
        // so they don't fire when toggling between states.
        VStack(spacing: 0) {
            if showSuccess {
                successView
            } else if isProcessing {
                processingView
            } else {
                selectionView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSuccess)
        .animation(.easeInOut(duration: 0.25), value: isProcessing)
        .alert("Download Error", isPresented: $showingError) {
            if canRetry {
                Button("Try Again") { startDownload() }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            if let segment = currentSegment {
                selectedRange = .currentSegment(segment)
            }
            if !hasCheckedAvailability {
                hasCheckedAvailability = true
                Task { await checkCameraAvailability() }
            }
        }
        .onDisappear {
            Logger.data.debug("SaveToPhotosView onDisappear called, isExporting: \(videoExportService.isExporting)")
            currentExportTask?.cancel()
            if videoExportService.isExporting {
                Logger.data.debug("Cancelling export due to view disappearing")
                videoExportService.cancelExport()
            }
            stopStatsTimer()
        }
    }

    // MARK: - Selection View

    private var selectionView: some View {
        VStack(spacing: 20) {
            // Range
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Range")

                HStack(spacing: 10) {
                    if let segment = currentSegment {
                        optionCard(
                            selected: selectedRange == .currentSegment(segment),
                            icon: "play.rectangle.fill",
                            title: "Segment \(segment)",
                            subtitle: formatDuration(segmentDurationSeconds)
                        ) {
                            selectedRange = .currentSegment(segment)
                        }
                    }

                    optionCard(
                        selected: selectedRange == .fullDrive,
                        icon: "film.stack.fill",
                        title: "Full Drive",
                        subtitle: formatDuration(route.duration / 1000)
                    ) {
                        selectedRange = .fullDrive
                    }
                }
            }

            // Camera
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    sectionLabel("Camera")
                    if isCheckingAvailability {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(CameraOption.allCases) { camera in
                        let available = availableCameras.contains(camera)
                        optionCard(
                            selected: selectedCamera == camera && available,
                            icon: camera.iconName,
                            title: camera.shortName,
                            subtitle: nil,
                            disabled: !available
                        ) {
                            guard available else { return }
                            selectedCamera = camera
                        }
                    }
                }
            }

            // Quality (road camera only)
            if selectedCamera == .road {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Quality")

                    HStack(spacing: 10) {
                        optionCard(
                            selected: selectedQuality == .standard,
                            icon: "speedometer",
                            title: "Standard",
                            subtitle: "~480p"
                        ) {
                            selectedQuality = .standard
                        }

                        optionCard(
                            selected: selectedQuality == .high,
                            icon: "film.fill",
                            title: "High",
                            subtitle: "1080p"
                        ) {
                            selectedQuality = .high
                        }
                    }
                }
            }

            // Save button
            Button {
                HapticManager.buttonPress()
                startDownload()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                    Text("Save to Photos")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.themeGreen)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Option Card

    private func optionCard(
        selected: Bool,
        icon: String,
        title: String,
        subtitle: String?,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.buttonPress()
            withAnimation(.easeInOut(duration: 0.15)) {
                action()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(selected ? Color.themeGreen : .secondary)

                Text(title)
                    .font(.caption.weight(.semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.themeGreen.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.themeGreen.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .opacity(disabled ? 0.3 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 20) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: processingProgress)
                    .stroke(Color.themeGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: processingProgress)

                VStack(spacing: 2) {
                    Text("\(Int(processingProgress * 100))%")
                        .font(.title3.weight(.semibold).monospacedDigit())

                    Text(downloadStats.phase.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 100, height: 100)

            // Download stats
            if downloadStats.phase == .downloading {
                downloadStatsView
            }

            // Cancel
            Button {
                HapticManager.buttonPress()
                cancelDownload()
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)
                    .background(
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear { startStatsTimer() }
    }

    @ViewBuilder
    private var downloadStatsView: some View {
        HStack {
            if downloadStats.bytesPerSecond > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                    Text(downloadStats.formattedSpeed)
                        .font(.caption.monospacedDigit())
                }
            }

            Spacer()

            if let segmentStatusText {
                Text(segmentStatusText)
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.themeGreen)
                .symbolEffect(.bounce, value: showSuccess)

            Text("Saved to Photos")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Stats Timer

    private func startStatsTimer() {
        statsUpdateTimer?.invalidate()
        statsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.downloadStats = self.videoExportService.downloadStats
                // Only mirror exportProgress while actively exporting to avoid
                // flashing stale progress from a previous download.
                if self.videoExportService.isExporting {
                    self.processingProgress = self.videoExportService.exportProgress
                }
            }
        }
    }

    private func stopStatsTimer() {
        statsUpdateTimer?.invalidate()
        statsUpdateTimer = nil
    }

    // MARK: - Actions

    @MainActor
    private func checkCameraAvailability() async {
        do {
            let files = try await apiClient.getRouteFiles(routeName: route.fullname)

            var cameras: Set<CameraOption> = []

            if let qcameras = files["qcameras"], !qcameras.isEmpty {
                cameras.insert(.road)
            }
            if let dcameras = files["dcameras"], !dcameras.isEmpty {
                cameras.insert(.driver)
            }
            if let ecameras = files["ecameras"], !ecameras.isEmpty {
                cameras.insert(.wide)
            }

            availableCameras = cameras.isEmpty ? [.road] : cameras

            if !availableCameras.contains(selectedCamera) {
                selectedCamera = .road
            }

            Logger.data.debug("Save to Photos: Available cameras: \(availableCameras.map { $0.rawValue })")
        } catch {
            Logger.data.error("Failed to check camera availability: \(error)")
            availableCameras = [.road]
        }

        isCheckingAvailability = false
    }

    private func startDownload() {
        Logger.data.debug("startDownload() called, isProcessing=\(isProcessing)")

        guard !isProcessing else {
            Logger.data.debug("Ignoring duplicate startDownload call - already processing")
            return
        }

        currentExportTask?.cancel()
        if videoExportService.isExporting {
            videoExportService.cancelExport()
        }

        currentExportTask = Task {
            await performDownload()
        }
    }

    @MainActor
    private func performDownload() async {
        guard !isProcessing else {
            Logger.data.debug("performDownload: Already in progress, ignoring")
            return
        }

        Logger.data.debug("performDownload: Starting download")
        isProcessing = true
        processingProgress = 0
        errorMessage = nil
        canRetry = false
        showSuccess = false

        do {
            try Task.checkCancellation()

            let authStatus = await photosSaveService.requestAuthorization()
            guard authStatus == .authorized || authStatus == .limited else {
                throw PhotosSaveService.PhotosSaveError.notAuthorized(authStatus)
            }

            try Task.checkCancellation()

            let segmentURLs = try await getSegmentURLs()

            try Task.checkCancellation()

            let outputName = generateOutputName()
            let outputURL = try await videoExportService.exportSegmentsToMP4(
                segmentURLs: segmentURLs,
                outputName: outputName
            )

            try Task.checkCancellation()

            // Show saving phase while writing to Photos
            processingProgress = 0.95
            downloadStats.phase = .saving

            _ = try await photosSaveService.saveAndCleanup(outputURL)

            stopStatsTimer()
            processingProgress = 1.0

            HapticManager.success()
            withAnimation(.easeInOut(duration: 0.3)) {
                isProcessing = false
                showSuccess = true
            }

            try await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
            return

        } catch is CancellationError {
            Logger.data.debug("Download cancelled by user")
        } catch VideoExportService.ExportError.cancelled {
            Logger.data.debug("Export cancelled")
        } catch let error as VideoExportService.ExportError {
            canRetry = isRetryableError(error)
            errorMessage = error.userFriendlyMessage
            showingError = true
            HapticManager.error()
        } catch let error as PhotosSaveService.PhotosSaveError {
            canRetry = false
            errorMessage = mapPhotosSaveError(error)
            showingError = true
            HapticManager.error()
        } catch {
            canRetry = true
            errorMessage = error.localizedDescription
            showingError = true
            HapticManager.error()
        }

        stopStatsTimer()
        isProcessing = false
        currentExportTask = nil
    }

    private func cancelDownload() {
        Logger.data.debug("User pressed cancel button")
        currentExportTask?.cancel()
        if videoExportService.isExporting {
            videoExportService.cancelExport()
        }
        TSRemuxService.shared.cancel()
        stopStatsTimer()
        isProcessing = false
        currentExportTask = nil
    }

    private func isRetryableError(_ error: VideoExportService.ExportError) -> Bool {
        switch error {
        case .downloadFailed, .exportFailed, .invalidOutput:
            return true
        case .streamNotAvailable, .missingSegments, .cancelled, .invalidURL, .noVideoTrack, .unsupportedFormat, .assetLoadFailed:
            return false
        }
    }

    private func mapPhotosSaveError(_ error: PhotosSaveService.PhotosSaveError) -> String {
        switch error {
        case .notAuthorized:
            return "Photos access is required. Please enable it in Settings > Privacy > Photos."
        case .fileNotFound:
            return "The exported video file was not found. Please try again."
        case .unsupportedFormat(let ext):
            return "The video format (.\(ext)) is not supported by Photos."
        case .saveFailed(let reason):
            if reason.contains("3302") || reason.contains("invalidResource") {
                return "Photos rejected the video file. The video may be corrupted. Try a different quality or camera angle."
            }
            return "Failed to save to Photos: \(reason)"
        }
    }

    // MARK: - Segment URL Building

    private func getSegmentURLs() async throws -> [URL] {
        Logger.data.debug("Fetching route files for segment export")
        let files = try await apiClient.getRouteFiles(routeName: route.fullname)

        let fileKey: String
        switch selectedCamera {
        case .road:
            fileKey = selectedQuality == .standard ? "qcameras" : "cameras"
        case .driver:
            fileKey = "dcameras"
        case .wide:
            fileKey = "ecameras"
        }

        guard let urlStrings = files[fileKey], !urlStrings.isEmpty else {
            Logger.data.error("No files found for key: \(fileKey)")
            throw VideoExportService.ExportError.missingSegments
        }

        return try await parseAndFilterURLs(urlStrings)
    }

    private func parseAndFilterURLs(_ urlStrings: [String]) async throws -> [URL] {
        let entries = urlStrings.compactMap { RouteFileEntry(urlString: $0) }
        if entries.isEmpty {
            Logger.data.error("Failed to parse route file entries")
            throw VideoExportService.ExportError.missingSegments
        }

        let filteredEntries: [RouteFileEntry]
        switch selectedRange {
        case .currentSegment(let segment):
            filteredEntries = entries.filter { $0.segmentNumber == segment }
        case .fullDrive:
            filteredEntries = entries
        }

        let sortedEntries = filteredEntries.sorted { (lhs, rhs) in
            (lhs.segmentNumber ?? 0) < (rhs.segmentNumber ?? 0)
        }

        let urls = sortedEntries.compactMap { URL(string: $0.url) }
        if urls.isEmpty {
            Logger.data.error("No valid URLs found after filtering segments")
            throw VideoExportService.ExportError.missingSegments
        }

        Logger.data.debug("Segment export using \(urls.count) segments for camera: \(selectedCamera.rawValue)")
        return urls
    }

    private func generateOutputName() -> String {
        let routePart = route.fullname
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: "--", with: "_")

        let cameraPart = selectedCamera.rawValue
        let rangePart: String
        switch selectedRange {
        case .currentSegment(let num): rangePart = "seg\(num)"
        case .fullDrive: rangePart = "full"
        }

        return "\(routePart)_\(cameraPart)_\(rangePart)"
    }

    // MARK: - Computed Properties

    private var segmentDurationSeconds: TimeInterval {
        return min(60, route.duration / 1000)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            return "0:\(String(format: "%02d", seconds))"
        }
    }

    private var segmentStatusText: String? {
        switch selectedRange {
        case .currentSegment(let segment):
            return "Segment \(segment)"
        case .fullDrive:
            guard downloadStats.totalSegments > 0 else { return nil }
            return "Segment \(downloadStats.currentSegment)/\(downloadStats.totalSegments)"
        }
    }

    // MARK: - Types

    enum RangeOption: Equatable {
        case currentSegment(Int)
        case fullDrive
    }

    enum CameraOption: String, CaseIterable, Identifiable {
        case road
        case driver
        case wide

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .road: return "Road Camera"
            case .driver: return "Driver Camera"
            case .wide: return "Wide Camera"
            }
        }

        var shortName: String {
            switch self {
            case .road: return "Road"
            case .driver: return "Driver"
            case .wide: return "Wide"
            }
        }

        var iconName: String {
            switch self {
            case .road: return "car"
            case .driver: return "person.fill"
            case .wide: return "camera.aperture"
            }
        }

        var streamType: CameraStreamType {
            switch self {
            case .road: return .road
            case .driver: return .driver
            case .wide: return .wide
            }
        }
    }

    enum QualityOption: String, CaseIterable {
        case standard
        case high

        var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .high: return "High"
            }
        }

        var subtitle: String {
            switch self {
            case .standard: return "~480p, ~2.6 MB/min"
            case .high: return "1080p, ~20 MB/min"
            }
        }
    }
}
