//
//  DriveViewerView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Full-screen drive viewer with video, map, and timeline
//

import SwiftUI
import AVKit
import os

struct DriveViewerView: View {
    let route: Route
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var playbackState = PlaybackState()
    @State private var videoURL: URL?
    @State private var showingRouteActions = false
    @State private var showingUploadQueue = false
    @State private var showingFileDownload = false
    @State private var thumbnailService = VideoThumbnailService()
    @State private var videoStatus: VideoPlaybackStatus = .idle
    @State private var hasLoadedInitialData = false
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                // Video player - ALWAYS at root level to prevent recreation
                videoPlayerSurface()
                    .zIndex(0)

                if isLandscape && UIDevice.current.userInterfaceIdiom == .phone {
                    // iPhone landscape: Full screen video mode overlays
                    fullScreenLandscapeOverlay(geometry: geometry)
                        .zIndex(1)
                } else if isLandscape && UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad landscape: side-by-side with map
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: geometry.size.width * 0.6)

                        // Only show map when we have data
                        if route.driveCoords != nil || route.startLat != nil {
                            DriveMapView(route: route, playbackState: playbackState)
                                .frame(width: geometry.size.width * 0.4)
                                .background(Color.black)
                        } else {
                            Color.black
                                .frame(width: geometry.size.width * 0.4)
                                .overlay {
                                    ProgressView()
                                        .tint(.white.opacity(0.5))
                                }
                        }
                    }
                    .zIndex(1)

                    // Timeline at bottom for iPad
                    VStack {
                        Spacer()
                        VStack(spacing: 0) {
                            if route.events == nil {
                                TimelineSkeleton()
                                    .frame(height: 120)
                                    .background(.ultraThinMaterial)
                            } else {
                                TimelineView(route: route, playbackState: playbackState, thumbnailService: thumbnailService)
                                    .frame(height: 120)
                                    .background(.ultraThinMaterial)
                            }

                            PlaybackControls(playbackState: playbackState)
                                .padding()
                                .background(.thinMaterial)
                        }
                    }
                    .zIndex(2)

                    // Close and actions for iPad
                    portraitOverlayButtons()
                        .zIndex(3)
                } else {
                    // Portrait mode overlays
                    portraitOverlay(geometry: geometry)
                        .zIndex(1)
                }

                PlaybackTicker(playbackState: playbackState)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(100)
            }
            .onChange(of: isLandscape) { _, newValue in
                if UIDevice.current.userInterfaceIdiom == .phone {
                    if newValue {
                        // Entering landscape - schedule auto-hide controls
                        scheduleHideControls()
                    } else {
                        // Exiting landscape - show controls and cancel auto-hide
                        showControls = true
                        hideControlsTask?.cancel()
                    }
                }
            }
        }
        .statusBarHidden(false)
        .onAppear {
            // Enable orientation change for DriveViewer only
            AppDelegate.orientationLock = .all
            // Ensure loading starts even if task doesn't trigger
            if !hasLoadedInitialData {
                Task {
                    await loadDriveData()
                }
            }
        }
        .onDisappear {
            // Reset orientation to portrait-only when leaving DriveViewer
            AppDelegate.orientationLock = .portrait
            // Force back to portrait
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
        .task(id: route.id) {
            await loadDriveData()
        }
        .sheet(isPresented: $showingRouteActions) {
            RouteActionsSheet(route: route)
                .environment(appState)
        }
        .sheet(isPresented: $showingFileDownload) {
            FileDownloadSheet(
                route: route,
                apiClient: appState.apiClient,
                currentSegment: route.segmentNumber(for: playbackState.currentOffset)
            )
                .environment(appState)
        }
        .sheet(isPresented: $showingUploadQueue) {
            UploadQueueView(dongleId: route.dongleId, apiClient: appState.apiClient)
                .environment(appState)
        }
    }

    // MARK: - Portrait Overlay

    @ViewBuilder
    private func portraitOverlay(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top spacer for buttons
            Spacer()
                .frame(height: 50)

            // Video area - leave transparent (reduced from 35% to 28%)
            Color.clear
                .frame(height: geometry.size.height * 0.28)

            // Map covers the rest - only show when we have coordinates
            if route.driveCoords != nil || route.startLat != nil {
                DriveMapView(route: route, playbackState: playbackState)
                    .background(Color.black)
            } else {
                // Placeholder while loading
                Color.black
                    .overlay {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                    }
            }
        }
        .ignoresSafeArea(edges: .bottom)

        // Timeline at bottom
        VStack {
            Spacer()
            VStack(spacing: 0) {
                if route.events == nil {
                    TimelineSkeleton()
                        .frame(height: 120)
                        .background(.ultraThinMaterial)
                } else {
                    TimelineView(route: route, playbackState: playbackState, thumbnailService: thumbnailService)
                        .frame(height: 120)
                        .background(.ultraThinMaterial)
                }

                PlaybackControls(playbackState: playbackState)
                    .padding()
                    .background(.thinMaterial)
            }
        }

        // Overlay buttons
        portraitOverlayButtons()
    }

    // MARK: - Landscape Full Screen Overlay

    @ViewBuilder
    private func fullScreenLandscapeOverlay(geometry: GeometryProxy) -> some View {
        // Tap handler overlay
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
                if showControls {
                    scheduleHideControls()
                }
            }

        // Controls overlay
        if showControls {
            VStack {
                // Top bar with exit button
                HStack {
                    Spacer()
                    Button {
                        HapticManager.buttonPress()
                        // Just rotate back to portrait - no need to dismiss
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                        }
                    } label: {
                        if #available(iOS 26.0, *) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular, in: Circle())
                        } else {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding()
                }

                Spacer()

                // Bottom controls (compact for landscape)
                VStack(spacing: 0) {
                    // Custom timeline (compact for landscape)
                    TimelineView(route: route, playbackState: playbackState, thumbnailService: thumbnailService, isCompact: true)
                        .frame(height: 72)
                        .onTapGesture {
                            // Prevent tap from propagating to video player
                        }

                    // Playback controls (compact)
                    HStack(spacing: 24) {
                        // Mute button
                        Button {
                            HapticManager.toggle()
                            playbackState.toggleMute()
                            scheduleHideControls()
                        } label: {
                            if #available(iOS 26.0, *) {
                                Image(systemName: playbackState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular, in: Circle())
                            } else {
                                Image(systemName: playbackState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }

                        // Play/Pause button
                        Button {
                            HapticManager.toggle()
                            if playbackState.isPlaying {
                                playbackState.pause()
                            } else {
                                playbackState.play()
                            }
                            scheduleHideControls()
                        } label: {
                            if #available(iOS 26.0, *) {
                                Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .glassEffect(.regular, in: Circle())
                            } else {
                                Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }

                        // Speed button - tap to cycle through speeds
                        Button {
                            HapticManager.selection()
                            playbackState.cycleSpeed()
                            scheduleHideControls()
                        } label: {
                            if #available(iOS 26.0, *) {
                                Text(String(format: "%.2gx", playbackState.preferredPlaySpeed))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular, in: Circle())
                            } else {
                                Text(String(format: "%.2gx", playbackState.preferredPlaySpeed))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Portrait Overlay Buttons

    @ViewBuilder
    private func portraitOverlayButtons() -> some View {
        VStack {
            HStack {
                Button {
                    HapticManager.buttonPress()
                    dismiss()
                } label: {
                    if #available(iOS 26.0, *) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: Circle())
                    } else {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding()

                Spacer()

                // Actions menu
                Menu {
                    Button {
                        HapticManager.selection()
                        showingRouteActions = true
                    } label: {
                        Label("Route Actions", systemImage: "ellipsis.circle")
                    }

                    Button {
                        HapticManager.selection()
                        showingFileDownload = true
                    } label: {
                        Label("Download Files", systemImage: "arrow.down.circle")
                    }

                    // Only show Upload Queue for owned devices
                    if let device = appState.selectedDevice, !device.isReadOnly {
                        Button {
                            HapticManager.selection()
                            showingUploadQueue = true
                        } label: {
                            Label("Upload Queue", systemImage: "arrow.up.circle")
                        }
                    }
                } label: {
                    if #available(iOS 26.0, *) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: Circle())
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding()
            }

            Spacer()
        }
    }

    // MARK: - Video Player Surface

    @ViewBuilder
    private func videoPlayerSurface() -> some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone

            let videoFrame: CGRect = {
                if isLandscape && isPhone {
                    // iPhone landscape: fullscreen
                    return CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height)
                } else if isLandscape && !isPhone {
                    // iPad landscape: left 60%
                    return CGRect(x: 0, y: 0, width: geometry.size.width * 0.6, height: geometry.size.height)
                } else {
                    // Portrait: top 28% with 50pt offset
                    let videoHeight = geometry.size.height * 0.28
                    return CGRect(x: 0, y: 50, width: geometry.size.width, height: videoHeight)
                }
            }()

            ZStack(alignment: .topLeading) {
                // Single persistent video player with dynamic positioning
                VideoPlayerView(
                    url: videoURL,
                    playbackState: playbackState,
                    status: $videoStatus
                )
                .id("persistent-video-player")
                .frame(width: videoFrame.width, height: videoFrame.height)
                .position(x: videoFrame.midX, y: videoFrame.midY)

                videoStatusOverlay
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .position(x: videoFrame.midX, y: videoFrame.midY)
            }
        }
    }

    @ViewBuilder
    private var videoStatusOverlay: some View {
        switch videoStatus {
        case .loading:
            videoLoadingView
        case .unavailable(let reason):
            videoUnavailableView(reason: reason)
        case .error(let message):
            videoErrorView(message: message, canRetry: true)
        case .timeout:
            videoErrorView(message: "Connection timed out", canRetry: true)
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var videoLoadingView: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("Loading video")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func videoUnavailableView(reason: VideoPlaybackStatus.UnavailableReason) -> some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                Image(systemName: "video.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.5))
                
                VStack(spacing: 6) {
                    Text(reason.message)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(reason.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func videoErrorView(message: String, canRetry: Bool) -> some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.5))
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                if canRetry {
                    Button {
                        HapticManager.buttonPress()
                        Task { await loadVideoURL() }
                    } label: {
                        Text("Try Again")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auto-hide Controls

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls = false
                }
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadDriveData() async {
        Logger.data.debug("Loading drive data for route")
        hasLoadedInitialData = true

        // Seed playback duration so timeline/controls stay in sync even before HLS loads
        playbackState.duration = route.duration
        
        // Load video URL and route data in parallel for snappier feel
        async let videoTask: () = loadVideoURL()
        async let dataTask: () = appState.preloadRouteDetailData(for: route)
        
        _ = await (videoTask, dataTask)
    }

    @MainActor
    private func loadVideoURL() async {
        videoStatus = .loading
        videoURL = nil

        do {
            let url = try await appState.apiClient.getVideoStreamURL(for: route)
            Logger.data.debug("Received video URL")
            videoURL = url
            await thumbnailService.loadAsset(from: url)
        } catch {
            Logger.data.error("Failed to load video URL", error: error)
            videoStatus = videoErrorStatus(for: error)
        }
    }

    private func videoErrorStatus(for error: Error) -> VideoPlaybackStatus {
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError(let code, let message):
                // 404 means video doesn't exist - not retryable
                if code == 404 {
                    // Check message for hints about why
                    let lowerMessage = message.lowercased()
                    if lowerMessage.contains("not found") || lowerMessage.contains("requested url") {
                        return .unavailable(reason: .notUploaded)
                    }
                    return .unavailable(reason: .unknown)
                }
                // 410 Gone - video was deleted
                if code == 410 {
                    return .unavailable(reason: .deleted)
                }
                // 5xx errors are server-side, worth retrying
                if code >= 500 {
                    return .error(message: "Server error. Please try again.")
                }
                return .error(message: message.isEmpty ? "Unable to load video." : message)
            case .networkError(let underlying):
                if let urlError = underlying as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet:
                        return .error(message: "No internet connection")
                    case .timedOut:
                        return .timeout
                    case .networkConnectionLost:
                        return .error(message: "Connection lost")
                    default:
                        break
                    }
                }
                return .error(message: "Network error")
            case .unauthorized:
                return .error(message: "Session expired. Please sign in again.")
            default:
                return .error(message: "Unable to load video")
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .error(message: "No internet connection")
            case .timedOut:
                return .timeout
            case .networkConnectionLost:
                return .error(message: "Connection lost")
            default:
                break
            }
        }
        
        return .error(message: "Unable to load video")
    }
}

private struct PlaybackTicker: View {
    @Bindable var playbackState: PlaybackState

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Color.clear
                .onAppear {
                    tick()
                }
                .onChange(of: timeline.date) { _ in
                    tick()
                }
        }
    }

    private func tick() {
        guard playbackState.desiredPlaySpeed > 0 else { return }
        playbackState.updateOffset()
    }
}

@Observable
final class PlaybackState {
    // State variables matching webapp architecture
    private var baseOffset: TimeInterval = 0 // Base offset at startTime (in milliseconds)
    private var startTime: Date = Date() // When baseOffset was set
    var desiredPlaySpeed: Double = 0 // Desired playback rate (0 = paused)
    var preferredPlaySpeed: Double = 1.0 // User's selected speed (persists when paused/seeking)
    var isBuffering = false
    var duration: TimeInterval = 0
    var isMuted = false
    var isSeeking = false // Track if video is currently seeking
    private var usesExternalClock = false
    private var wasPlayingBeforeSeeking = false // Track play state before seeking

    // Pending seek coordination with the AVPlayer surface
    var pendingSeekOffset: TimeInterval?
    var seekRequestID = UUID()

    // Observable offset that gets updated periodically
    var currentOffset: TimeInterval = 0

    // Computed offset (like webapp's currentOffset function)
    private var computedOffset: TimeInterval {
        let elapsed = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
        let speed = isBuffering ? 0 : desiredPlaySpeed
        return baseOffset + (elapsed * speed)
    }

    // Update the observable offset (call this periodically)
    func updateOffset() {
        guard desiredPlaySpeed > 0 else { return }
        guard !usesExternalClock else { return }
        currentOffset = computedOffset
    }

    var isPlaying: Bool {
        // During seeking, show the state from before seeking started
        if isSeeking {
            return wasPlayingBeforeSeeking
        }
        return desiredPlaySpeed > 0
    }

    func play() {
        captureCurrentOffset()
        // Only reset wasPlayingBeforeSeeking if we're not currently seeking
        // If we ARE seeking, keep the flag so the UI doesn't flicker
        if !isSeeking {
            wasPlayingBeforeSeeking = false
        }
        desiredPlaySpeed = preferredPlaySpeed
    }

    func pause() {
        captureCurrentOffset()
        desiredPlaySpeed = 0
        // Don't change preferredPlaySpeed - keep user's selected speed
    }

    func seek(to offset: TimeInterval) {
        let clamped = clampOffset(offset)
        baseOffset = clamped
        startTime = Date()
        currentOffset = clamped
        if !isSeeking {
            // First seek - capture playing state BEFORE pausing
            wasPlayingBeforeSeeking = desiredPlaySpeed > 0
        }
        isSeeking = true
        pendingSeekOffset = clamped
        seekRequestID = UUID()
    }

    func setSpeed(_ speed: Double) {
        captureCurrentOffset()
        let clamped = max(0, min(speed, 2.0))
        preferredPlaySpeed = clamped
        // If playing, update current speed immediately
        if desiredPlaySpeed > 0 {
            desiredPlaySpeed = clamped
        }
    }
    
    /// Available playback speeds
    private static let speeds: [Double] = [0.5, 1.0, 1.5, 2.0]
    
    /// Cycles to the next playback speed
    func cycleSpeed() {
        let currentIndex = Self.speeds.firstIndex(where: { abs($0 - preferredPlaySpeed) < 0.01 }) ?? 1
        let nextIndex = (currentIndex + 1) % Self.speeds.count
        setSpeed(Self.speeds[nextIndex])
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func syncWithPlayer(seconds: Double) {
        let ms = clampOffset(seconds * 1000)
        baseOffset = ms
        startTime = Date()
        currentOffset = ms
        usesExternalClock = true
    }

    func seekCompleted(at offset: TimeInterval, success: Bool) {
        if success {
            let clamped = clampOffset(offset)
            baseOffset = clamped
            currentOffset = clamped
            startTime = Date()
        }
        pendingSeekOffset = nil
        // Reset seeking state AFTER setting isSeeking to false
        // This ensures the flag is cleared in the right order
        let wasSeeking = isSeeking
        isSeeking = false
        if wasSeeking {
            wasPlayingBeforeSeeking = false
        }
    }

    func setExternalClockActive(_ active: Bool) {
        usesExternalClock = active
    }

    private func captureCurrentOffset() {
        baseOffset = computedOffset
        startTime = Date()
        currentOffset = baseOffset
    }

    private func clampOffset(_ offset: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return max(0, offset) }
        return max(0, min(offset, duration))
    }
}

#Preview {
    DriveViewerView(route: Route(
        fullname: "test|2024-01-15--12-30-00",
        logId: "2024-01-15--12-30-00",
        dongleId: "test",
        duration: 1800000,
        distance: 12.5
    ))
    .environment(AppState.shared)
}
