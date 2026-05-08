//
//  DriveCardMapPreview.swift
//  connect-ios
//
//  Created by Claude on 12/26/24.
//
//  Static route map preview using MKMapSnapshotter for performance
//

import SwiftUI
import MapKit

struct DriveCardMapPreview: View {
    let route: Route
    @Environment(AppState.self) private var appState

    @State private var snapshotImage: UIImage?
    @State private var isGeneratingSnapshot = false
    @State private var hasRequestedCoords = false
    @State private var shimmerOffset: CGFloat = -1

    private var cacheKey: NSString {
        route.fullname as NSString
    }

    private var coordinates: [CLLocationCoordinate2D] {
        // First check the observable cache
        if let cachedCoords = appState.routeCoordinatesCache[route.fullname], !cachedCoords.isEmpty {
            return cachedCoords.sorted { $0.key < $1.key }.map { $0.value.clCoordinate }
        }

        // Then check the route's transient property
        if let coords = route.driveCoords, !coords.isEmpty {
            return coords.sorted { $0.key < $1.key }.map { $0.value.clCoordinate }
        }

        // Fallback: use start/end coordinates if available
        var fallback: [CLLocationCoordinate2D] = []
        if let startCoord = startCoordinate {
            fallback.append(startCoord)
        }
        if let endCoord = endCoordinate {
            fallback.append(endCoord)
        }
        return fallback
    }

    private var hasFullRoute: Bool {
        if let cachedCoords = appState.routeCoordinatesCache[route.fullname], cachedCoords.count > 2 {
            return true
        }
        if let coords = route.driveCoords, coords.count > 2 {
            return true
        }
        return false
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        if let lat = route.startLat, let lng = route.startLng {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return route.driveCoords?.sorted { $0.key < $1.key }.first?.value.clCoordinate
    }

    private var endCoordinate: CLLocationCoordinate2D? {
        if let lat = route.endLat, let lng = route.endLng {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return route.driveCoords?.sorted { $0.key < $1.key }.last?.value.clCoordinate
    }

    private var hasRouteData: Bool {
        startCoordinate != nil || endCoordinate != nil
    }

    var body: some View {
        Group {
            if let image = snapshotImage {
                // Show the map snapshot with fade transition
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .mask(edgeFadeMask)
            } else if hasRouteData {
                // Shimmer skeleton while waiting for coordinates and snapshot
                mapSkeletonView
            }
            // If no route data at all, show nothing
        }
        .animation(.easeInOut(duration: 0.35), value: snapshotImage != nil)
        .task(id: route.fullname) {
            requestCoordsIfNeeded()
            loadFromCacheOrGenerate()
        }
        .onChange(of: hasFullRoute) { wasFullRoute, isNowFullRoute in
            if isNowFullRoute && !wasFullRoute {
                loadFromCacheOrGenerate()
            }
        }
    }
    
    @ViewBuilder
    private var mapSkeletonView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(height: 120)
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.35),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: shimmerOffset * geometry.size.width)
                    .blendMode(.screen)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .onAppear {
                shimmerOffset = -0.7
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.2
                }
            }
    }

    private func loadFromCacheOrGenerate() {
        // Check global cache first
        if let cached = appState.mapSnapshotCache.object(forKey: cacheKey) {
            snapshotImage = cached
            return
        }
        // Generate if we have full route data and not already generating
        guard hasFullRoute, snapshotImage == nil, !isGeneratingSnapshot else { return }
        generateSnapshot()
    }

    private func requestCoordsIfNeeded() {
        guard !hasRequestedCoords, !hasFullRoute else { return }
        hasRequestedCoords = true
        appState.loadRouteCoordinatesInBackground(for: route)
    }

    private func generateSnapshot() {
        guard !coordinates.isEmpty, !isGeneratingSnapshot else { return }

        isGeneratingSnapshot = true

        let coords = coordinates
        let key = cacheKey

        Task.detached(priority: .utility) {
            let image = await self.createMapSnapshot(coordinates: coords)
            await MainActor.run {
                if let image {
                    self.appState.mapSnapshotCache.setObject(image, forKey: key)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        self.snapshotImage = image
                    }
                }
                self.isGeneratingSnapshot = false
            }
        }
    }

    private func createMapSnapshot(
        coordinates: [CLLocationCoordinate2D]
    ) async -> UIImage? {
        guard coordinates.count >= 2 else { return nil }

        // Calculate region
        let lats = coordinates.map { $0.latitude }
        let lngs = coordinates.map { $0.longitude }

        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLng = lngs.min(),
              let maxLng = lngs.max() else { return nil }

        let latPadding = (maxLat - minLat) * 0.35
        let lngPadding = (maxLng - minLng) * 0.35

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLng + maxLng) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) + latPadding, 0.01),
                longitudeDelta: max((maxLng - minLng) + lngPadding, 0.01)
            )
        )

        // Configure snapshotter
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 400, height: 160) // 2x for retina
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()

            // Draw the route on the snapshot
            let image = UIGraphicsImageRenderer(size: snapshot.image.size).image { context in
                // Draw the map
                snapshot.image.draw(at: .zero)

                // Draw route polyline
                if coordinates.count >= 2 {
                    let path = UIBezierPath()

                    for (index, coord) in coordinates.enumerated() {
                        let point = snapshot.point(for: coord)
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }

                    // Draw stroke
                    let routeColor = UIColor(Color.themeGreen)
                    routeColor.setStroke()
                    path.lineWidth = 3.0
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }

                // Draw start marker (green)
                if let startCoord = coordinates.first {
                    let startPoint = snapshot.point(for: startCoord)
                    drawMarker(at: startPoint, color: .systemGreen, in: context.cgContext)
                }

                // Draw end marker (red)
                if coordinates.count > 1, let endCoord = coordinates.last {
                    let endPoint = snapshot.point(for: endCoord)
                    drawMarker(at: endPoint, color: .systemRed, in: context.cgContext)
                }
            }

            return image
        } catch {
            return nil
        }
    }

    private func drawMarker(at point: CGPoint, color: UIColor, in context: CGContext) {
        let radius: CGFloat = 6
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        // Fill
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)

        // White border
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect)
    }

    private var edgeFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)

            Rectangle()
                .fill(.black)

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            DriveCardMapPreview(route: Route(
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
            .padding()
        }
    }
}
