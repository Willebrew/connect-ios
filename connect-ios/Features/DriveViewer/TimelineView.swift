//
//  TimelineView.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Interactive timeline scrubber with events
//

import SwiftUI

struct TimelineView: View {
    let route: Route
    @Bindable var playbackState: PlaybackState
    var thumbnailService: VideoThumbnailService?
    var isCompact: Bool = false

    @State private var isDragging = false
    @State private var dragOffset: TimeInterval = 0
    @State private var wasPlayingBeforeDrag = false
    @State private var seekDebounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: isCompact ? 2 : 4) {
            if isCompact {
                Spacer()
                    .frame(height: 12)
            }

            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let playheadWidth = TimelinePlayhead.width
                let horizontalInset = playheadWidth / 2
                let trackWidth = max(1, totalWidth - playheadWidth)
                let dragMax = max(horizontalInset, totalWidth - horizontalInset)
                let dragRange = horizontalInset...dragMax
                let trackHeight: CGFloat = isCompact ? 32 : 40

                // Event visualization
                ZStack(alignment: .leading) {
                    // Base track
                    Rectangle()
                        .fill(Color.drivingBlue.opacity(0.2))
                        .frame(width: trackWidth, height: trackHeight)

                    // Engaged segments
                    if let events = route.events {
                        ForEach(events.filter { $0.type == .engage }) { event in
                            if let endOffset = event.data.endRouteOffsetMillis {
                                let startX = xPosition(for: event.routeOffsetMillis, in: trackWidth)
                                let endX = xPosition(for: endOffset, in: trackWidth)
                                let width = endX - startX

                                Rectangle()
                                    .fill(Color.engagedGreen.opacity(0.5))
                                    .frame(width: max(2, width), height: trackHeight)
                                    .offset(x: startX)
                            }
                        }

                        // Overriding segments (gray - when user takes control)
                        ForEach(events.filter { $0.type == .overriding }) { event in
                            if let endOffset = event.data.endRouteOffsetMillis {
                                let startX = xPosition(for: event.routeOffsetMillis, in: trackWidth)
                                let endX = xPosition(for: endOffset, in: trackWidth)
                                let width = endX - startX

                                Rectangle()
                                    .fill(Color.engagedGrey.opacity(0.5))
                                    .frame(width: max(2, width), height: trackHeight)
                                    .offset(x: startX)
                            }
                        }

                        // Alert markers
                        ForEach(events.filter { $0.type == .alert }) { event in
                            let x = xPosition(for: event.routeOffsetMillis, in: trackWidth)
                            let color: Color = {
                                switch event.data.alertStatus {
                                case .critical: return Color.alertRed
                                case .userPrompt: return Color.alertOrange
                                default: return .yellow
                                }
                            }()

                            Rectangle()
                                .fill(color)
                                .frame(width: 3, height: trackHeight)
                                .offset(x: x)
                        }
                    }
                }
                .frame(width: trackWidth, height: trackHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, horizontalInset)
                .overlay(alignment: .leading) {
                    let displayOffset = isDragging ? dragOffset : playbackState.currentOffset
                    let rawXPos = xPosition(for: displayOffset, in: trackWidth)
                    let playheadX = rawXPos.clamped(to: 0...trackWidth) + horizontalInset

                    TimelinePlayhead(isDragging: isDragging, height: trackHeight)
                        .offset(x: playheadX - (TimelinePlayhead.width / 2))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            // Scrub playback position
                            let clampedLocation = value.location.x.clamped(to: dragRange)
                            let relativeX = (clampedLocation - horizontalInset).clamped(to: 0...trackWidth)
                            dragOffset = offsetFrom(x: relativeX, width: trackWidth)

                            if !isDragging {
                                // Track if video was playing before we started dragging
                                wasPlayingBeforeDrag = playbackState.isPlaying
                                // Pause immediately when starting to drag
                                if wasPlayingBeforeDrag {
                                    playbackState.pause()
                                }
                            }
                            isDragging = true

                            // Debounce video seeks to avoid overwhelming AVPlayer
                            seekDebounceTask?.cancel()
                            seekDebounceTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    playbackState.seek(to: dragOffset)
                                }
                            }
                        }
                        .onEnded { _ in
                            // Cancel any pending debounced seek
                            seekDebounceTask?.cancel()
                            
                            // Perform final seek to exact position
                            playbackState.seek(to: dragOffset)
                            
                            isDragging = false
                            // Resume playing if it was playing before drag
                            if wasPlayingBeforeDrag {
                                playbackState.play()
                                wasPlayingBeforeDrag = false
                            }
                        }
                )
            }
            .frame(height: isCompact ? 50 : 60)

            // Event status indicator - right below timeline (hidden in compact mode)
            if !isCompact {
                EventStatusIndicator(route: route, playbackState: playbackState)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }

            // Time labels with centered segment indicator
            HStack {
                TimeDisplay(offset: isDragging ? dragOffset : playbackState.currentOffset)
                    .font(isCompact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                    .foregroundStyle(.white)

                Spacer()
                
                // Segment indicator - centered
                if let segment = route.segmentNumber(for: isDragging ? dragOffset : playbackState.currentOffset) {
                    Text("Segment \(segment)")
                        .font(isCompact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()

                Text(route.duration.hourMinuteDuration)
                    .font(isCompact ? .caption2 : .caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal)
    }

    private func xPosition(for offset: TimeInterval, in width: CGFloat) -> CGFloat {
        guard route.duration > 0 else { return 0 }
        let progress = offset / route.duration
        return width * progress
    }

    private func offsetFrom(x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        let progress = x / width
        return route.duration * progress
    }
}

private struct TimelinePlayhead: View {
    static let width: CGFloat = 34
    let isDragging: Bool
    let height: CGFloat

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.0),
                            .white.opacity(0.3),
                            .white.opacity(0.6),
                            .white.opacity(0.3),
                            .white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: height)
                .shadow(color: .white.opacity(0.2), radius: 4, y: 0)

            if #available(iOS 26.0, *) {
                Circle()
                    .fill(.white.opacity(isDragging ? 0.35 : 0.25))
                    .frame(width: isDragging ? 36 : 32, height: isDragging ? 36 : 32)
                    .overlay {
                        Circle()
                            .fill(.white)
                            .frame(width: isDragging ? 24 : 20, height: isDragging ? 24 : 20)
                            .glassEffect(.regular, in: Circle())
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
            } else {
                Circle()
                    .fill(.white.opacity(isDragging ? 0.35 : 0.25))
                    .frame(width: isDragging ? 36 : 32, height: isDragging ? 36 : 32)
                    .overlay {
                        Circle()
                            .fill(.white)
                            .frame(width: isDragging ? 24 : 20, height: isDragging ? 24 : 20)
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
            }
        }
        .frame(width: TimelinePlayhead.width, height: height)
        .shadow(color: .white.opacity(isDragging ? 0.5 : 0.35), radius: isDragging ? 8 : 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
    }
}

struct EventStatusIndicator: View {
    let route: Route
    @Bindable var playbackState: PlaybackState

    var body: some View {
        let status = currentEventStatus

        Text(status.text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(status.color.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(status.color.opacity(0.4), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
    
    /// Returns the current segment number for display elsewhere
    var currentSegment: Int? {
        route.segmentNumber(for: playbackState.currentOffset)
    }

    private var currentEventStatus: EventStatus {
        guard let events = route.events else {
            return EventStatus(text: "Loading...", color: .gray)
        }

        let offset = playbackState.currentOffset

        // Check for alerts at current position (highest priority)
        for event in events where event.type == .alert {
            if abs(event.routeOffsetMillis - offset) < 500 { // Within 500ms
                switch event.data.alertStatus {
                case .critical:
                    return EventStatus(text: "Critical Alert", color: .alertRed)
                case .userPrompt:
                    return EventStatus(text: "User Prompt", color: .alertOrange)
                case .normal:
                    return EventStatus(text: "Alert", color: .yellow)
                case .none:
                    return EventStatus(text: "Alert", color: .yellow)
                }
            }
        }

        // Check for engaged segments
        for event in events where event.type == .engage {
            if let endOffset = event.data.endRouteOffsetMillis {
                if offset >= event.routeOffsetMillis && offset <= endOffset {
                    return EventStatus(text: "Engaged", color: .engagedGreen)
                }
            }
        }

        // Check for overriding segments
        for event in events where event.type == .overriding {
            if let endOffset = event.data.endRouteOffsetMillis {
                if offset >= event.routeOffsetMillis && offset <= endOffset {
                    return EventStatus(text: "Override", color: .engagedGrey)
                }
            }
        }

        // Default to disengaged
        return EventStatus(text: "Disengaged", color: .drivingBlue)
    }
}

private struct EventStatus {
    let text: String
    let color: Color
}

struct PlaybackControls: View {
    @Bindable var playbackState: PlaybackState

    var body: some View {
        HStack(spacing: 0) {
            // Mute/Unmute (left)
            Button {
                HapticManager.toggle()
                playbackState.toggleMute()
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

            Spacer()

            // Play/Pause (center)
            Button {
                HapticManager.toggle()
                if playbackState.isPlaying {
                    playbackState.pause()
                } else {
                    playbackState.play()
                }
            } label: {
                if #available(iOS 26.0, *) {
                    Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .glassEffect(.regular, in: Circle())
                } else {
                    Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Spacer()

            // Speed control (right) - tap to cycle through speeds
            Button {
                HapticManager.selection()
                playbackState.cycleSpeed()
            } label: {
                if #available(iOS 26.0, *) {
                    Text(String(format: "%.2gx", playbackState.preferredPlaySpeed))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: Circle())
                } else {
                    Text(String(format: "%.2gx", playbackState.preferredPlaySpeed))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
    }
}

struct TimeDisplay: View {
    let offset: TimeInterval

    var body: some View {
        Text(timeString(from: offset))
    }

    private func timeString(from offset: TimeInterval) -> String {
        let totalSeconds = Int(offset / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound))
    }
}
