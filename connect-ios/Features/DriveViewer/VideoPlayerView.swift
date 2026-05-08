//
//  VideoPlayerView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  HLS video player with AVPlayer
//

import SwiftUI
import AVKit
import AVFoundation
import os

struct VideoPlayerView: View {
    let url: URL?
    @Bindable var playbackState: PlaybackState
    @Binding var status: VideoPlaybackStatus

    @State private var player: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var currentPlayerItem: AVPlayerItem?
    @State private var playerItemStatusObserver: NSKeyValueObservation?
    @State private var playerItemErrorObserver: NSObjectProtocol?
    @State private var playerItemFailedObserver: NSObjectProtocol?
    @State private var playerItemDidPlayToEndObserver: NSObjectProtocol?
    @State private var hasAutoStartedPlayback = false
    @State private var loadingTimeoutTask: Task<Void, Never>?
    @State private var exportStartObserver: NSObjectProtocol?
    @State private var exportEndObserver: NSObjectProtocol?
    @State private var wasPlayingBeforeExport = false
#if DEBUG
    @State private var debugInfo = PlayerDebugInfo()
    private let isDebugHUDEnabled = false
#endif

    var body: some View {
        Group {
            if let player = player {
                ZStack(alignment: .bottomLeading) {
                    CustomVideoPlayer(player: player)
                        .ignoresSafeArea()
#if DEBUG
                    if isDebugHUDEnabled {
                        PlayerDebugHUD(info: debugInfo, playbackState: playbackState)
                            .padding(8)
                    }
#endif
                }
            } else {
                Color.black
            }
        }
        .onAppear {
            configureAudioSession()
            setupExportObservers()
            if player == nil, url != nil {
                setupPlayer(with: url)
            }
        }
        .onDisappear {
            cleanupExportObservers()
            cleanupPlayer()
        }
        .onChange(of: url) { _, newValue in
            if let newValue {
                setupPlayer(with: newValue)
            } else {
                cleanupPlayer()
            }
        }
        .onChange(of: playbackState.isMuted) { _, newValue in
            player?.isMuted = newValue
        }
        .onChange(of: playbackState.desiredPlaySpeed) { _, _ in
            guard let player else { return }
            applyPlaybackState(to: player)
        }
        .onChange(of: playbackState.seekRequestID) { _, _ in
            handlePendingSeek()
        }
    }

    private func setupPlayer(with url: URL? = nil) {
        guard let videoURL = url ?? self.url else { return }

        Logger.data.debug("Loading video player")

        cleanupPlayer()
        status = .loading

        let playerItem = AVPlayerItem(url: videoURL)
        currentPlayerItem = playerItem

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        player.isMuted = playbackState.isMuted
        self.player = player

        playerItemStatusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
            switch item.status {
            case .readyToPlay:
                Logger.data.debug("AVPlayerItem ready to play")
                DispatchQueue.main.async {
                    self.loadingTimeoutTask?.cancel()
                    self.loadingTimeoutTask = nil
                    self.status = .ready
                    if !self.hasAutoStartedPlayback {
                        self.hasAutoStartedPlayback = true
                        self.playbackState.play()
                    }
                }
            case .failed:
                let status = Self.parseAVPlayerError(item.error)
                DispatchQueue.main.async {
                    self.loadingTimeoutTask?.cancel()
                    self.loadingTimeoutTask = nil
                    self.status = status
                }
                if let error = item.error {
                    Logger.data.error("AVPlayerItem failed", error: error)
                }
            case .unknown:
                Logger.data.debug("AVPlayerItem status unknown")
            @unknown default:
                break
            }
        }

        playerItemErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: playerItem,
            queue: .main
        ) { _ in
            if let log = playerItem.errorLog()?.events.last {
                Logger.data.error("AVPlayerItem error log: \(log.errorStatusCode) \(log.errorComment ?? "")")
                // Check if it's a 404
                if log.errorStatusCode == -12938 || log.errorStatusCode == 404 {
                    self.status = .unavailable(reason: .notUploaded)
                } else if log.errorStatusCode < 0 {
                    // Negative codes are usually network/streaming issues - may be transient
                    self.status = .error(message: "Playback interrupted")
                }
            }
        }

        playerItemFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let status = Self.parseAVPlayerError(error)
            Logger.data.error("AVPlayerItem failed to play to end: \(error?.localizedDescription ?? "unknown")")
            self.status = status
        }

        playerItemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak playbackState] _ in
            playbackState?.pause()
        }

        Task {
            if #available(iOS 17.0, *) {
                do {
                    let duration = try await playerItem.asset.load(.duration)
                    if duration.isNumeric {
                        let ms = CMTimeGetSeconds(duration) * 1000
                        await MainActor.run {
                            playbackState.duration = ms
                        }
                    }
                } catch {
                    Logger.data.error("Failed to load asset duration", error: error)
                }
            } else {
                playerItem.asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                    var error: NSError?
                    let status = playerItem.asset.statusOfValue(forKey: "duration", error: &error)
                    guard status == .loaded else {
                        if let error {
                            Logger.data.error("Failed to load asset duration", error: error)
                        }
                        return
                    }
                    let duration = playerItem.asset.duration
                    if duration.isNumeric {
                        let ms = CMTimeGetSeconds(duration) * 1000
                        DispatchQueue.main.async {
                            playbackState.duration = ms
                        }
                    }
                }
            }
        }

        attachTimeObserver(to: player)
        playbackState.setExternalClockActive(true)
        applyPlaybackState(to: player)
        handlePendingSeek()
        
        // Start loading timeout - if video doesn't become ready in 30 seconds, show timeout
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Only timeout if still in loading state
                if case .loading = self.status {
                    Logger.data.error("Video loading timed out after 30 seconds")
                    self.status = .timeout
                }
            }
        }
    }

    private func cleanupPlayer() {
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = nil
        player?.pause()
        removeTimeObserver()
        player = nil
        cleanupPlayerObservers()
        currentPlayerItem = nil
        playbackState.setExternalClockActive(false)
    }

    private func cleanupPlayerObservers() {
        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil

        if let observer = playerItemErrorObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemErrorObserver = nil
        }

        if let observer = playerItemFailedObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemFailedObserver = nil
        }

        if let observer = playerItemDidPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemDidPlayToEndObserver = nil
        }

        hasAutoStartedPlayback = false
    }

    private func attachTimeObserver(to player: AVPlayer) {
        removeTimeObserver()

        let interval = CMTime(value: 1, timescale: 30)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            guard !self.playbackState.isSeeking else { return }

            let seconds = CMTimeGetSeconds(time)
            self.playbackState.syncWithPlayer(seconds: seconds)

#if DEBUG
            let desired = self.playbackState.currentOffset / 1000
            self.debugInfo = PlayerDebugInfo(
                playerTime: seconds,
                desiredTime: desired,
                diff: desired - seconds,
                rate: player.rate,
                statusDescription: String(describing: player.currentItem?.status ?? .unknown),
                isSeeking: self.playbackState.isSeeking
            )
#endif
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func handlePendingSeek() {
        guard let player,
              let target = playbackState.pendingSeekOffset else { return }
        performSeek(to: target, on: player)
    }

    private func performSeek(to offset: TimeInterval, on player: AVPlayer) {
        let time = CMTime(seconds: offset / 1000, preferredTimescale: 600)
        let targetPlayer = player
        targetPlayer.pause()
        targetPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            DispatchQueue.main.async {
                self.playbackState.seekCompleted(at: offset, success: finished)
                guard finished,
                      let currentPlayer = self.player,
                      currentPlayer === targetPlayer else { return }

                // Resume playback at preferred speed if we should be playing
                if self.playbackState.desiredPlaySpeed > 0 {
                    currentPlayer.play()
                    currentPlayer.rate = Float(self.playbackState.preferredPlaySpeed)
                } else {
                    currentPlayer.pause()
                }
            }
        }
    }

    private func applyPlaybackState(to player: AVPlayer) {
        let speed = playbackState.desiredPlaySpeed

        if speed == 0 {
            player.pause()
        } else {
            if playbackState.isSeeking { return }
            player.play()
            player.rate = Float(speed)
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
            Logger.data.debug("Audio session configured for playback")
        } catch {
            Logger.data.error("Failed to configure audio session", error: error)
        }
    }
    
    // MARK: - Export Notification Handling
    
    private func setupExportObservers() {
        // Stop video player when export starts to avoid AVFoundation conflicts
        // Just pausing isn't enough - we need to release the HLS stream
        exportStartObserver = NotificationCenter.default.addObserver(
            forName: .videoExportDidStart,
            object: nil,
            queue: .main
        ) { [self] _ in
            wasPlayingBeforeExport = playbackState.isPlaying
            Logger.data.debug("Stopping video player for export (was playing: \(wasPlayingBeforeExport))")
            
            // Stop playback and release the player item to free the HLS stream
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
        
        // Restore video when export ends
        exportEndObserver = NotificationCenter.default.addObserver(
            forName: .videoExportDidEnd,
            object: nil,
            queue: .main
        ) { [self] _ in
            Logger.data.debug("Export ended, restoring video player")
            
            // Re-setup the player with the original URL
            if let videoURL = url {
                setupPlayer(with: videoURL)
                // If it was playing before, resume playback after setup
                if wasPlayingBeforeExport {
                    // Small delay to let the player initialize
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.playbackState.play()
                    }
                }
            }
        }
    }
    
    private func cleanupExportObservers() {
        if let observer = exportStartObserver {
            NotificationCenter.default.removeObserver(observer)
            exportStartObserver = nil
        }
        if let observer = exportEndObserver {
            NotificationCenter.default.removeObserver(observer)
            exportEndObserver = nil
        }
    }
    
    /// Parses AVPlayer/AVPlayerItem errors into user-friendly status
    private static func parseAVPlayerError(_ error: Error?) -> VideoPlaybackStatus {
        guard let error = error else {
            return .error(message: "Video failed to load")
        }
        
        let nsError = error as NSError
        let errorMessage = nsError.localizedDescription.lowercased()
        
        // Check for 404/not found errors
        // CoreMedia error -12938 is HTTP 404
        if nsError.code == -12938 ||
           errorMessage.contains("404") ||
           errorMessage.contains("not found") ||
           errorMessage.contains("file not found") {
            return .unavailable(reason: .notUploaded)
        }
        
        // Check for network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return .error(message: "No internet connection")
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNetworkConnectionLost:
                return .error(message: "Connection lost")
            default:
                return .error(message: "Network error")
            }
        }
        
        // Check for CoreMedia errors
        if nsError.domain == "CoreMediaErrorDomain" {
            // -12938 is HTTP error (usually 404)
            if nsError.code == -12938 {
                return .unavailable(reason: .notUploaded)
            }
            // -12939 is connection failure
            if nsError.code == -12939 {
                return .error(message: "Connection failed")
            }
        }
        
        // Generic fallback
        return .error(message: "Unable to play video")
    }
}

// Custom video player using UIViewRepresentable
struct CustomVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

#if DEBUG
private struct PlayerDebugInfo: Equatable {
    var playerTime: Double = 0
    var desiredTime: Double = 0
    var diff: Double = 0
    var rate: Float = 0
    var statusDescription: String = "unknown"
    var isSeeking: Bool = false
}

private struct PlayerDebugHUD: View {
    let info: PlayerDebugInfo
    let playbackState: PlaybackState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("player -> \(formatted(info.playerTime))s")
            Text("desired -> \(formatted(info.desiredTime))s (delta \(String(format: "%.3f", info.diff)))")
            Text("rate \(String(format: "%.2f", info.rate)) · status \(info.statusDescription)")
            Text("state seeking:\(info.isSeeking) speed:\(String(format: "%.2f", playbackState.desiredPlaySpeed))")
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.green)
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
#endif
