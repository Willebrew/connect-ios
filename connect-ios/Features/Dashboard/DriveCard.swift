//
//  DriveCard.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Individual drive card in the list
//

import SwiftUI

struct DriveCard: View {
    let route: Route
    @Environment(AppState.self) private var appState
    @State private var hasRequestedSummary = false
    
    // Cache computed values to reduce re-computation
    private var engagementText: String? {
        guard let events = cachedEvents else { return nil }
        return engagementPercentage(events: events, duration: route.duration)
    }

    private var cachedEvents: [DriveEvent]? {
        appState.routeEventsCache[route.fullname] ?? route.events
    }

    private var cachedLocations: RouteLocations? {
        appState.routeLocationsCache[route.fullname]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Date and time
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.startTimeUtc.dayMonthYear)
                        .font(.headline)

                    Text("\(route.startTimeUtc.timeOnly) - \(route.endTimeUtc.timeOnly)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Preserved/Public badges
                HStack(spacing: 6) {
                    if route.isPreserved {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Color.themeGreen)
                    }

                    if route.isPublic {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            // Route map preview - central visual element
            DriveCardMapPreview(route: route)

            // Stats row
            HStack(spacing: 16) {
                Label(
                    route.duration.hourMinuteDuration,
                    systemImage: "clock"
                )
                .font(.subheadline)

                Label(
                    route.distance.formatDistance(unit: appState.distanceUnit),
                    systemImage: "location"
                )
                .font(.subheadline)

                if let engagementText {
                    Label(
                        engagementText,
                        systemImage: "steeringwheel"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.engagedGreen)
                }
            }
            .foregroundStyle(.secondary)

            // Locations
            if let start = cachedLocations?.start ?? route.startLocation,
               let end = cachedLocations?.end ?? route.endLocation {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        // Start location badge
                        Text("Start")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())

                        Text(start.place)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        // End location badge
                        Text("End")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())

                        Text(end.place)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Timeline preview - engagement visualization
            if let events = cachedEvents {
                TimelinePreview(events: events, duration: route.duration)
                    .frame(height: 8)
                    .drawingGroup() // Render to bitmap for better scroll performance
            } else {
                TimelineSkeletonBar()
                    .frame(height: 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Tap to view drive details")
        .accessibilityAddTraits(.isButton)
        .task(id: route.fullname) {
            guard !hasRequestedSummary else { return }
            if cachedEvents == nil || cachedLocations?.start == nil || cachedLocations?.end == nil {
                hasRequestedSummary = true
                await appState.preloadRouteSummaryData(for: route)
            }
        }
    }

    private func engagementPercentage(events: [DriveEvent], duration: TimeInterval) -> String {
        // Calculate total engaged time
        let totalEngagedTime = events
            .filter { $0.type == .engage }
            .compactMap { event -> TimeInterval? in
                guard let endOffset = event.data.endRouteOffsetMillis else { return nil }
                return endOffset - event.routeOffsetMillis
            }
            .reduce(0, +)

        // Calculate percentage
        guard duration > 0 else { return "0%" }
        let percentage = (totalEngagedTime / duration) * 100
        return String(format: "%.0f%%", percentage)
    }

    private var accessibilityDescription: String {
        var description = "Drive from \(route.startTimeUtc.dayMonthYear) at \(route.startTimeUtc.timeOnly)"
        description += ", duration \(route.duration.hourMinuteDuration)"
        description += ", distance \(route.distance.formatDistance(unit: appState.distanceUnit))"

        if route.isPreserved {
            description += ", preserved"
        }
        if route.isPublic {
            description += ", public"
        }

        if let start = route.startLocation, let end = route.endLocation {
            description += ", from \(start.place) to \(end.place)"
        }
        return description
    }
}

struct TimelineSkeletonBar: View {
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.25))
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.35),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.5)
                    .offset(x: shimmerOffset * geometry.size.width)
                    .blendMode(.screen)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onAppear {
                    shimmerOffset = -0.8
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                        shimmerOffset = 1.2
                    }
                }
        }
    }
}

struct TimelinePreview: View {
    let events: [DriveEvent]
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Base color (driving)
                Rectangle()
                    .fill(Color.drivingBlue.opacity(0.3))

                // Engaged segments
                ForEach(events.filter { $0.type == .engage }) { event in
                    if let endOffset = event.data.endRouteOffsetMillis {
                        let startX = geometry.size.width * (event.routeOffsetMillis / duration)
                        let endX = geometry.size.width * (endOffset / duration)
                        let width = endX - startX

                        Rectangle()
                            .fill(Color.engagedGreen.opacity(0.7))
                            .frame(width: max(1, width))
                            .offset(x: startX)
                    }
                }

                // Overriding segments (gray - when user takes control)
                ForEach(events.filter { $0.type == .overriding }) { event in
                    if let endOffset = event.data.endRouteOffsetMillis {
                        let startX = geometry.size.width * (event.routeOffsetMillis / duration)
                        let endX = geometry.size.width * (endOffset / duration)
                        let width = endX - startX

                        Rectangle()
                            .fill(Color.engagedGrey.opacity(0.7))
                            .frame(width: max(1, width))
                            .offset(x: startX)
                    }
                }

                // Alerts
                ForEach(events.filter { $0.type == .alert }) { event in
                    let x = geometry.size.width * (event.routeOffsetMillis / duration)
                    let color: Color = {
                        switch event.data.alertStatus {
                        case .critical: return Color.alertRed
                        case .userPrompt: return Color.alertOrange
                        default: return .yellow
                        }
                    }()

                    Rectangle()
                        .fill(color)
                        .frame(width: 2)
                        .offset(x: x)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    ScrollView {
        VStack {
            DriveCard(route: Route(
                fullname: "test|2024-01-15--12-30-00",
                logId: "2024-01-15--12-30-00",
                dongleId: "test",
                duration: 1800000,
                distance: 12.5,
                startLat: 37.7749,
                startLng: -122.4194,
                endLat: 37.8044,
                endLng: -122.2712
            ))
        }
        .padding()
    }
    .environment(AppState.shared)
}
